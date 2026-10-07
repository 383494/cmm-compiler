%option noyywrap
%option nounput
%option noinput
%option yylineno
%option never-interactive

%s COMMENTS_ENABLED
%x COMMENT

%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ERR_STREAM MUXDEF(CMM_OUTPUT_STDERR, stderr, stdout)

#if CMM_ENABLE_COMMENTS
#define YY_USER_INIT BEGIN(COMMENTS_ENABLED)
#endif

#define YY_USER_ACTION yylloc.first_line = yylloc.last_line = yylineno;

static int comment_line;

static void report_syntax_line(int line) {
    if (cmm_last_error_line != line) {
        fprintf(ERR_STREAM, "Error type B at Line %d: syntax error\n", line);
        cmm_error_count++;
        cmm_last_error_line = line;
    }
}

static char *token_text(void) {
    char *text = malloc((size_t)yyleng + 1);
    if (text == NULL) {
        abort();
    }
    memcpy(text, yytext, (size_t)yyleng + 1);
    return text; // free'd by caller
}
%}

WhiteSpace      [ \t\n\r]+
LineComment     \/\/[^\n]*
Identifier      [a-zA-Z_][a-zA-Z0-9_]*
Decimal         [1-9][0-9]*
Octal           0[0-7]*
Hexadecimal     0[xX][0-9a-fA-F]+
Real            (0|[1-9][0-9]*)\.([0-9]+)
IllegalOctal    0[0-9]*[89][0-9]*
IllegalHex      0[xX][0-9a-fA-F]*[g-zG-Z][0-9a-zA-Z]*

%%

{WhiteSpace}        { }
{LineComment}       {
#if !CMM_ENABLE_COMMENTS
    report_syntax_line(yylineno);
#endif
}
"/*"                { comment_line = yylineno; BEGIN(COMMENT); }
<COMMENT>"*/"       {
#if !CMM_ENABLE_COMMENTS
    for (int line = comment_line; line <= yylineno; ++line) {
        report_syntax_line(line);
    }
#endif
    BEGIN(COMMENTS_ENABLED);
}
<COMMENT>[^*\n]+    { }
<COMMENT>"*"        { }
<COMMENT>\n         { }
<COMMENT><<EOF>>    {
#if CMM_ENABLE_COMMENTS
    if (cmm_last_error_line != comment_line) {
        cmm_error_count++;
        fprintf(ERR_STREAM, "Error type A at Line %d: Unterminated comment.\n", comment_line);
        cmm_last_error_line = comment_line;
    }
#else
    for (int line = comment_line; line <= yylineno; ++line) {
        report_syntax_line(line);
    }
#endif
    BEGIN(COMMENTS_ENABLED);
    return INVALID;
}

"int"|"float"       { yylval.str_val = token_text(); return TYPE; }
"struct"            { return STRUCT; }
"return"            { return RETURN; }
"if"                { return IF; }
"else"              { return ELSE; }
"while"             { return WHILE; }

";"                 { return SEMI; }
","                 { return COMMA; }
"="                 { return ASSIGNOP; }
"=="|"!="|">="|"<="|">"|"<" {
    yylval.str_val = token_text();
    return RELOP;
}
"+"                 { return PLUS; }
"-"                 { return MINUS; }
"*"                 { return STAR; }
"/"                 { return DIV; }
"&&"                { return AND; }
"||"                { return OR; }
"!"                 { return NOT; }
"."                 { return DOT; }
"("                 { return LP; }
")"                 { return RP; }
"["                 { return LB; }
"]"                 { return RB; }
"{"                 { return LC; }
"}"                 { return RC; }

{Identifier}        { yylval.str_val = token_text(); return ID; }
{Real}              { yylval.float_val = strtof(yytext, NULL); return FLOAT; }
{Decimal}           { yylval.int_val = (int)strtol(yytext, NULL, 10); return INT; }
{Octal}             { yylval.int_val = (int)strtol(yytext, NULL, 8); return INT; }
{Hexadecimal}       { yylval.int_val = (int)strtol(yytext, NULL, 16); return INT; }
{IllegalOctal}      {
    if (cmm_last_error_line != yylineno) {
        fprintf(ERR_STREAM, "Error type A at Line %d: Illegal octal number '%s'.\n", yylineno, yytext);
        cmm_error_count++;
        cmm_last_error_line = yylineno;
    }
    return INVALID;
}
{IllegalHex}        {
    if (cmm_last_error_line != yylineno) {
        fprintf(ERR_STREAM, "Error type A at Line %d: Illegal hexadecimal number '%s'.\n", yylineno, yytext);
        cmm_error_count++;
        cmm_last_error_line = yylineno;
    }
    return INVALID;
}

.                   {
    if (cmm_last_error_line != yylineno) {
        fprintf(ERR_STREAM, "Error type A at Line %d: Mysterious character \"%s\".\n", yylineno, yytext);
        cmm_error_count++;
        cmm_last_error_line = yylineno;
    }
    return INVALID;
}

<<EOF>>             {
    yylloc.first_line = yylloc.last_line = yylineno;
    return 0;
}

%%
