%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "parser.tab.h"

static char *dup_text(void)
{
    char *s = malloc(yyleng + 1);
    strcpy(s, yytext);
    return s;
}
%}

%option noyywrap yylineno nounput noinput

%%

[ \t\r]+                ;
\n                      ;
"//".*                  ;

"if"                    return IF;
"else"                  return ELSE;
"while"                 return WHILE;
"true"                  return TRUE;
"false"                 return FALSE;

[A-Za-z_][A-Za-z0-9_]*  { yylval.str = dup_text(); return ID; }
[0-9]+                  { yylval.str = dup_text(); return NUM; }

"<="|">="|"=="|"!="|"<"|">"  { yylval.str = dup_text(); return RELOP; }
"&&"                    return AND;
"||"                    return OR;
"!"                     return NOT;

[-+*/=;(){}]            return yytext[0];

.                       {
                            fprintf(stderr, "line %d: unexpected character '%s'\n",
                                    yylineno, yytext);
                            exit(1);
                        }

%%
