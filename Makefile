# Build the generator and run every test with:  make test
# On Windows use mingw32-make from Git Bash (the recipes need sh).
# Without make, the same build is:
#   flex lexer.l && bison -d parser.y && gcc lex.yy.c parser.tab.c -o icg

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
CFLAGS = -std=gnu99 -Wall -Wextra -Wno-unused-function -g -Ibuild

ICG = icg$(EXE)

all: $(ICG)

$(ICG): build/parser.tab.c build/lex.yy.c
	$(CC) $(CFLAGS) -o $@ build/lex.yy.c build/parser.tab.c

build/parser.tab.c build/parser.tab.h: src/parser.y | build
	$(BISON) -d -o build/parser.tab.c src/parser.y

build/lex.yy.c: src/lexer.l build/parser.tab.h | build
	$(FLEX) -o $@ src/lexer.l

build:
	mkdir -p build

test: $(ICG)
	sh run_tests.sh ./$(ICG)

clean:
	rm -rf build $(ICG)

.PHONY: all test clean
