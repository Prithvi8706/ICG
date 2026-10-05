#include "backpatch.h"
#include "quad.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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
        Quad *q = quad_at(p->items[i]);
        /* Every listed quad must be a jump that nobody has filled yet;
         * anything else means a semantic action is wrong. */
        if (q == NULL || (q->kind != Q_IF && q->kind != Q_GOTO)
                || q->target != UNFILLED) {
            fprintf(stderr, "icg: internal error: bad backpatch of %d to %d\n",
                    p->items[i], target);
            exit(3);
        }
        q->target = target;
    }
}
