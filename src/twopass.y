/* Two-pass baseline for comparison with parser.y (Appel, Modern Compiler
 * Implementation in C, ch. 7; Aho et al. sec. 6.6).
 *
 *   pass 1  parse the program into a syntax tree
 *   pass 2  walk the tree, emitting jumps to symbolic labels L1, L2, ...
 *           and recording where each label is placed
 *   pass 3  replace every label with its quadruple number
 *
 * The code shapes match parser.y, so for any program both print the same
 * quadruples; what differs is when targets become known and what memory is
 * held until then (the whole tree and label table vs. patch lists).
 *
 * Sections: 1. declarations   2. grammar (builds the tree)
 *           3. helpers: tree, quad table, code generation, labels, main */

%code requires {
typedef struct Node Node;
}

%code {
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define QUAD_START 100   /* number of the first quadruple */

typedef enum {
    /* statements */ N_SEQ, N_ASSIGN, N_IF, N_IFELSE, N_WHILE, N_DO, N_FOR,
                     N_BREAK, N_CONTINUE,
    /* conditions */ N_REL, N_AND, N_OR, N_NOT, N_TRUE, N_FALSE,
    /* expressions */ N_BINOP, N_UMINUS, N_LEAF
} NodeKind;

struct Node {
    NodeKind kind;
    char *text;   /* name for ASSIGN and LEAF, operator for REL and BINOP */
    Node *a, *b, *c, *d;
};

Node *node(NodeKind kind, char *text, Node *a, Node *b, Node *c, Node *d);

static int loop_depth = 0;   /* loops open while parsing, to reject a stray break */
static Node *root = NULL;
void check_in_loop(const char *what, int line);

int  yylex(void);
void yyerror(const char *msg);
extern int yylineno;
extern FILE *yyin;
}

%union {
    char *str;    /* ID, NUM, RELOP text */
    Node *node;
}

%define parse.error verbose
%locations   /* @n.first_line: the line of the n-th symbol */
%expect 0

/* Same tokens and names as parser.y, so lexer.l serves both. */
%token <str> ID "identifier" NUM "number" RELOP "relational operator"
%token IF "if" ELSE "else" WHILE "while" DO "do" FOR "for"
%token BREAK "break" CONTINUE "continue" TRUE "true" FALSE "false"
%token AND "&&" OR "||" NOT "!"

%precedence LOWER_THAN_ELSE
%precedence ELSE

%left OR
%left AND
%precedence NOT
%left '+' '-'
%left '*' '/'
%precedence UMINUS

%type <node> L S A B E

%%

program
    : L                 { root = $1; }
    ;

L
    : L S               { $$ = node(N_SEQ, NULL, $1, $2, NULL, NULL); }
    | S                 { $$ = $1; }
    ;

S
    : A ';'             { $$ = $1; }
    | IF '(' B ')' S %prec LOWER_THAN_ELSE
                        { $$ = node(N_IF, NULL, $3, $5, NULL, NULL); }
    | IF '(' B ')' S ELSE S
                        { $$ = node(N_IFELSE, NULL, $3, $5, $7, NULL); }
    | WHILE { loop_depth++; } '(' B ')' S
                        { loop_depth--;
                          $$ = node(N_WHILE, NULL, $4, $6, NULL, NULL); }
    | DO { loop_depth++; } S WHILE '(' B ')' ';'
                        { loop_depth--;
                          $$ = node(N_DO, NULL, $3, $6, NULL, NULL); }
    | FOR { loop_depth++; } '(' A ';' B ';' A ')' S
                        { loop_depth--;
                          $$ = node(N_FOR, NULL, $4, $6, $8, $10); }
    | BREAK ';'         { check_in_loop("break", @1.first_line);
                          $$ = node(N_BREAK, NULL, NULL, NULL, NULL, NULL); }
    | CONTINUE ';'      { check_in_loop("continue", @1.first_line);
                          $$ = node(N_CONTINUE, NULL, NULL, NULL, NULL, NULL); }
    | '{' L '}'         { $$ = $2; }
    ;

