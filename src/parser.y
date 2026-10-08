/* One-pass intermediate code generator with backpatching.
 * Translation scheme: Aho, Lam, Sethi, Ullman, Compilers (2nd ed.), sec. 6.7.
 *
 * Sections: 1. declarations   2. grammar + semantic actions
 *           3. helpers: quad table, patch lists, symbol table, main */

%code requires {
/* A list of quadruple numbers whose jump target is still unfilled.
 * NULL is the empty list. */
typedef struct {
    int *items;
    int size;
} PatchList;

typedef struct {
    PatchList *truelist;
    PatchList *falselist;
} BoolLists;
}

%code {
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define QUAD_START 100   /* number of the first quadruple */
#define UNFILLED   (-1)  /* jump target not known yet: printed as "_" */

typedef enum {
    Q_BINOP,   /* result = arg1 op arg2        */
    Q_UMINUS,  /* result = minus arg1          */
    Q_COPY,    /* result = arg1                */
    Q_IF,      /* if arg1 op arg2 goto target  */
    Q_GOTO,    /* goto target                  */
    Q_HALT     /* halt                         */
} QuadKind;

typedef struct {
    QuadKind kind;
    char *op;      /* "+", "<", ...; NULL where the kind implies it */
    char *arg1;
    char *arg2;
    char *result;  /* destination name for BINOP, UMINUS, COPY */
    int target;    /* jump target for IF and GOTO, UNFILLED until patched */
} Quad;

int nextinstr = QUAD_START;  /* number the next emitted quadruple will get */

int        emit(QuadKind kind, char *op, char *arg1, char *arg2, char *result);
char      *newtemp(void);
PatchList *makelist(int instr);
PatchList *merge(PatchList *p1, PatchList *p2);
void       backpatch(PatchList *p, int target);
void       symtab_insert(char *name, int line);
void       not_yet(const char *construct);

int  yylex(void);
void yyerror(const char *msg);
extern int yylineno;
extern FILE *yyin;
}

%union {
    char      *str;       /* ID, NUM, RELOP text */
    char      *addr;      /* E: name or temp holding the value */
    BoolLists  b;         /* B */
    PatchList *nextlist;  /* S, L, N */
    int        instr;     /* M */
}

%define parse.error verbose
%expect 0

/* The quoted names are what syntax error messages show. */
%token <str> ID "identifier" NUM "number" RELOP "relational operator"
%token IF "if" ELSE "else" WHILE "while" TRUE "true" FALSE "false"
%token AND "&&" OR "||" NOT "!"

/* Dangling else: an else binds to the nearest if, because shifting ELSE
 * (higher precedence) beats reducing the else-less if rule. */
%nonassoc LOWER_THAN_ELSE
%nonassoc ELSE

%left OR
%left AND
%right NOT
%nonassoc RELOP
%left '+' '-'
%left '*' '/'
%right UMINUS

%type <addr> E
%type <b> B
%type <nextlist> S L N
%type <instr> M

%%

program
    : L                 { backpatch($1, nextinstr);
                          emit(Q_HALT, NULL, NULL, NULL, NULL); }
    ;

L
    : L M S             { backpatch($1, $2); $$ = $3; }
    | S                 { $$ = $1; }
    ;

S
    : ID '=' E ';'      { symtab_insert($1, yylineno);
                          emit(Q_COPY, NULL, $3, NULL, $1);
                          $$ = NULL; }
    | IF '(' B ')' M S %prec LOWER_THAN_ELSE
                        { backpatch($3.truelist, $5);
                          $$ = merge($3.falselist, $6); }
    /* N sits after ELSE rather than before it (as in the textbook) so that
     * after S1 the parser faces a shift/reduce choice on ELSE, which the
     * precedence above resolves, instead of an unresolvable reduce/reduce
     * between N and the else-less if. The goto N emits still lands directly
     * after S1's code, since nothing is emitted while shifting ELSE. */
    | IF '(' B ')' M S ELSE N M S
                        { not_yet("if-else"); $$ = NULL; }
    | WHILE M '(' B ')' M S
                        { not_yet("while"); $$ = NULL; }
    | '{' L '}'         { $$ = $2; }
    ;

