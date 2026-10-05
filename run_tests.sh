#!/bin/sh
# Runs every tests/NN_name.src through the generator and compares the output
# (stdout and stderr) with tests/NN_name.expected. Prints PASS/FAIL per test.
# Any output still containing "goto _" fails, even if it matches.

ICG=${1:-./icg}
pass=0
total=0

for src in tests/*.src; do
    name=$(basename "$src" .src)
    expected="tests/$name.expected"
    total=$((total + 1))

    if [ ! -f "$expected" ]; then
        echo "FAIL  $name (no .expected file)"
        continue
    fi

    actual=$("$ICG" "$src" 2>&1)

    if printf '%s\n' "$actual" | grep -q 'goto _'; then
        echo "FAIL  $name (unfilled jump left in output)"
    elif printf '%s\n' "$actual" | diff --strip-trailing-cr -u "$expected" - > /dev/null; then
        echo "PASS  $name"
        pass=$((pass + 1))
    else
        echo "FAIL  $name"
        printf '%s\n' "$actual" | diff --strip-trailing-cr -u "$expected" - | sed 's/^/      /'
    fi
done

echo "$pass of $total tests passing"
[ "$pass" -eq "$total" ]
