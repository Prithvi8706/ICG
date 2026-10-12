/* One-pass intermediate code generator with backpatching.
 * Translation scheme: Aho, Lam, Sethi, Ullman, Compilers (2nd ed.), sec. 6.7.
 *
 * Sections: 1. declarations   2. grammar + semantic actions
 *           3. helpers: quad table, patch lists, loop stack, trace,
 *              symbol table, main */

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
#include <stdarg.h>
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
void       emit_goto(int target);
char      *newtemp(void);
PatchList *makelist(int instr);
PatchList *merge(PatchList *p1, PatchList *p2);
void       backpatch(PatchList *p, int target);
void       loop_begin(void);
PatchList *loop_end(int continue_target);
void       loop_jump(int is_break, int line);
void       rule(const char *production);
void       symtab_insert(char *name, int line);

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
    int        instr;     /* M, W */
}

%define parse.error verbose
%locations   /* @n.first_line: the line of the n-th symbol */
%expect 0

/* The quoted names are what syntax error messages show. */
%token <str> ID "identifier" NUM "number" RELOP "relational operator"
%token IF "if" ELSE "else" WHILE "while" DO "do" FOR "for"
%token BREAK "break" CONTINUE "continue" TRUE "true" FALSE "false"
%token AND "&&" OR "||" NOT "!"

/* Dangling else: an else binds to the nearest if, because shifting ELSE
 * (higher precedence) beats reducing the else-less if rule. */
%precedence LOWER_THAN_ELSE
%precedence ELSE

%left OR
%left AND
%precedence NOT
%left '+' '-'
%left '*' '/'
%precedence UMINUS

%type <addr> E
%type <b> B
%type <nextlist> S L N
%type <instr> M W

%%

program
    : L                 { rule("program -> L");
                          backpatch($1, nextinstr);
                          emit(Q_HALT, NULL, NULL, NULL, NULL); }
    ;

L
    : L M S             { rule("L -> L1 M S");
                          backpatch($1, $2); $$ = $3; }
    | S                 { $$ = $1; }
    ;

S
    : A ';'             { $$ = NULL; }
    | IF '(' B ')' M S %prec LOWER_THAN_ELSE
                        { rule("S -> if ( B ) M S1");
                          backpatch($3.truelist, $5);
                          $$ = merge($3.falselist, $6); }
    /* N sits after ELSE rather than before it (as in the textbook) so that
     * after S1 the parser faces a shift/reduce choice on ELSE, which the
     * precedence above resolves, instead of an unresolvable reduce/reduce
     * between N and the else-less if. The goto N emits still lands directly
     * after S1's code, since nothing is emitted while shifting ELSE. */
    | IF '(' B ')' M S ELSE N M S
                        { rule("S -> if ( B ) M1 S1 else N M2 S2");
                          backpatch($3.truelist, $5);
                          backpatch($3.falselist, $9);
                          $$ = merge(merge($6, $8), $10); }
    /* W is M that also opens a loop, so a break or continue in the body
     * knows which loop it leaves. Both kinds are patched when it closes. */
    | WHILE M '(' B ')' W S
                        { rule("S -> while M1 ( B ) W S1");
                          backpatch($7, $2);
                          backpatch($4.truelist, $6);
                          emit_goto($2);
                          $$ = merge($4.falselist, loop_end($2)); }
    | DO W S WHILE '(' M B ')' ';'
                        { rule("S -> do W S1 while ( M B ) ;");
                          backpatch($3, $6);
                          backpatch($7.truelist, $2);
                          $$ = merge($7.falselist, loop_end($6)); }
    /* Code order: init, test, step, goto test, body, goto step. */
    | FOR '(' A ';' M B ';' M A N ')' W S
                        { rule("S -> for ( A1 ; M1 B ; M2 A2 N ) W S1");
                          backpatch($6.truelist, $12);
                          backpatch($10, $5);
                          backpatch($13, $8);
                          emit_goto($8);
                          $$ = merge($6.falselist, loop_end($8)); }
    | BREAK ';'         { rule("S -> break ;");
                          loop_jump(1, @1.first_line); $$ = NULL; }
    | CONTINUE ';'      { rule("S -> continue ;");
                          loop_jump(0, @1.first_line); $$ = NULL; }
    | '{' L '}'         { $$ = $2; }
    ;

