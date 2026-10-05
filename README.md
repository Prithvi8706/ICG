# ICG with Backpatching

One-pass intermediate code generator for a small C-like language (BCSE307P).
Flex and Bison translate assignments, boolean conditions and `if` / `if-else` /
`while` into numbered three-address code, filling every jump target by
backpatching (Aho et al., *Compilers*, 2nd ed., sec. 6.7).

## Build and test

Needs gcc, flex and bison. On Windows use `mingw32-make` from Git Bash
(`win_flex` / `win_bison` are picked up automatically).

```sh
make          # builds ./icg
make test     # backpatch unit test + every tests/*.src against its .expected
make clean
```

## Run

```sh
./icg tests/02_if.src               # three-address code (default)
./icg --format=quad tests/02_if.src # quadruple table
./icg < program.src                 # read stdin
```

```
100: t1 = a + b
101: x = t1
102: if a < b goto 104
103: goto 105
104: y = c
105: halt
```

## Status (Review 1)

Working: lexer for the full language, grammar for every construct with 0
conflicts, quad table, temporaries, `makelist` / `merge` / `backpatch`,
code for assignment, arithmetic, relational conditions, `if` and blocks.

Parsed but not generated yet (Review 2): `if-else`, `while`, `&&`, `||`, `!`,
parenthesised conditions, `true`, `false`. These stop with
`line N: <construct> is not implemented yet`.

## Layout

| File | Contents |
|------|----------|
| `src/lexer.l` | tokens, line numbers |
| `src/parser.y` | grammar, M / N markers, semantic actions |
| `src/quad.c` | quad table, `emit()`, `newtemp()`, printing |
| `src/backpatch.c` | `makelist`, `merge`, `backpatch` |
| `src/symtab.c` | symbol table |
| `src/main.c` | command line |
| `tests/` | `NN_name.src` + `NN_name.expected`, unit test in `tests/unit/` |
| `run_tests.sh` | diffs actual vs expected, fails on any `goto _` |
