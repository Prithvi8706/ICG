#include "quad.h"

#include <stdlib.h>
#include <string.h>

static Quad *quads = NULL;  /* quads[i] is quadruple QUAD_START + i */
static int nquads = 0;
static int capacity = 0;
static int ntemps = 0;

int nextinstr = QUAD_START;

static char *dup(const char *s)
{
    if (s == NULL)
        return NULL;
    char *copy = malloc(strlen(s) + 1);
    strcpy(copy, s);
    return copy;
}

int emit(QuadKind kind, const char *op, const char *arg1,
         const char *arg2, const char *result, int target)
{
    if (nquads == capacity) {
        capacity = capacity ? capacity * 2 : 64;
        quads = realloc(quads, capacity * sizeof *quads);
    }
    Quad *q = &quads[nquads++];
    q->kind = kind;
    q->op = dup(op);
    q->arg1 = dup(arg1);
    q->arg2 = dup(arg2);
    q->result = dup(result);
    q->target = target;
    return nextinstr++;
}

char *newtemp(void)
{
    char name[16];
    sprintf(name, "t%d", ++ntemps);
    return dup(name);
}

Quad *quad_at(int instr)
{
    int i = instr - QUAD_START;
    if (i < 0 || i >= nquads)
        return NULL;
    return &quads[i];
}

static void format_target(char *buf, int target)
{
    if (target == UNFILLED)
        strcpy(buf, "_");
    else
        sprintf(buf, "%d", target);
}

void print_tac(FILE *out)
{
    char t[16];
    for (int i = 0; i < nquads; i++) {
        Quad *q = &quads[i];
        fprintf(out, "%d: ", QUAD_START + i);
        switch (q->kind) {
        case Q_BINOP:
            fprintf(out, "%s = %s %s %s\n", q->result, q->arg1, q->op, q->arg2);
            break;
        case Q_UMINUS:
            fprintf(out, "%s = minus %s\n", q->result, q->arg1);
            break;
        case Q_COPY:
            fprintf(out, "%s = %s\n", q->result, q->arg1);
            break;
        case Q_IF:
            format_target(t, q->target);
            fprintf(out, "if %s %s %s goto %s\n", q->arg1, q->op, q->arg2, t);
            break;
        case Q_GOTO:
            format_target(t, q->target);
            fprintf(out, "goto %s\n", t);
            break;
        case Q_HALT:
            fprintf(out, "halt\n");
            break;
        }
    }
}

/* Quadruple form: conditional jumps use op "j<" etc., plain jumps "j",
 * and the result column holds the jump target. */
void print_quads(FILE *out)
{
    char op[16], result[16];
    fprintf(out, "%-5s %-7s %-7s %-7s %s\n", "#", "op", "arg1", "arg2", "result");
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
            format_target(result, q->target);
            res = result;
        }
        fprintf(out, "%-5d %-7s %-7s %-7s %s\n", QUAD_START + i, op,
                q->arg1 ? q->arg1 : "", q->arg2 ? q->arg2 : "",
                res ? res : "");
    }
}