A
    : ID '=' E          { symtab_insert($1, @1.first_line);
                          emit(Q_COPY, NULL, $3, NULL, $1); }
    ;

B
    : B OR M B          { rule("B -> B1 || M B2");
                          backpatch($1.falselist, $3);
                          $$.truelist = merge($1.truelist, $4.truelist);
                          $$.falselist = $4.falselist; }
    | B AND M B         { rule("B -> B1 && M B2");
                          backpatch($1.truelist, $3);
                          $$.truelist = $4.truelist;
                          $$.falselist = merge($1.falselist, $4.falselist); }
    | NOT B             { $$.truelist = $2.falselist;
                          $$.falselist = $2.truelist; }
    | '(' B ')'         { $$ = $2; }
    | E RELOP E         { rule("B -> E1 relop E2");
                          $$.truelist = makelist(nextinstr);
                          $$.falselist = makelist(nextinstr + 1);
                          emit(Q_IF, $2, $1, $3, NULL);
                          emit(Q_GOTO, NULL, NULL, NULL, NULL); }
    | TRUE              { rule("B -> true");
                          $$.truelist = makelist(nextinstr);
                          $$.falselist = NULL;
                          emit(Q_GOTO, NULL, NULL, NULL, NULL); }
    | FALSE             { rule("B -> false");
                          $$.truelist = NULL;
                          $$.falselist = makelist(nextinstr);
                          emit(Q_GOTO, NULL, NULL, NULL, NULL); }
    ;

E
    : E '+' E           { $$ = newtemp(); emit(Q_BINOP, "+", $1, $3, $$); }
    | E '-' E           { $$ = newtemp(); emit(Q_BINOP, "-", $1, $3, $$); }
    | E '*' E           { $$ = newtemp(); emit(Q_BINOP, "*", $1, $3, $$); }
    | E '/' E           { $$ = newtemp(); emit(Q_BINOP, "/", $1, $3, $$); }
    | '-' E %prec UMINUS
                        { $$ = newtemp(); emit(Q_UMINUS, NULL, $2, NULL, $$); }
    | '(' E ')'         { $$ = $2; }
    | ID                { symtab_insert($1, @1.first_line); $$ = $1; }
    | NUM               { $$ = $1; }
    ;

M
    : %empty            { $$ = nextinstr; }
    ;

N
    : %empty            { rule("N -> e");
                          $$ = makelist(nextinstr);
                          emit(Q_GOTO, NULL, NULL, NULL, NULL); }
    ;

W
    : %empty            { $$ = nextinstr;
                          loop_begin(); }
    ;

%%

/* ---------- trace ---------- */

static int trace = 0;      /* --trace: print each rule and list operation */
static int step = 0;       /* --step: also wait for Enter after each one */
static FILE *tty = NULL;   /* keyboard for --step, even when stdin is the program */

/* Counters for --stats. */
static int pending = 0, peak_pending = 0, list_entries = 0;

static void trace_event(const char *what, const char *fmt, ...)
{
    char line[64];
    va_list ap;

    if (!trace)
        return;
    va_start(ap, fmt);
    printf("    %-10s ", what);
    vprintf(fmt, ap);
    printf("\n");
    va_end(ap);
    if (step) {
        fflush(stdout);
        if (fgets(line, sizeof line, tty) == NULL)
            step = 0;
    }
}

#define LIST_TEXT 256

/* Writes "{102, 105}" into buf (LIST_TEXT bytes), eliding a list too long
 * to fit. */
