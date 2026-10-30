#!/bin/sh
set -eu

parser=${1:-./Code/parser}
tmp=$(mktemp)
trap 'rm -f "$tmp"' 0
trap 'exit 1' HUP INT TERM

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    cat "$tmp" >&2
    exit 1
}

run() {
    status=0
    "$parser" "$1" >"$tmp" 2>&1 || status=$?
}

check_pass() {
    file=$1
    run "$file"
    [ "$status" -eq 0 ] || fail "expected parse success: $file"
    grep -q '^Error type ' "$tmp" && fail "expected no diagnostics: $file"
    [ -s "$tmp" ] && fail "expected no output: $file"
    printf 'PASS: %s\n' "$file"
}

# Asserts the exact "type@line" sequence of diagnostics, that at most one
# diagnostic is reported per line, and that type B carries the syntax-error
# message while type A carries a non-empty description.
check_errors() {
    file=$1
    expected=$2
    run "$file"
    [ "$status" -le 1 ] || fail "unexpected exit status $status: $file"
    grep -q '^Error type ' "$tmp" || fail "expected diagnostics: $file"

    actual=$(awk '/^Error type / { printf "%s%s@%d", separator, substr($3, 1, 1), $6; separator = " " }' "$tmp")
    [ "$actual" = "$expected" ] || fail "expected diagnostics [$expected] from $file, got [$actual]"

    repeated=$(awk '/^Error type / { seen[$6]++ } END { for (line in seen) if (seen[line] > 1) print line }' "$tmp")
    [ -z "$repeated" ] || fail "more than one diagnostic on line $repeated in $file"

    b_total=$(grep -c '^Error type B ' "$tmp" || :)
    b_exact=$(grep -c '^Error type B at Line [0-9][0-9]*: syntax error$' "$tmp" || :)
    [ "$b_total" = "$b_exact" ] || fail "unexpected syntax-error text in $file"

    a_total=$(grep -c '^Error type A ' "$tmp" || :)
    a_exact=$(grep -c '^Error type A at Line [0-9][0-9]*: .\+$' "$tmp" || :)
    [ "$a_total" = "$a_exact" ] || fail "unexpected lexical-error text in $file"

    printf 'PASS: %s (diagnostics: %s)\n' "$file" "$actual"
}

check_message() {
    file=$1
    pattern=$2
    run "$file"
    grep -q "$pattern" "$tmp" || fail "expected '$pattern' in $file"
    printf 'PASS: %s (message: %s)\n' "$file" "$pattern"
}

check_pass tests/pass0.cmm
check_pass tests/pass1.cmm
if [ "${FEATURE_ENABLE_OCTAL:-1}" = 1 ] && [ "${FEATURE_ENABLE_HEXADECIMAL:-1}" = 1 ]; then
    check_pass tests/pass2.cmm
elif [ "${FEATURE_ENABLE_OCTAL:-1}" = 1 ]; then
    check_errors tests/pass2.cmm 'B@4'
else
    # 0123 splits into two integers and recovery spills onto line 4.
    check_errors tests/pass2.cmm 'B@3 B@4'
fi
if [ "${FEATURE_ENABLE_OCTAL:-1}" = 1 ]; then
    check_pass tests/octal.cmm
else
    # Without octal literals '0123' is a 0 followed by a decimal 123.
    check_errors tests/octal.cmm 'B@2 B@3 B@4'
fi
if [ "${FEATURE_ENABLE_HEXADECIMAL:-1}" = 1 ]; then
    check_pass tests/hex.cmm
else
    # Without hexadecimal literals '0x1F' is a 0 followed by an identifier.
    check_errors tests/hex.cmm 'B@2 B@3 B@4'
fi
check_pass tests/pass4.cmm
check_pass tests/pass5.cmm
if [ "${FEATURE_ENABLE_BINARY:-1}" = 1 ]; then
    check_pass tests/binary.cmm
else
    # Without binary literals '0b101' is an octal 0 followed by an identifier.
    check_errors tests/binary.cmm 'B@2 B@3'
fi
if [ "${FEATURE_ENABLE_COMMENTS:-1}" = 1 ]; then
    check_pass tests/pass3.cmm
    check_pass tests/comments-inline.cmm
else
    # Without comment rules '//' and '/*' are ordinary operators, so the first
    # comment line is one syntax error and recovery skips the rest.
    check_errors tests/pass3.cmm 'B@3'
    check_errors tests/comments-inline.cmm 'B@2'
fi

# One diagnostic per independent defect.
check_errors tests/fail0.cmm 'A@4'
check_message tests/fail0.cmm '^Error type A at Line 4: Mysterious character "~"\.$'
check_errors tests/fail1.cmm 'B@5 B@6'
if [ "${FEATURE_ENABLE_OCTAL:-1}" = 1 ] && [ "${FEATURE_ENABLE_HEXADECIMAL:-1}" = 1 ]; then
    check_errors tests/fail2.cmm 'A@3 A@4 B@7'
elif [ "${FEATURE_ENABLE_OCTAL:-1}" = 1 ]; then
    check_errors tests/fail2.cmm 'A@3 B@4 B@7'
else
    # Without octal support 09 is split into two integers; recovery's syntax
    # error on line 4 then preempts the illegal-hex diagnostic there (at most
    # one diagnostic per line).
    check_errors tests/fail2.cmm 'B@3 B@4 B@7'
