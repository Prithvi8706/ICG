# Build both generators and run every test with:  make test
# On Windows use mingw32-make from Git Bash (the recipes need sh).
# Without make, the same build is (from src/):
#   flex lexer.l && bison -d parser.y && gcc lex.yy.c parser.tab.c -o icg
#   bison -d -o parser.tab.c twopass.y && gcc lex.yy.c parser.tab.c -o twopass
#
# lexer.l includes "parser.tab.h", so each grammar's header goes in its own
# directory and lex.yy.c is compiled once against each.

ifeq ($(OS),Windows_NT)
FLEX  ?= win_flex
BISON ?= win_bison
EXE   := .exe
else
FLEX  ?= flex
BISON ?= bison
EXE   :=
endif

CC     = gcc
CFLAGS = -std=gnu99 -Wall -Wextra -Wno-unused-function -g

ICG     = icg$(EXE)
TWOPASS = twopass$(EXE)

all: $(ICG) $(TWOPASS)

$(ICG): build/icg/parser.tab.c build/lex.yy.c
	$(CC) $(CFLAGS) -Ibuild/icg -o $@ build/lex.yy.c build/icg/parser.tab.c

$(TWOPASS): build/twopass/parser.tab.c build/lex.yy.c
	$(CC) $(CFLAGS) -Ibuild/twopass -o $@ build/lex.yy.c build/twopass/parser.tab.c

build/icg/parser.tab.c: src/parser.y
	mkdir -p build/icg
	$(BISON) -d -o $@ src/parser.y

build/twopass/parser.tab.c: src/twopass.y
	mkdir -p build/twopass
	$(BISON) -d -o $@ src/twopass.y

build/lex.yy.c: src/lexer.l
	mkdir -p build
	$(FLEX) -o $@ src/lexer.l

test: $(ICG) $(TWOPASS)
	sh run_tests.sh ./$(ICG) ./$(TWOPASS)

clean:
	rm -rf build $(ICG) $(TWOPASS)

.PHONY: all test clean