static char *list_text(char *buf, PatchList *p)
{
    int n = sprintf(buf, "{");
    for (int i = 0; p != NULL && i < p->size; i++) {
        if (n > LIST_TEXT - 20) {
            n += sprintf(buf + n, ", ...");
            break;
        }
        n += sprintf(buf + n, i ? ", %d" : "%d", p->items[i]);
    }
    sprintf(buf + n, "}");
    return buf;
}

/* Prints the reduction whose action runs next. */
void rule(const char *production)
{
    if (trace)
        printf("%s\n", production);
}

/* ---------- quad table ---------- */

static Quad *quads = NULL;  /* quads[i] is quadruple QUAD_START + i */
static int nquads = 0, capacity = 0, ntemps = 0;

static void format_target(char *buf, int target)
{
    if (target == UNFILLED)
        strcpy(buf, "_");
    else
        sprintf(buf, "%d", target);
}

/* Three-address text of one quad, without its number. */
static void format_tac(char *buf, Quad *q)
{
    char t[16];
    format_target(t, q->target);
    switch (q->kind) {
    case Q_BINOP:  sprintf(buf, "%s = %s %s %s", q->result, q->arg1, q->op, q->arg2); break;
    case Q_UMINUS: sprintf(buf, "%s = minus %s", q->result, q->arg1); break;
    case Q_COPY:   sprintf(buf, "%s = %s", q->result, q->arg1); break;
    case Q_IF:     sprintf(buf, "if %s %s %s goto %s", q->arg1, q->op, q->arg2, t); break;
    case Q_GOTO:   sprintf(buf, "goto %s", t); break;
    case Q_HALT:   strcpy(buf, "halt"); break;
    }
}

static int add_quad(QuadKind kind, char *op, char *arg1, char *arg2, char *result,
                    int target)
{
    char text[256];
    if (nquads == capacity) {
        capacity = capacity ? capacity * 2 : 64;
        quads = realloc(quads, capacity * sizeof *quads);
    }
    quads[nquads] = (Quad){ kind, op, arg1, arg2, result, target };
    if ((kind == Q_IF || kind == Q_GOTO) && target == UNFILLED && ++pending > peak_pending)
        peak_pending = pending;
    format_tac(text, &quads[nquads]);
    trace_event("emit", "%d: %s", nextinstr, text);
    nquads++;
    return nextinstr++;
}

/* Jumps (Q_IF, Q_GOTO) start with an empty target that backpatch fills. */
int emit(QuadKind kind, char *op, char *arg1, char *arg2, char *result)
{
    return add_quad(kind, op, arg1, arg2, result, UNFILLED);
}

/* A backward jump: its target already exists, so nothing is patched. */
void emit_goto(int target)
{
    add_quad(Q_GOTO, NULL, NULL, NULL, NULL, target);
}

char *newtemp(void)
{
    char *name = malloc(16);
    sprintf(name, "t%d", ++ntemps);
    return name;
}

static void print_tac(void)
{
    char text[256];
    for (int i = 0; i < nquads; i++) {
        format_tac(text, &quads[i]);
        printf("%d: %s\n", QUAD_START + i, text);
    }
}

/* Quadruple form: conditional jumps use op "j<" etc., plain jumps "j",
 * and the result column holds the jump target. */
static void print_quads(void)
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
    char a[LIST_TEXT];
    PatchList *p = malloc(sizeof *p);
    p->items = malloc(sizeof *p->items);
    p->items[0] = instr;
    p->size = 1;
    list_entries += 1;
    trace_event("makelist", "%s", list_text(a, p));
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
    list_entries += p->size;
    if (trace) {
        char a[LIST_TEXT], b[LIST_TEXT], c[LIST_TEXT];
        trace_event("merge", "%s + %s = %s", list_text(a, p1), list_text(b, p2),
                    list_text(c, p));
    }
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
    pending -= p->size;
    if (trace) {
        char a[LIST_TEXT];
        trace_event("backpatch", "%s := %d", list_text(a, p), target);
    }
}

/* ---------- loop stack ---------- */