fi
# Illegal numeric literals report the offending text once per line.
if [ "${FEATURE_ENABLE_OCTAL:-1}" = 1 ]; then
    check_errors tests/illegal-octal.cmm 'A@2'
    check_message tests/illegal-octal.cmm "^Error type A at Line 2: Illegal octal number '09'\.$"
else
    check_errors tests/illegal-octal.cmm 'B@2'
fi
if [ "${FEATURE_ENABLE_HEXADECIMAL:-1}" = 1 ]; then
    check_errors tests/illegal-hex.cmm 'A@2'
    check_message tests/illegal-hex.cmm "^Error type A at Line 2: Illegal hexadecimal number '0xG1'\.$"
else
    check_errors tests/illegal-hex.cmm 'B@2'
fi
# Several syntax errors on one line collapse into one diagnostic.
check_errors tests/recovery/same-line-errors.cmm 'B@2'
if [ "${FEATURE_ENABLE_COMMENTS:-1}" = 1 ]; then
    # The comment opened on line 3 closes at line 7, so only the stray '*/'
    # on line 8 is a defect.
    check_errors tests/fail3.cmm 'B@8'
else
    check_errors tests/fail3.cmm 'B@3'
fi
check_errors tests/fail4.cmm 'B@3'
check_errors tests/fail5.cmm 'B@3 B@4'
check_errors tests/fail6.cmm 'B@3'

# Recovery for a single damaged construct.
check_errors tests/recovery/array-dimension.cmm 'B@4'
check_errors tests/recovery/brace-initializer.cmm 'B@3'
check_errors tests/recovery/parameter-list.cmm 'B@1'
check_errors tests/recovery/call-arguments.cmm 'B@2'
check_errors tests/recovery/subscript.cmm 'B@3'
check_errors tests/recovery/struct-body.cmm 'B@3'
check_errors tests/recovery/nested-blocks.cmm 'B@5'
check_errors tests/recovery/deep-nesting.cmm 'B@12'
check_errors tests/recovery/struct-usage.cmm 'B@14'
check_errors tests/recovery/defect-in-long-program.cmm 'B@21'
check_errors tests/recovery/two-functions-one-broken.cmm 'B@8'
check_errors tests/recovery/stress-functions.cmm 'B@10'

# Recovery that has to preserve the construct that follows. Each fixture keeps
# its defects on separate lines.
check_errors tests/recovery/local-declarations.cmm 'B@3 B@4'
check_errors tests/recovery/external-declarations.cmm 'B@2 B@3'
check_errors tests/recovery/statements.cmm 'B@4 B@5'
check_errors tests/recovery/return-statement.cmm 'B@4 B@5'
check_errors tests/recovery/condition.cmm 'B@3 B@4'
check_errors tests/recovery/else-boundary.cmm 'B@4 B@5'
check_errors tests/recovery/block-boundary.cmm 'B@3 B@5'
check_errors tests/recovery/statement-block-boundary.cmm 'B@4 B@6'
check_errors tests/recovery/return-block-boundary.cmm 'B@3 B@5'
check_errors tests/recovery/consecutive-defects.cmm 'B@2 B@3 B@4'
check_errors tests/recovery/error-then-declaration.cmm 'B@3 B@4'

# Each per-delimiter recovery rule must keep its own diagnostics; removing any
# of them swallows one of these defects.
check_errors tests/recovery/declarator-list-dimensions.cmm 'B@2 B@3'
check_errors tests/recovery/multi-subscript.cmm 'B@4 B@5'
check_errors tests/recovery/multi-call-arguments.cmm 'B@3 B@4'
check_errors tests/recovery/loop-condition-body.cmm 'B@3 B@4'
check_errors tests/recovery/branch-condition-body.cmm 'B@3 B@4'
check_errors tests/recovery/chained-assignment.cmm 'B@4'
# Guards the reset choice in the Specifier-error rules: resuming reporting too
# early duplicates this single defect.
check_errors tests/recovery/damaged-initializer.cmm 'B@2'

# Boundary damage that only shows up at the end of the file.
check_errors tests/recovery/unbalanced-close-brace.cmm 'B@5'
check_errors tests/recovery/missing-final-brace.cmm 'B@4'

# Lexical diagnostics: reported once, with the offending text, and reporting
# resumes after the parser synchronises.
check_errors tests/recovery/lexical-first.cmm 'A@3'
check_message tests/recovery/lexical-first.cmm '^Error type A at Line 3: Mysterious character "\$"\.$'
check_errors tests/recovery/mixed-errors.cmm 'B@3 B@4'
check_errors tests/recovery/lexical-boundary.cmm 'B@3 A@4'
check_message tests/recovery/lexical-boundary.cmm '^Error type A at Line 4: Mysterious character "@"\.$'

if [ "${FEATURE_ENABLE_COMMENTS:-1}" = 1 ]; then
    check_errors tests/recovery/unterminated-comment.cmm 'A@3'
    check_message tests/recovery/unterminated-comment.cmm '^Error type A at Line 3: Unterminated comment\.$'
else
    # Without comment rules the opener lexes as operators and recovery skips
    # the rest of the file.
    check_errors tests/recovery/unterminated-comment.cmm 'B@3'
fi