A
    : ID '=' E          { $$ = node(N_ASSIGN, $1, $3, NULL, NULL, NULL); }
    ;

B
    : B OR B            { $$ = node(N_OR, NULL, $1, $3, NULL, NULL); }
    | B AND B           { $$ = node(N_AND, NULL, $1, $3, NULL, NULL); }
    | NOT B             { $$ = node(N_NOT, NULL, $2, NULL, NULL, NULL); }
    | '(' B ')'         { $$ = $2; }
    | E RELOP E         { $$ = node(N_REL, $2, $1, $3, NULL, NULL); }
    | TRUE              { $$ = node(N_TRUE, NULL, NULL, NULL, NULL, NULL); }
    | FALSE             { $$ = node(N_FALSE, NULL, NULL, NULL, NULL, NULL); }
    ;

E
    : E '+' E           { $$ = node(N_BINOP, "+", $1, $3, NULL, NULL); }
    | E '-' E           { $$ = node(N_BINOP, "-", $1, $3, NULL, NULL); }
    | E '*' E           { $$ = node(N_BINOP, "*", $1, $3, NULL, NULL); }
    | E '/' E           { $$ = node(N_BINOP, "/", $1, $3, NULL, NULL); }
    | '-' E %prec UMINUS
                        { $$ = node(N_UMINUS, NULL, $2, NULL, NULL, NULL); }
    | '(' E ')'         { $$ = $2; }
    | ID                { $$ = node(N_LEAF, $1, NULL, NULL, NULL, NULL); }
    | NUM               { $$ = node(N_LEAF, $1, NULL, NULL, NULL, NULL); }
    ;

%%

/* ---------- syntax tree ---------- */

static int nnodes = 0;

Node *node(NodeKind kind, char *text, Node *a, Node *b, Node *c, Node *d)
{
    Node *n = malloc(sizeof *n);
    *n = (Node){ kind, text, a, b, c, d };
    nnodes++;
    return n;
}

void check_in_loop(const char *what, int line)
{
    if (loop_depth == 0) {
        fprintf(stderr, "line %d: %s outside a loop\n", line, what);
        exit(2);
    }
}

/* ---------- quad table ---------- */

typedef enum { Q_BINOP, Q_UMINUS, Q_COPY, Q_IF, Q_GOTO, Q_HALT } QuadKind;

typedef struct {
    QuadKind kind;
    char *op, *arg1, *arg2, *result;
    int label;    /* IF and GOTO: symbolic target, set in pass 2 */
    int target;   /* IF and GOTO: quadruple number, set in pass 3 */
} Quad;

static Quad *quads = NULL;  /* quads[i] is quadruple QUAD_START + i */
static int nquads = 0, capacity = 0, ntemps = 0;

static void emit(QuadKind kind, char *op, char *arg1, char *arg2, char *result,
                 int label)
{
    if (nquads == capacity) {
        capacity = capacity ? capacity * 2 : 64;
        quads = realloc(quads, capacity * sizeof *quads);
    }
    quads[nquads++] = (Quad){ kind, op, arg1, arg2, result, label, 0 };
}

static void emit_goto(int label)
{
    emit(Q_GOTO, NULL, NULL, NULL, NULL, label);
}

static char *newtemp(void)
{
    char *name = malloc(16);
    sprintf(name, "t%d", ++ntemps);
    return name;
}

/* ---------- labels ---------- */

static int *label_at = NULL;  /* label_at[L] = index of the quad L is placed before */
static int nlabels = 0, label_cap = 0;

static int newlabel(void)
{
    if (nlabels == label_cap) {
        label_cap = label_cap ? label_cap * 2 : 64;
        label_at = realloc(label_at, label_cap * sizeof *label_at);
    }
    label_at[nlabels] = -1;
    return ++nlabels;   /* labels are numbered from 1 */
}

