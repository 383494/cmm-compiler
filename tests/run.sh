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
    grep -q '^Program' "$tmp" || fail "expected AST output: $file"
    grep -q '^Error type ' "$tmp" && fail "expected no diagnostics: $file"
    printf 'PASS: %s\n' "$file"
}

# Asserts the exact "type@line" sequence of diagnostics, that at most one
# diagnostic is reported per line, that diagnostics never accompany an AST,
# that type B carries the syntax-error message, and that type A carries a
# non-empty description.
check_errors() {
    file=$1
    expected=$2
    run "$file"
    [ "$status" -le 1 ] || fail "unexpected exit status $status: $file"
    grep -q '^Error type ' "$tmp" || fail "expected diagnostics: $file"
    grep -q '^Program' "$tmp" && fail "expected diagnostics without an AST: $file"

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

# Asserts that valid input yields the expected AST nodes and no diagnostics.
check_ast_contains() {
    file=$1
    shift
    run "$file"
    [ "$status" -eq 0 ] || fail "expected parse success: $file"
    grep -q '^Error type ' "$tmp" && fail "expected no diagnostics: $file"
    for node in "$@"; do
        grep -q "^ *$node\b" "$tmp" || fail "expected AST node $node in $file"
    done
    printf 'PASS: %s (AST nodes: %s)\n' "$file" "$*"
}

check_pass tests/pass0.cmm
check_pass tests/pass1.cmm
check_pass tests/pass2.cmm
check_pass tests/pass4.cmm
check_ast_contains tests/pass4.cmm CompSt StructSpecifier FunDec WHILE IF ELSE RETURN LB DOT NOT AND RELOP VarList ParamDec Args
check_ast_contains tests/pass5.cmm CompSt StructSpecifier FunDec WHILE IF ELSE RETURN LB DOT NOT MINUS RELOP OR Args
if [ "${FEATURE_ENABLE_COMMENTS:-0}" = 1 ]; then
    check_pass tests/pass3.cmm
else
    check_errors tests/pass3.cmm 'B@3'
fi

# One diagnostic per independent defect.
check_errors tests/fail0.cmm 'A@4'
check_message tests/fail0.cmm '^Error type A at Line 4: Mysterious character "~"\.$'
check_errors tests/fail1.cmm 'B@5 B@6'
check_errors tests/fail2.cmm 'A@3 A@4 B@7'
if [ "${FEATURE_ENABLE_COMMENTS:-0}" = 1 ]; then
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

if [ "${FEATURE_ENABLE_COMMENTS:-0}" = 1 ]; then
    check_errors tests/recovery/unterminated-comment.cmm 'A@3'
    check_message tests/recovery/unterminated-comment.cmm '^Error type A at Line 3: Unterminated comment\.$'
else
    # Without comment support the '/*' is just arithmetic operators.
    check_errors tests/recovery/unterminated-comment.cmm 'B@3'
fi
