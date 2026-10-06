%{
/* One-pass intermediate code generator with backpatching.
 * Translation scheme: Aho, Lam, Sethi, Ullman, Compilers (2nd ed.), sec. 6.7. */
#include <stdio.h>
#include <stdlib.h>
#include "quad.h"
#include "symtab.h"

int yylex(void);
void yyerror(const char *msg);
extern int yylineno;

/* Rules whose actions are scheduled for Review 2 stop here instead of
 * emitting wrong code. */
static void not_yet(const char *construct)
{
    fprintf(stderr, "line %d: %s is not implemented yet\n", yylineno, construct);
    exit(2);
}
%}

%code requires {
#include "backpatch.h"

typedef struct {
    PatchList *truelist;
    PatchList *falselist;
} BoolLists;
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
                          emit(Q_HALT, NULL, NULL, NULL, NULL, UNFILLED); }
    ;

L
    : L M S             { backpatch($1, $2); $$ = $3; }
    | S                 { $$ = $1; }
    ;

S
    : ID '=' E ';'      { symtab_insert($1, yylineno);
                          emit(Q_COPY, NULL, $3, NULL, $1, UNFILLED);
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
                          emit(Q_IF, $2, $1, $3, NULL, UNFILLED);
                          emit(Q_GOTO, NULL, NULL, NULL, NULL, UNFILLED); }
    | TRUE              { not_yet("true"); }
    | FALSE             { not_yet("false"); }
    ;

E
    : E '+' E           { $$ = newtemp(); emit(Q_BINOP, "+", $1, $3, $$, UNFILLED); }
    | E '-' E           { $$ = newtemp(); emit(Q_BINOP, "-", $1, $3, $$, UNFILLED); }
    | E '*' E           { $$ = newtemp(); emit(Q_BINOP, "*", $1, $3, $$, UNFILLED); }
    | E '/' E           { $$ = newtemp(); emit(Q_BINOP, "/", $1, $3, $$, UNFILLED); }
    | '-' E %prec UMINUS
                        { $$ = newtemp(); emit(Q_UMINUS, NULL, $2, NULL, $$, UNFILLED); }
    | '(' E ')'         { $$ = $2; }
    | ID                { symtab_insert($1, yylineno); $$ = $1; }
    | NUM               { $$ = $1; }
    ;

M
    : %empty            { $$ = nextinstr; }
    ;

N
    : %empty            { $$ = makelist(nextinstr);
                          emit(Q_GOTO, NULL, NULL, NULL, NULL, UNFILLED); }
    ;

%%

void yyerror(const char *msg)
{
    fprintf(stderr, "line %d: %s\n", yylineno, msg);
}
