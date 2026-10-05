#include <stdio.h>
#include <string.h>

#include "quad.h"

extern FILE *yyin;
int yyparse(void);

static void usage(void)
{
    fprintf(stderr, "usage: icg [--format=tac|quad] [file]\n"
                    "  reads stdin when no file is given\n");
}

int main(int argc, char **argv)
{
    const char *format = "tac";
    const char *path = NULL;

    for (int i = 1; i < argc; i++) {
        if (strncmp(argv[i], "--format=", 9) == 0) {
            format = argv[i] + 9;
        } else if (argv[i][0] == '-' && argv[i][1] != '\0') {
            usage();
            return 1;
        } else if (path == NULL) {
            path = argv[i];
        } else {
            usage();
            return 1;
        }
    }
    if (strcmp(format, "tac") != 0 && strcmp(format, "quad") != 0) {
        usage();
        return 1;
    }

    if (path != NULL) {
        yyin = fopen(path, "r");
        if (yyin == NULL) {
            perror(path);
            return 1;
        }
    }

    if (yyparse() != 0)
        return 1;

    if (strcmp(format, "quad") == 0)
        print_quads(stdout);
    else
        print_tac(stdout);
    return 0;
}
