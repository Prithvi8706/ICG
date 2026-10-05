#ifndef SYMTAB_H
#define SYMTAB_H

typedef struct Symbol {
    char *name;
    char *type;            /* always "int" in this language */
    int line;              /* line where the name first appears */
    struct Symbol *next;
} Symbol;

Symbol *symtab_lookup(const char *name);
Symbol *symtab_insert(const char *name, int line);  /* returns existing entry if present */

#endif
