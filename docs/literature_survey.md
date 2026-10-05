# Literature Survey

How compilers resolve forward jump targets, and what each source contributes
to this project. Edition and section details should be checked against the
library copy before they are quoted in the final report.

## Sources

1. **A. V. Aho, M. S. Lam, R. Sethi, J. D. Ullman.** *Compilers: Principles,
   Techniques, and Tools*, 2nd ed. Addison-Wesley, 2006. Ch. 6, sec. 6.6
   (control flow) and sec. 6.7 (backpatching).
   The translation scheme this project implements: `truelist` / `falselist` /
   `nextlist`, the `makelist`, `merge` and `backpatch` helpers, and the empty
   marker non-terminals `M` and `N`. It is the baseline the generator is
   checked against.

2. **A. W. Appel.** *Modern Compiler Implementation in C*. Cambridge University
   Press, 1998. Ch. 7 (translation to intermediate code).
   Translates conditionals into IR trees whose jumps name symbolic labels;
   targets are resolved when labels are placed, not by patching instruction
   numbers. This is the main alternative to backpatching and the basis of the
   two-pass baseline planned for Review 3.

3. **K. D. Cooper, L. Torczon.** *Engineering a Compiler*, 2nd ed. Morgan
   Kaufmann, 2011. Ch. 7 (code shape).
   Short-circuit evaluation of `&&` and `||` and the standard code shapes for
   `if`, `if-else` and loops. Used to check that the generated jump sequences
   are the conventional ones.

4. **J. Levine.** *flex & bison*. O'Reilly, 2009.
   Practical Bison: `%union` semantic values, empty rules and mid-rule
   actions, and precedence declarations that resolve the dangling-else
   conflict. Directly informs `parser.y`.

5. **C. Lattner, V. Adve.** "LLVM: A Compilation Framework for Lifelong Program
   Analysis & Transformation." *Proc. International Symposium on Code
   Generation and Optimization (CGO)*, 2004, pp. 75-86.
   A production IR built from basic blocks: branch targets are blocks that
   can be created before their code exists, and each block's terminator is
   set when control flow is known. Shows how forward branches are handled
   outside the textbook setting.

6. **S. H. Rodger, T. W. Finley.** *JFLAP: An Interactive Formal Languages and
   Automata Package*. Jones and Bartlett, 2006.
   Precedent for interactive visual tools in theory-of-computation teaching.
   Supports the trace viewer planned as this project's novelty.

## Comparison of approaches

| | Two-pass, symbolic labels | Backpatching | Basic-block IR (LLVM style) |
|---|---|---|---|
| Passes over the code | 2: emit with labels, then resolve | 1: targets filled during parsing | 1 to build blocks; targets are block references |
| Memory for pending jumps | Label table plus all code held until resolution | Lists of unfilled jump indices (`truelist`, `falselist`, `nextlist`) | Block objects and the control-flow graph |
| Fit with Bison | Easy (`newlabel()` in actions) but needs a separate resolution pass | Natural: empty marker rules `M` and `N` capture `nextinstr` at the right point | Heavy: needs an IR framework around the parser |
| Main source | Appel (1998) | Aho et al. (2006) | Lattner and Adve (2004) |

## Gap

Backpatching is well-known textbook material, but the patch lists are
invisible: a student sees the finished quadruples, not the moment each jump
was created empty and later filled. Few student tools show the lists while
code is generated. This project implements the textbook scheme in one pass
and, as its extension, traces every `makelist`, `merge` and `backpatch` call so
the process can be replayed step by step.
