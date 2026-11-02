#!/bin/sh
# Test runner for the C-- compiler.
#
# Usage: sh tests/run.sh [path/to/parser]
#
# Every *.cmm fixture declares its expected result in trailing // comments, one
# or more @expect lines:
#
#     // @expect pass
#     // @expect fail B@4
#     // @expect[OCTAL=1 HEXADECIMAL=0] fail B@4
#     // @expect[OCTAL=0] fail B@3 B@4
#
# The optional bracketed condition lists FEATURE_ENABLE_* values (with the
# prefix omitted) that must all hold for the line to apply. Exactly one line
# must apply under the current feature configuration; if none applies the
# fixture is skipped. "pass" requires exit status 0 and no output. "fail"
# compares the exact sequence of "type@line" diagnostics and requires at most
# one diagnostic per line.
#
# Feature values come from the environment, falling back to Code/features.mk.
# Metadata lines are removed before the parser runs, so fixtures behave
# identically whether comment support is enabled or not. Keeping the block at
# the end of the file means removing it restores the original fixture exactly:
# the code's line numbers (including EOF diagnostics) never depend on the
# metadata, and adding or removing an expectation never renumbers the others.
set -eu

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
parser=${1:-./Code/parser}
tmp=$(mktemp)
stripped=$(mktemp)
trap 'rm -f "$tmp" "$stripped"' 0
trap 'exit 1' HUP INT TERM

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    cat "$tmp" >&2
    exit 1
}

# Populate unset feature variables from features.mk. The makefile normally
# exports them, but the runner must also work when invoked directly.
features_file=$tests_dir/../Code/features.mk
[ -f "$features_file" ] || fail "missing $features_file"
feature_defaults=$(awk -F'[[:space:]]*[?]?=[[:space:]]*' \
    '$1 ~ /^FEATURE_/ { print $1, $2 }' "$features_file")
while read -r name value; do
    [ -n "$name" ] || continue
    eval ": \"\${$name:=$value}\""
done <<EOF
$feature_defaults
EOF

feature_value() {
    name=$1
    case $name in
    '' | *[!A-Z0-9_]*) fail "invalid feature name '$name'" ;;
    esac
    eval "value=\${FEATURE_ENABLE_$name:-}"
    [ -n "$value" ] || fail "unknown feature '$name'"
    printf '%s' "$value"
}

run() {
    status=0
    "$parser" "$1" >"$tmp" 2>&1 || status=$?
}

expectations() {
    awk '
        /^[[:space:]]*\/\/[[:space:]]*@expect/ {
            line = $0
            sub(/^[[:space:]]*\/\/[[:space:]]*@expect[[:space:]]*/, "", line)
            sub(/[[:space:]]+$/, "", line)
            print line
        }
    ' "$1"
}

strip_metadata() {
    awk '
        !/^[[:space:]]*\/\/[[:space:]]*@expect/ { print }
    ' "$1" >"$stripped"
}

for file in $(find "$tests_dir" -type f -name '*.cmm' | sort); do
    relative=${file#"$tests_dir"/}
    declared=$(expectations "$file")
    [ -n "$declared" ] || fail "missing @expect metadata: $relative"

    selected=0
    outcome=
    diagnostics=
    while IFS= read -r header; do
        [ -n "$header" ] || continue

        condition=
        rest=$header
        case $rest in
        '['*)
            case $rest in
            *']'*) ;;
            *) fail "unterminated @expect condition: $relative: $header" ;;
            esac
            condition=${rest#\[}
            condition=${condition%%\]*}
            rest=${rest#*\]}
            rest=${rest#"${rest%%[![:space:]]*}"}
            ;;
        esac

        case $rest in
        pass | fail)
            candidate=$rest
            candidate_diagnostics=
            ;;
        'fail '*)
            candidate=fail
            candidate_diagnostics=${rest#fail }
            ;;
        *)
            fail "malformed @expect line: $relative: $header"
            ;;
        esac

        for diagnostic in $candidate_diagnostics; do
            case $diagnostic in
            *@*) ;;
            *) fail "malformed diagnostic '$diagnostic': $relative: $header" ;;
            esac
            diagnostic_type=${diagnostic%%@*}
            diagnostic_line=${diagnostic#*@}
            case $diagnostic_type in
            '' | *[!A-Za-z0-9_]*) fail "malformed diagnostic type '$diagnostic': $relative" ;;
            esac
            case $diagnostic_line in
            '' | *[!0-9]*) fail "malformed diagnostic line '$diagnostic': $relative" ;;
            esac
        done

        matches=1
        for clause in $condition; do
            case $clause in
            *=*) ;;
            *) fail "malformed feature clause '$clause': $relative: $header" ;;
            esac
            name=${clause%%=*}
            want=${clause#*=}
            case $want in
            0 | 1) ;;
            *) fail "feature '$name' expects 0 or 1, got '$want': $relative" ;;
            esac
            got=$(feature_value "$name")
            if [ "$got" != "$want" ]; then
                matches=0
                break
            fi
        done

        if [ "$matches" -eq 1 ]; then
            selected=$((selected + 1))
            outcome=$candidate
            diagnostics=$candidate_diagnostics
        fi
    done <<EOF
$declared
EOF

    if [ "$selected" -eq 0 ]; then
        printf 'SKIP: %s (no @expect applies)\n' "$relative"
        continue
    fi
    [ "$selected" -eq 1 ] || fail "ambiguous @expect lines: $relative"

    strip_metadata "$file"
    run "$stripped"

    if [ "$outcome" = pass ]; then
        [ "$status" -eq 0 ] || fail "expected parse success: $relative"
        grep -q '^Error type ' "$tmp" && fail "expected no diagnostics: $relative"
        [ -s "$tmp" ] && fail "expected no output: $relative"
        printf 'PASS: %s\n' "$relative"
        continue
    fi

    [ "$status" -le 1 ] || fail "unexpected exit status $status: $relative"
    grep -q '^Error type ' "$tmp" || fail "expected diagnostics: $relative"

    actual=$(awk '/^Error type / { printf "%s%s@%d", separator, $3, $6; separator = " " }' "$tmp")
    [ "$actual" = "$diagnostics" ] ||
        fail "expected diagnostics [$diagnostics] from $relative, got [$actual]"

    repeated=$(awk '/^Error type / { seen[$6]++ } END { for (line in seen) if (seen[line] > 1) print line }' "$tmp")
    [ -z "$repeated" ] || fail "more than one diagnostic on line $repeated in $relative"

    printf 'PASS: %s (diagnostics: %s)\n' "$relative" "$actual"
done