/* One entry per loop being parsed: the break and continue jumps found in
 * its body so far, all still unfilled. */
typedef struct Loop {
    PatchList *breaks;
    PatchList *continues;
    struct Loop *outer;
} Loop;

static Loop *loops = NULL;

void loop_begin(void)
{
    Loop *l = malloc(sizeof *l);
    *l = (Loop){ NULL, NULL, loops };
    loops = l;
    if (trace)
        printf("W -> e (loop opened)\n");
}

/* Sends every continue to continue_target and returns the breaks, which
 * join the loop's nextlist. */
PatchList *loop_end(int continue_target)
{
    Loop *l = loops;
    loops = l->outer;
    backpatch(l->continues, continue_target);
    return l->breaks;
}

void loop_jump(int is_break, int line)
{
    if (loops == NULL) {
        fprintf(stderr, "line %d: %s outside a loop\n", line,
                is_break ? "break" : "continue");
        exit(2);
    }
    PatchList *p = makelist(nextinstr);
    emit(Q_GOTO, NULL, NULL, NULL, NULL);
    if (is_break)
        loops->breaks = merge(loops->breaks, p);
    else
        loops->continues = merge(loops->continues, p);
}

/* ---------- symbol table ---------- */

typedef struct Symbol {
    char *name;
    int line;              /* line where the name first appears; type is always int */
    struct Symbol *next;
} Symbol;

static Symbol *symbols = NULL;          /* in the order names are first reduced */
static Symbol **symbols_end = &symbols;

void symtab_insert(char *name, int line)
{
    for (Symbol *s = symbols; s != NULL; s = s->next)
        if (strcmp(s->name, name) == 0)
            return;
    Symbol *s = malloc(sizeof *s);
    *s = (Symbol){ name, line, NULL };
    *symbols_end = s;
    symbols_end = &s->next;
}

static void print_symbols(void)
{
    printf("%-12s %s\n", "name", "first line");
    for (Symbol *s = symbols; s != NULL; s = s->next)
        printf("%-12s %d\n", s->name, s->line);
    printf("\n");
}

/* ---------- errors and main ---------- */

void yyerror(const char *msg)
{
    fprintf(stderr, "line %d: %s\n", yylineno, msg);
}

static void usage(void)
{
    fprintf(stderr, "usage: icg [--format=tac|quad] [--trace] [--step] [--symbols] [--stats] [file]\n"
                    "  reads stdin when no file is given\n"
                    "  --trace    print every rule, emit, makelist, merge and backpatch\n"
                    "  --step     like --trace, waiting for Enter after each step\n"
                    "  --symbols  print the symbol table before the code\n"
                    "  --stats    print code size and patch-list usage to stderr\n");
}

int main(int argc, char **argv)
{
    const char *format = "tac";
    const char *path = NULL;
    int stats = 0, symbols_wanted = 0;

    for (int i = 1; i < argc; i++) {
        if (strncmp(argv[i], "--format=", 9) == 0)
            format = argv[i] + 9;
        else if (strcmp(argv[i], "--trace") == 0)
            trace = 1;
        else if (strcmp(argv[i], "--step") == 0)
            trace = step = 1;
        else if (strcmp(argv[i], "--symbols") == 0)
            symbols_wanted = 1;
        else if (strcmp(argv[i], "--stats") == 0)
            stats = 1;
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

    if (step) {
#ifdef _WIN32
        tty = fopen("CON", "r");
#else
        tty = fopen("/dev/tty", "r");
#endif
        if (tty == NULL) {
            fprintf(stderr, "icg: --step needs a keyboard\n");
            return 1;
        }
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

    if (trace)
        printf("\n");
    if (symbols_wanted)
        print_symbols();
    if (strcmp(format, "quad") == 0)
        print_quads();
    else
        print_tac();
    if (stats)
        fprintf(stderr, "quads: %d  peak unfilled jumps: %d  patch-list entries: %d\n",
                nquads, peak_pending, list_entries);
    return 0;
}
