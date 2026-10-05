#ifndef BACKPATCH_H
#define BACKPATCH_H

/* A list of quadruple numbers whose jump target is still unfilled.
 * NULL is the empty list. */
typedef struct {
    int *items;
    int size;
} PatchList;

PatchList *makelist(int instr);
PatchList *merge(PatchList *p1, PatchList *p2);
void       backpatch(PatchList *p, int target);

#endif