static void place(int label)
{
    label_at[label - 1] = nquads;
}

/* Pass 3: every jump learns its quadruple number. */
static void resolve_labels(void)
{
    for (int i = 0; i < nquads; i++)
        if (quads[i].kind == Q_IF || quads[i].kind == Q_GOTO) {
            int at = label_at[quads[i].label - 1];
            if (at < 0) {
                fprintf(stderr, "twopass: internal error: L%d never placed\n",
                        quads[i].label);
                exit(3);
            }
            quads[i].target = QUAD_START + at;
        }
}

/* ---------- pass 2: code generation ---------- */

static char *gen_expr(Node *e)
{
    char *a, *b, *t;
    switch (e->kind) {
    case N_LEAF:
        return e->text;
    case N_UMINUS:
        a = gen_expr(e->a);
        t = newtemp();
        emit(Q_UMINUS, NULL, a, NULL, t, 0);
        return t;
    default:  /* N_BINOP */
        a = gen_expr(e->a);
        b = gen_expr(e->b);
        t = newtemp();
        emit(Q_BINOP, e->text, a, b, t, 0);
        return t;
    }
}

/* Jumps to label t when b is true and to f when it is false. */
static void gen_bool(Node *b, int t, int f)
{
    int mid;
    char *x, *y;
    switch (b->kind) {
    case N_REL:
        x = gen_expr(b->a);
        y = gen_expr(b->b);
        emit(Q_IF, b->text, x, y, NULL, t);
        emit_goto(f);
        break;
    case N_AND:
        mid = newlabel();
        gen_bool(b->a, mid, f);
        place(mid);
        gen_bool(b->b, t, f);
        break;
    case N_OR:
        mid = newlabel();
        gen_bool(b->a, t, mid);
        place(mid);
        gen_bool(b->b, t, f);
        break;
    case N_NOT:
        gen_bool(b->a, f, t);
        break;
    case N_TRUE:
        emit_goto(t);
        break;
    default:  /* N_FALSE */
        emit_goto(f);
        break;
    }
}

/* Code for s; control leaves to label next. brk and cont are the targets
 * of break and continue in the innermost enclosing loop. */
static void gen_stmt(Node *s, int next, int brk, int cont)
{
    int t, f, top, step;
    switch (s->kind) {
    case N_SEQ:
        t = newlabel();
        gen_stmt(s->a, t, brk, cont);
        place(t);
        gen_stmt(s->b, next, brk, cont);
        break;
    case N_ASSIGN:
        emit(Q_COPY, NULL, gen_expr(s->a), NULL, s->text, 0);
        break;
    case N_IF:
        t = newlabel();
        gen_bool(s->a, t, next);
        place(t);
        gen_stmt(s->b, next, brk, cont);
        break;
    case N_IFELSE:
        t = newlabel();
        f = newlabel();
        gen_bool(s->a, t, f);
        place(t);
        gen_stmt(s->b, next, brk, cont);
        emit_goto(next);
        place(f);
        gen_stmt(s->c, next, brk, cont);
        break;
    case N_WHILE:
        top = newlabel();
        t = newlabel();
        place(top);
        gen_bool(s->a, t, next);
        place(t);
        gen_stmt(s->b, top, next, top);
        emit_goto(top);
        break;
    case N_DO:
        top = newlabel();
        t = newlabel();   /* the test */
        place(top);
        gen_stmt(s->a, t, next, t);
        place(t);
        gen_bool(s->b, top, next);
        break;
    case N_FOR:
        top = newlabel();
        t = newlabel();   /* the body */
        step = newlabel();
        gen_stmt(s->a, 0, brk, cont);
        place(top);
        gen_bool(s->b, t, next);
        place(step);
        gen_stmt(s->c, 0, brk, cont);
        emit_goto(top);
        place(t);
        gen_stmt(s->d, step, next, step);
        emit_goto(step);
        break;
    case N_BREAK:
        emit_goto(brk);
        break;
    default:  /* N_CONTINUE */
        emit_goto(cont);
        break;
    }
}

