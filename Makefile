# Build the generator and run every test with:  make test
# On Windows use mingw32-make from Git Bash (the recipes need sh).

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
CFLAGS = -std=gnu99 -Wall -Wextra -g -Isrc -Ibuild

ICG  = icg$(EXE)
# Not named *patch*.exe: Windows UAC treats such names as installers.
UNIT = build/unit_lists$(EXE)
OBJS = build/parser.tab.o build/lex.yy.o build/quad.o build/backpatch.o \
       build/symtab.o build/main.o

all: $(ICG)

$(ICG): $(OBJS)
	$(CC) $(CFLAGS) -o $@ $(OBJS)

build/parser.tab.c build/parser.tab.h: src/parser.y | build
	$(BISON) -d -o build/parser.tab.c src/parser.y

build/lex.yy.c: src/lexer.l build/parser.tab.h | build
	$(FLEX) -o $@ src/lexer.l

build/%.o: build/%.c
	$(CC) $(CFLAGS) -Wno-unused-function -c -o $@ $<

build/%.o: src/%.c src/*.h | build
	$(CC) $(CFLAGS) -c -o $@ $<

build/main.o: build/parser.tab.h

$(UNIT): tests/unit/test_backpatch.c build/quad.o build/backpatch.o
	$(CC) $(CFLAGS) -o $@ $^

build:
	mkdir -p build

test: $(ICG) $(UNIT)
	./$(UNIT)
	sh run_tests.sh ./$(ICG)

clean:
	rm -rf build $(ICG)

.PHONY: all test clean