B
    : B OR M B          { not_yet("||"); }
    | B AND M B         { not_yet("&&"); }
    | NOT B             { not_yet("!"); }
    | '(' B ')'         { not_yet("parenthesised condition"); }
    | E RELOP E         { $$.truelist = makelist(nextinstr);
                          $$.falselist = makelist(nextinstr + 1);
                          emit(Q_IF, $2, $1, $3, NULL);
                          emit(Q_GOTO, NULL, NULL, NULL, NULL); }
    | TRUE              { not_yet("true"); }
    | FALSE             { not_yet("false"); }
    ;

E
    : E '+' E           { $$ = newtemp(); emit(Q_BINOP, "+", $1, $3, $$); }
    | E '-' E           { $$ = newtemp(); emit(Q_BINOP, "-", $1, $3, $$); }
    | E '*' E           { $$ = newtemp(); emit(Q_BINOP, "*", $1, $3, $$); }
    | E '/' E           { $$ = newtemp(); emit(Q_BINOP, "/", $1, $3, $$); }
    | '-' E %prec UMINUS
                        { $$ = newtemp(); emit(Q_UMINUS, NULL, $2, NULL, $$); }
    | '(' E ')'         { $$ = $2; }
    | ID                { symtab_insert($1, yylineno); $$ = $1; }
    | NUM               { $$ = $1; }
    ;

M
    : %empty            { $$ = nextinstr; }
    ;

N
    : %empty            { $$ = makelist(nextinstr);
                          emit(Q_GOTO, NULL, NULL, NULL, NULL); }
    ;

%%

/* ---------- quad table ---------- */

static Quad *quads = NULL;  /* quads[i] is quadruple QUAD_START + i */
static int nquads = 0, capacity = 0, ntemps = 0;

/* Jumps (Q_IF, Q_GOTO) start with an empty target that backpatch fills. */
int emit(QuadKind kind, char *op, char *arg1, char *arg2, char *result)
{
    if (nquads == capacity) {
        capacity = capacity ? capacity * 2 : 64;
        quads = realloc(quads, capacity * sizeof *quads);
    }
    quads[nquads++] = (Quad){ kind, op, arg1, arg2, result, UNFILLED };
    return nextinstr++;
}

char *newtemp(void)
{
    char *name = malloc(16);
    sprintf(name, "t%d", ++ntemps);
    return name;
}

static void format_target(char *buf, int target)
{
    if (target == UNFILLED)
        strcpy(buf, "_");
    else
        sprintf(buf, "%d", target);
}

void print_tac(void)
{
    char t[16];
    for (int i = 0; i < nquads; i++) {
        Quad *q = &quads[i];
        printf("%d: ", QUAD_START + i);
        format_target(t, q->target);
        switch (q->kind) {
        case Q_BINOP:  printf("%s = %s %s %s\n", q->result, q->arg1, q->op, q->arg2); break;
        case Q_UMINUS: printf("%s = minus %s\n", q->result, q->arg1); break;
        case Q_COPY:   printf("%s = %s\n", q->result, q->arg1); break;
        case Q_IF:     printf("if %s %s %s goto %s\n", q->arg1, q->op, q->arg2, t); break;
        case Q_GOTO:   printf("goto %s\n", t); break;
        case Q_HALT:   printf("halt\n"); break;
        }
    }
}

/* Quadruple form: conditional jumps use op "j<" etc., plain jumps "j",
 * and the result column holds the jump target. */