/* ---------- printing ---------- */

static void format_tac(char *buf, Quad *q, int symbolic)
{
    char t[16];
    sprintf(t, symbolic ? "L%d" : "%d", symbolic ? q->label : q->target);
    switch (q->kind) {
    case Q_BINOP:  sprintf(buf, "%s = %s %s %s", q->result, q->arg1, q->op, q->arg2); break;
    case Q_UMINUS: sprintf(buf, "%s = minus %s", q->result, q->arg1); break;
    case Q_COPY:   sprintf(buf, "%s = %s", q->result, q->arg1); break;
    case Q_IF:     sprintf(buf, "if %s %s %s goto %s", q->arg1, q->op, q->arg2, t); break;
    case Q_GOTO:   sprintf(buf, "goto %s", t); break;
    case Q_HALT:   strcpy(buf, "halt"); break;
    }
}

static void print_tac(void)
{
    char text[256];
    for (int i = 0; i < nquads; i++) {
        format_tac(text, &quads[i], 0);
        printf("%d: %s\n", QUAD_START + i, text);
    }
}

/* Pass 2 output before pass 3: each label that some jump uses, on its own
 * line where it is placed. */
static void print_labels(void)
{
    char text[256];
    char *used = calloc(nlabels + 1, 1);
    for (int i = 0; i < nquads; i++)
        if (quads[i].kind == Q_IF || quads[i].kind == Q_GOTO)
            used[quads[i].label] = 1;
    for (int i = 0; i < nquads; i++) {
        for (int l = 0; l < nlabels; l++)
            if (label_at[l] == i && used[l + 1])
                printf("L%d:\n", l + 1);
        format_tac(text, &quads[i], 1);
        printf("      %s\n", text);
    }
}

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
            sprintf(t, "%d", q->target);
            res = t;
        }
        printf("%-5d %-7s %-7s %-7s %s\n", QUAD_START + i, op,
               q->arg1 ? q->arg1 : "", q->arg2 ? q->arg2 : "", res ? res : "");
    }
}

/* ---------- errors and main ---------- */

void yyerror(const char *msg)
{
    fprintf(stderr, "line %d: %s\n", yylineno, msg);
}

static void usage(void)
{
    fprintf(stderr, "usage: twopass [--format=tac|quad|labels] [--stats] [file]\n"
                    "  reads stdin when no file is given\n"
                    "  --format=labels  code after pass 2, before labels are resolved\n"
                    "  --stats          print code size, tree and label counts to stderr\n");
}

int main(int argc, char **argv)
{
    const char *format = "tac";
    const char *path = NULL;
    int stats = 0;

    for (int i = 1; i < argc; i++) {
        if (strncmp(argv[i], "--format=", 9) == 0)
            format = argv[i] + 9;
        else if (strcmp(argv[i], "--stats") == 0)
            stats = 1;
        else if (argv[i][0] == '-' || path != NULL) {
            usage();
            return 1;
        } else
            path = argv[i];
    }
    if (strcmp(format, "tac") != 0 && strcmp(format, "quad") != 0
            && strcmp(format, "labels") != 0) {
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

    if (yyparse() != 0)                                       /* pass 1 */
        return 1;

    int end = newlabel();                                     /* pass 2 */
    gen_stmt(root, end, 0, 0);
    place(end);
    emit(Q_HALT, NULL, NULL, NULL, NULL, 0);

    if (strcmp(format, "labels") == 0) {
        print_labels();
    } else {
        resolve_labels();                                     /* pass 3 */
        if (strcmp(format, "quad") == 0)
            print_quads();
        else
            print_tac();
    }
    if (stats)
        fprintf(stderr, "quads: %d  tree nodes: %d  labels: %d\n",
                nquads, nnodes, nlabels);
    return 0;
}
