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
Binary          0[bB][01]+
Decimal         [1-9][0-9]*
Octal           0[0-7]*
Hexadecimal     0[xX][0-9a-fA-F]+
Real            (0|[1-9][0-9]*)\.([0-9]+)

%%

{WhiteSpace}        { }
<COMMENTS_ENABLED>{LineComment} { }
<COMMENTS_ENABLED>"/*" { comment_line = yylineno; BEGIN(COMMENT); }
<COMMENT>"*/"       { BEGIN(COMMENTS_ENABLED); }
<COMMENT>[^*\n]+    { }
<COMMENT>"*"        { }
<COMMENT>\n         { }
<COMMENT><<EOF>>    {
    if (cmm_last_error_line != comment_line) {
        cmm_error_count++;
        fprintf(ERR_STREAM, "Error type A at Line %d: Unterminated comment.\n", comment_line);
        cmm_last_error_line = comment_line;
    }
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
{Binary}            { yylval.int_val = (int)strtol(yytext + 2, NULL, 2); return INT; }
{Decimal}           { yylval.int_val = (int)strtol(yytext, NULL, 10); return INT; }
{Octal}             { yylval.int_val = (int)strtol(yytext, NULL, 8); return INT; }
{Hexadecimal}       { yylval.int_val = (int)strtol(yytext, NULL, 16); return INT; }

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
