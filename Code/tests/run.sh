#!/bin/sh
set -u

parser=${1:-./parser}
test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
comments=${FEATURE_ENABLE_COMMENTS:-0}

status=0

run_case() {
    expected=$1
    file=$2
    label=$3

    out=$("$parser" "$file" 2>&1)
    if printf '%s\n' "$out" | grep -q 'Error type'; then
        has_error=1
    else
        has_error=0
    fi

    if [ "$expected" = pass ] && [ "$has_error" -eq 0 ]; then
        printf 'PASS %s\n' "$label"
    elif [ "$expected" = fail ] && [ "$has_error" -eq 1 ]; then
        printf 'PASS %s\n' "$label"
    else
        printf 'FAIL %s\n' "$label"
        if [ "$expected" = pass ]; then
            printf '  expected no error, but got:\n'
        else
            printf '  expected an error, but got none:\n'
        fi
        printf '%s\n' "$out" | sed 's/^/    /'
        status=1
    fi
}

for f in "$test_dir"/pass*.cmm; do
    [ -e "$f" ] || continue
    name=${f##*/}
    if [ "$name" = pass3.cmm ] && [ "$comments" -eq 0 ]; then
        printf 'SKIP %s (comments disabled)\n' "$name"
        continue
    fi
    run_case pass "$f" "$name"
done

for f in "$test_dir"/fail*.cmm; do
    [ -e "$f" ] || continue
    name=${f##*/}
    if [ "$name" = fail3.cmm ] && [ "$comments" -eq 0 ]; then
        printf 'SKIP %s (comments disabled)\n' "$name"
        continue
    fi
    run_case fail "$f" "$name"
done

exit "$status"
