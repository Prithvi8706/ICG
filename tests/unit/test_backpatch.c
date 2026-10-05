/* Unit test for makelist / merge / backpatch: emit two empty jumps,
 * collect them in one list and fill both with a single backpatch. */
#include <stdio.h>
#include <stdlib.h>

#include "backpatch.h"
#include "quad.h"

static int failures = 0;

static void check(int ok, const char *what)
{
    printf("%s  %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        failures++;
}

int main(void)
{
    int j1 = emit(Q_IF, "<", "a", "b", NULL, UNFILLED);   /* 100 */
    int j2 = emit(Q_GOTO, NULL, NULL, NULL, NULL, UNFILLED); /* 101 */

    PatchList *p1 = makelist(j1);
    PatchList *p2 = makelist(j2);
    check(p1->size == 1 && p1->items[0] == 100, "makelist(100) holds only 100");

    PatchList *both = merge(p1, p2);
    check(both->size == 2 && both->items[0] == 100 && both->items[1] == 101,
          "merge gives [100, 101]");
    check(merge(NULL, p2) == p2 && merge(p1, NULL) == p1,
          "merge with an empty list returns the other list");

    check(quad_at(100)->target == UNFILLED && quad_at(101)->target == UNFILLED,
          "jumps start unfilled");
    backpatch(both, 102);
    check(quad_at(100)->target == 102 && quad_at(101)->target == 102,
          "backpatch fills both jumps with 102");

    backpatch(NULL, 999);
    check(1, "backpatch of an empty list is a no-op");

    return failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