void print_quads(void)
{
    char op[16], t[16];
    printf("%-5s %-7s %-7s %-7s %s\n", "#", "op", "arg1", "arg2", "result");
    for (int i = 0; i < nquads; i++) {
        Quad *q = &quads[i];
        const char *res = q->result;
        switch (q->kind) {
        case Q_BINOP:  strcpy(op, q->op); break;
        case Q_UMINUS: strcpy(op, "uminus"); break;
        case Q_COPY:   strcpy(op, "="); break;
        case Q_IF:     sprintf(op, "j%s", q->op); break;
        case Q_GOTO:   strcpy(op, "j"); break;
        case Q_HALT:   strcpy(op, "halt"); break;
        }
        if (q->kind == Q_IF || q->kind == Q_GOTO) {
            format_target(t, q->target);
            res = t;
        }
        printf("%-5d %-7s %-7s %-7s %s\n", QUAD_START + i, op,
               q->arg1 ? q->arg1 : "", q->arg2 ? q->arg2 : "", res ? res : "");
    }
}

/* ---------- patch lists ---------- */

PatchList *makelist(int instr)
{
    PatchList *p = malloc(sizeof *p);
    p->items = malloc(sizeof *p->items);
    p->items[0] = instr;
    p->size = 1;
    return p;
}

PatchList *merge(PatchList *p1, PatchList *p2)
{
    if (p1 == NULL)
        return p2;
    if (p2 == NULL)
        return p1;
    PatchList *p = malloc(sizeof *p);
    p->size = p1->size + p2->size;
    p->items = malloc(p->size * sizeof *p->items);
    memcpy(p->items, p1->items, p1->size * sizeof *p->items);
    memcpy(p->items + p1->size, p2->items, p2->size * sizeof *p->items);
    return p;
}

void backpatch(PatchList *p, int target)
{
    if (p == NULL)
        return;
    for (int i = 0; i < p->size; i++) {
        int k = p->items[i] - QUAD_START;
        /* Every listed quad must be a jump that nobody has filled yet;
         * anything else means a semantic action is wrong. */
        if (k < 0 || k >= nquads || (quads[k].kind != Q_IF && quads[k].kind != Q_GOTO)
                || quads[k].target != UNFILLED) {
            fprintf(stderr, "icg: internal error: bad backpatch of %d to %d\n",
                    p->items[i], target);
            exit(3);
        }
        quads[k].target = target;
    }
}

/* ---------- symbol table ---------- */

typedef struct Symbol {
    char *name;
    int line;              /* line where the name first appears; type is always int */
    struct Symbol *next;
} Symbol;

static Symbol *symbols = NULL;

void symtab_insert(char *name, int line)
{
    for (Symbol *s = symbols; s != NULL; s = s->next)
        if (strcmp(s->name, name) == 0)
            return;
    Symbol *s = malloc(sizeof *s);
    *s = (Symbol){ name, line, symbols };
    symbols = s;
}

/* ---------- errors and main ---------- */

void yyerror(const char *msg)
{
    fprintf(stderr, "line %d: %s\n", yylineno, msg);
}

/* Rules whose actions are scheduled for Review 2 stop here instead of
 * emitting wrong code. */
void not_yet(const char *construct)
{
    fprintf(stderr, "line %d: %s is not implemented yet\n", yylineno, construct);
    exit(2);
}

static void usage(void)
{
    fprintf(stderr, "usage: icg [--format=tac|quad] [file]\n"
                    "  reads stdin when no file is given\n");
}

int main(int argc, char **argv)
{
    const char *format = "tac";
    const char *path = NULL;

    for (int i = 1; i < argc; i++) {
        if (strncmp(argv[i], "--format=", 9) == 0)
            format = argv[i] + 9;
        else if (argv[i][0] == '-' || path != NULL) {
            usage();
            return 1;
        } else
            path = argv[i];
    }
    if (strcmp(format, "tac") != 0 && strcmp(format, "quad") != 0) {
        usage();
        return 1;
    }

    if (path != NULL) {
        yyin = fopen(path, "r");
        if (yyin == NULL) {
            perror(path);
            return 1;
        }
    } else if (isatty(fileno(stdin))) {
#ifdef _WIN32
        fprintf(stderr, "Type a program, then press Ctrl+Z and Enter to compile it.\n");
#else
        fprintf(stderr, "Type a program, then press Ctrl+D to compile it.\n");
#endif
    }

    if (yyparse() != 0)
        return 1;

    if (strcmp(format, "quad") == 0)
        print_quads();
    else
        print_tac();
    return 0;
}
