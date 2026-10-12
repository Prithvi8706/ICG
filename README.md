# ICG with Backpatching

One-pass intermediate code generator for a small C-like language (BCSE307P).
Flex and Bison translate assignments, arithmetic, short-circuit boolean
conditions, `if` / `if-else`, `while`, `do-while`, `for`, `break` and
`continue` into numbered three-address code, filling every jump target by
backpatching (Aho et al., *Compilers*, 2nd ed., sec. 6.7).

A second Bison grammar, `twopass`, generates the same code the classic
two-pass way (syntax tree, symbolic labels, label resolution) as a baseline
for comparison.

## Build and test

Needs gcc, flex and bison. On Windows use `mingw32-make` from Git Bash
(`win_flex` / `win_bison` are picked up automatically).

```sh
make          # builds ./icg and ./twopass
make test     # runs every tests/*.src against its .expected, with both programs
make clean
```

Without make, from `src/`:

```sh
flex lexer.l && bison -d parser.y && gcc lex.yy.c parser.tab.c -o icg
bison -d -o parser.tab.c twopass.y && gcc lex.yy.c parser.tab.c -o twopass
```

## Run

```sh
./icg tests/04_while.src                # three-address code (default)
./icg --format=quad tests/04_while.src  # quadruple table
./icg --trace tests/03_if_else.src      # every rule, emit, makelist, merge, backpatch
./icg --step tests/03_if_else.src       # same, waiting for Enter after each step
./icg --stats tests/06_nested.src       # code size and patch-list usage (stderr)
./icg < program.src                     # read stdin

./twopass tests/04_while.src                # same code as icg
./twopass --format=labels tests/04_while.src  # code before labels are resolved
./twopass --stats tests/06_nested.src       # code size, tree nodes, labels (stderr)
```

```
$ ./icg tests/04_while.src
100: i = 0
101: if i < n goto 103
102: goto 106
103: t1 = i + 1
104: i = t1
105: goto 101
106: done = 1
107: halt
```

With `--trace`, each reduction that touches a jump is printed with what it
did, and the finished code follows after a blank line:

```
B -> E1 relop E2
    makelist   {100}
    makelist   {101}
    emit       100: if a < b goto _
    emit       101: goto _
    emit       102: x = 1
N -> e
    makelist   {103}
    emit       103: goto _
    emit       104: x = 2
S -> if ( B ) M1 S1 else N M2 S2
    backpatch  {100} := 102
    backpatch  {101} := 104
...
```

## Language

```
S -> id = E ;  |  if ( B ) S  |  if ( B ) S else S  |  while ( B ) S
   | do S while ( B ) ;  |  for ( id = E ; B ; id = E ) S
   | break ;  |  continue ;  |  { S ... }
B -> B || B  |  B && B  |  ! B  |  ( B )  |  E relop E  |  true  |  false
E -> E + E  |  E - E  |  E * E  |  E / E  |  - E  |  ( E )  |  id  |  num
```

`relop` is one of `< <= > >= == !=`. `//` starts a comment. Errors stop with
the line number: unexpected characters, syntax errors (naming the tokens
expected), and `break` or `continue` outside a loop.

## Backpatching vs. two passes

Both programs print identical code for every test; the difference is when
jump targets become known and what is held in memory until then.

| Program | `icg` (backpatching) | `twopass` (labels) |
|---|---|---|
| Passes | 1: code emitted while parsing | 3: parse to tree, emit with labels, resolve |
| Held until targets are known | patch lists of unfilled jumps | whole syntax tree, label table, all code |
| `06_nested` (16 quads) | peak 7 unfilled jumps, 10 list entries | 26 tree nodes, 9 labels |
| `10_break_continue` (17 quads) | peak 8 unfilled jumps, 11 list entries | 29 tree nodes, 9 labels |
| `14_nested_loops` (18 quads) | peak 7 unfilled jumps, 12 list entries | 32 tree nodes, 11 labels |

## Layout

| File | Contents |
|------|----------|
| `src/lexer.l` | tokens, line numbers (shared by both grammars) |
| `src/parser.y` | grammar, M / N / W markers and semantic actions; below the grammar, the helpers: quad table (`emit`, `newtemp`, printing), patch lists (`makelist`, `merge`, `backpatch`), loop stack for `break` / `continue`, trace, symbol table and `main` |
| `src/twopass.y` | baseline: grammar that builds a syntax tree, code generation with labels, label resolution |
| `tests/` | `NN_name.src` + `NN_name.expected`, optional `NN_name.args` |
| `run_tests.sh` | diffs actual vs expected for both programs, fails on any `goto _` in final code |
| `docs/` | literature survey, review slides |
