#include "symtab.h"

#include <stdlib.h>
#include <string.h>

static Symbol *head = NULL;

Symbol *symtab_lookup(const char *name)
{
    for (Symbol *s = head; s != NULL; s = s->next)
        if (strcmp(s->name, name) == 0)
            return s;
    return NULL;
}

Symbol *symtab_insert(const char *name, int line)
{
    Symbol *s = symtab_lookup(name);
    if (s != NULL)
        return s;
    s = malloc(sizeof *s);
    s->name = malloc(strlen(name) + 1);
    strcpy(s->name, name);
    s->type = "int";
    s->line = line;
    s->next = head;
    head = s;
    return s;
}
