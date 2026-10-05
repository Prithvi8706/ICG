#ifndef QUAD_H
#define QUAD_H

#include <stdio.h>

#define QUAD_START 100   /* number of the first quadruple */
#define UNFILLED   (-1)  /* jump target not known yet: printed as "_" */

typedef enum {
    Q_BINOP,   /* result = arg1 op arg2           */
    Q_UMINUS,  /* result = minus arg1             */
    Q_COPY,    /* result = arg1                   */
    Q_IF,      /* if arg1 op arg2 goto target     */
    Q_GOTO,    /* goto target                     */
    Q_HALT     /* halt                            */
} QuadKind;

typedef struct {
    QuadKind kind;
    char *op;      /* "+", "<", ...; NULL where the kind implies it */
    char *arg1;
    char *arg2;
    char *result;  /* destination name for BINOP, UMINUS, COPY */
    int target;    /* jump target for IF and GOTO, UNFILLED until patched */
} Quad;

extern int nextinstr;  /* number the next emitted quadruple will get */

int   emit(QuadKind kind, const char *op, const char *arg1,
           const char *arg2, const char *result, int target);
char *newtemp(void);
Quad *quad_at(int instr);

void  print_tac(FILE *out);    /* 100: if a < b goto 102 */
void  print_quads(FILE *out);  /* op / arg1 / arg2 / result table */

#endif
