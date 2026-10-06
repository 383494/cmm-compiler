%option noyywrap
%option nounput
%option noinput
%option yylineno

%{

%}

WhiteSpace          [ \t\n\r]*
LineComment         \/\/.*
MultiLineComment    "/*"([^*]|[*][^/]|[\r\n])*"*/"

Identifier      [a-zA-Z_][a-zA-Z0-9_]*

Binary          0[bB][01]+
Decimal         [1-9][0-9]*
Octal           0[0-7]*
Hexadecimal     0[xX][0-9a-fA-F]+
Real            (0|[1-9][0-9]*)\.([0-9]+)

%%

{WhiteSpace}        { }
{LineComment}       { yyerror("not implemented"); }
{MultiLineComment}  { yyerror("not implemented"); }

// TODO


{Identifier}    { yylval.str_val = strcpy(malloc(strlen(yytext) + 1), yytext); return IDENT; }

{Binary}        { yylval.int_val = strtol(yytext + 2, nullptr, 2); return INT_CONST; }
{Decimal}       { int x; sscanf(yytext, "%d", &x); yylval.int_val = x; return INT_CONST; }
{Octal}         { int x; sscanf(yytext, "%d", &x); yylval.int_val = x; return INT_CONST; }
{Hexadecimal}   { int x; sscanf(yytext, "%d", &x); yylval.int_val = x; return INT_CONST; }
{Real}          { float x; sscanf(yytext, "%f", &x); yylval.float_val = x; return FLOAT_CONST; }

.               { return yytext[0]; }

%%
