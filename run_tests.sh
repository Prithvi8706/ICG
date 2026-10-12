#!/bin/sh
# Runs every tests/NN_name.src through the generator and compares the output
# (stdout and stderr) with tests/NN_name.expected. Prints PASS/FAIL per test.
# Any final code still containing "goto _" fails, even if it matches.
#
# tests/NN_name.args, if present, holds extra options for the run.
# When a second program is given (the two-pass baseline), every test without
# an .args file must produce exactly the same output from it too.

ICG=${1:-./icg}
TWOPASS=$2
pass=0
total=0

check() {  # check NAME EXPECTED ACTUAL
    total=$((total + 1))
    # Only the final code, after the trace's closing blank line, if any.
    if printf '%s\n' "$3" | awk 'NF == 0 { code = ""; next } { code = code $0 "\n" }
                                 END { printf "%s", code }' | grep -q 'goto _'; then
        echo "FAIL  $1 (unfilled jump left in output)"
    elif printf '%s\n' "$3" | diff --strip-trailing-cr -u "$2" - > /dev/null; then
        echo "PASS  $1"
        pass=$((pass + 1))
    else
        echo "FAIL  $1"
        printf '%s\n' "$3" | diff --strip-trailing-cr -u "$2" - | sed 's/^/      /'
    fi
}

for src in tests/*.src; do
    name=$(basename "$src" .src)
    expected="tests/$name.expected"

    if [ ! -f "$expected" ]; then
        total=$((total + 1))
        echo "FAIL  $name (no .expected file)"
        continue
    fi

    args=""
    [ -f "tests/$name.args" ] && args=$(cat "tests/$name.args")

    check "$name" "$expected" "$("$ICG" $args "$src" 2>&1)"

    if [ -n "$TWOPASS" ] && [ -z "$args" ]; then
        check "$name (two-pass)" "$expected" "$("$TWOPASS" "$src" 2>&1)"
    fi
done

echo "$pass of $total tests passing"
[ "$pass" -eq "$total" ]
