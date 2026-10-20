# Preprocesses /*@if EXPR@*/ ... /*@else@*/ ... /*@endif@*/ blocks before
# flex runs. EXPR is a boolean expression over FEATURE_* variables using
# !, &&, ||, and parentheses; a bare name means "feature is enabled". The
# first branch is emitted when EXPR is true, the @else branch otherwise.
# Marker lines are always removed, so a disabled branch contributes no
# patterns, rules, or support code.
#
# Feature values come from the environment, which the makefile populates from
# features.mk.

function fail(message) {
    printf "feature-filter: %s\n", message > "/dev/stderr"
    failed = 1
    exit 1
}

function feature_value(name,    value) {
    if (!(name in ENVIRON))
        fail("undefined feature " name)
    value = ENVIRON[name]
    if (value != "0" && value != "1")
        fail("feature " name " must be 0 or 1, got '" value "'")
    return value == "1"
}

function tokenize(expr,    i, n, char, name) {
    ntokens = 0
    i = 1
    n = length(expr)
    while (i <= n) {
        char = substr(expr, i, 1)
        if (char == " " || char == "\t") {
            ++i
            continue
        }
        if (char == "!") {
            tok[++ntokens] = "!"
            ++i
            continue
        }
        if (char == "&") {
            if (substr(expr, i + 1, 1) != "&")
                fail("expected '&&' in condition " expr)
            tok[++ntokens] = "&&"
            i += 2
            continue
        }
        if (char == "|") {
            if (substr(expr, i + 1, 1) != "|")
                fail("expected '||' in condition " expr)
            tok[++ntokens] = "||"
            i += 2
            continue
        }
        if (char == "(" || char == ")") {
            tok[++ntokens] = char
            ++i
            continue
        }
        if (char ~ /[A-Za-z_]/) {
            name = ""
            while (i <= n && substr(expr, i, 1) ~ /[A-Za-z0-9_]/) {
                name = name substr(expr, i, 1)
                ++i
            }
            tok[++ntokens] = name
            continue
        }
        fail("unexpected character '" char "' in condition " expr)
    }
}

function parse_primary(    value) {
    if (pos > ntokens)
        fail("unexpected end of condition")
    if (tok[pos] == "!") {
        ++pos
        return !parse_primary()
    }
    if (tok[pos] == "(") {
        ++pos
        value = parse_or()
        if (pos > ntokens || tok[pos] != ")")
            fail("missing ')' in condition")
        ++pos
        return value
    }
    return feature_value(tok[pos++])
}

function parse_and(    value, rhs) {
    value = parse_primary()
    while (pos <= ntokens && tok[pos] == "&&") {
        ++pos
        rhs = parse_primary()
        value = value && rhs
    }
    return value
}

function parse_or(    value, rhs) {
    value = parse_and()
    while (pos <= ntokens && tok[pos] == "||") {
        ++pos
        rhs = parse_and()
        value = value || rhs
    }
    return value
}

function evaluate(expr,    value) {
    tokenize(expr)
    pos = 1
    value = parse_or()
    if (pos <= ntokens)
        fail("unexpected '" tok[pos] "' in condition " expr)
    return value
}

BEGIN { depth = 0 }

/^[ \t]*\/\*@if .+@\*\/$/ {
    condition = $0
    sub(/^[ \t]*\/\*@if /, "", condition)
    sub(/@\*\/$/, "", condition)
    ++depth
    source[depth] = condition
    enabled[depth] = evaluate(condition)
    taken_else[depth] = 0
    active[depth] = enabled[depth]
    next
}

/^[ \t]*\/\*@else@\*\/$/ {
    if (depth == 0)
        fail("@else outside a conditional block")
    if (taken_else[depth])
        fail("duplicate @else in condition " source[depth])
    taken_else[depth] = 1
    active[depth] = !enabled[depth]
    next
}

/^[ \t]*\/\*@endif@\*\/$/ {
    if (depth == 0)
        fail("unmatched @endif")
    --depth
    next
}

/^[ \t]*\/\*@(if|else|endif)/ {
    fail("malformed marker: " $0)
}

{
    for (i = 1; i <= depth; ++i)
        if (!active[i])
            next
    print
}

END {
    if (!failed && depth != 0)
        fail("unterminated @if " source[depth])
}
