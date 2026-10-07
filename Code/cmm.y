%{
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ast/ast_defs.h"

#define ERR_STREAM MUXDEF(CMM_OUTPUT_STDERR, stderr, stdout)

int yylex(void);
void yyerror(BaseAST **ast, char const *err_info);

unsigned int cmm_error_count = 0;
int cmm_lex_recovering = 0;

#define yylex() (cmm_lex_recovering = YYRECOVERING(), (yylex)())

static BaseAST *plain_node(const char *type, int lineno, size_t count, ...) {
    PlainAST *node = NEW(PlainAST);
    if (node == NULL) {
        abort();
    }
    snprintf(node->type, sizeof(node->type), "%s", type);
    node->lineno = lineno;

    PlainAST **next = &node->child;
    va_list children;
    va_start(children, count);
    for (size_t i = 0; i < count; ++i) {
        PlainAST *child = (PlainAST *)va_arg(children, BaseAST *);
        if (child == NULL) {
            continue;
        }
        if (node->child == NULL || child->lineno < node->lineno) {
            node->lineno = child->lineno;
        }
        *next = child;
        next = &child->sib;
    }
    va_end(children);
    *next = NULL;
    return (BaseAST *)node;
}

static BaseAST *plain_token(const char *type, const char *data, int lineno) {
    BaseAST *base = plain_node(type, lineno, 0);
    PlainAST *node = (PlainAST *)base;
    snprintf(node->data, sizeof(node->data), "%s", data);
    return base;
}

static BaseAST *plain_text_token(const char *type, char *data, int lineno) {
    BaseAST *node = plain_token(type, data, lineno);
    free(data);
    return node;
}

static BaseAST *plain_int_token(int value, int lineno) {
    char data[MAX_ID_LEN];
    snprintf(data, sizeof(data), "%d", value);
    return plain_token("INT", data, lineno);
}

static BaseAST *plain_float_token(float value, int lineno) {
    char data[MAX_ID_LEN];
    snprintf(data, sizeof(data), "%.6f", value);
    return plain_token("FLOAT", data, lineno);
}

static void plain_free(BaseAST *base) {
    PlainAST *node = (PlainAST *)base;
    while (node != NULL) {
        PlainAST *next = node->sib;
        plain_free((BaseAST *)node->child);
        free(node);
        node = next;
    }
}
%}

%code requires {
#include "ast/ast_defs.h"
}

%code provides {
void yyerror(BaseAST **ast, char const *err_info);
extern unsigned int cmm_error_count;
extern int cmm_lex_recovering;
}

%code {
// to report multiple bugs
static int statement_boundary(int token) {
    switch (token) {
    case ID: 
    case INT:
    case FLOAT:
    case LP:
    case MINUS:
    case NOT:
    case LC:
    case RETURN:
    case IF:
    case WHILE:
    case RC:
    case ELSE:
        return 1;
    default:
        return 0;
    }
}
}

%parse-param { BaseAST **ast }
%locations

%union {
    char *str_val;
    int int_val;
    float float_val;
    BaseAST *ast_val;
}

%token <int_val> INT
%token <float_val> FLOAT
%token <str_val> ID TYPE RELOP
%token SEMI COMMA ASSIGNOP
%token PLUS MINUS STAR DIV
%token AND OR NOT DOT
%token LP RP LB RB LC RC
%token STRUCT RETURN
%token INVALID
%token IF ELSE WHILE

%right ASSIGNOP
%left OR
%left AND
%left RELOP
%left PLUS MINUS
%left STAR DIV
%precedence NOT UMINUS
%precedence LB DOT
%precedence LOWER_THAN_ELSE
%precedence ELSE

%type <ast_val> Program Args CompSt Dec Def Exp ExtDef FunDec OptTag ParamDec
%type <ast_val> Specifier Stmt StructSpecifier Tag VarDec
%type <ast_val> DecList DefList ExtDecList ExtDefList StmtList VarList

%destructor { free($$); } <str_val>
%destructor { plain_free($$); } <ast_val>

%%

Program:
    ExtDefList {
        *ast = plain_node("Program", @$.first_line, 1, $1);
        $$ = NULL;
    }
    ;

ExtDefList:
    ExtDef ExtDefList {
        $$ = plain_node("ExtDefList", @$.first_line, 2, $1, $2);
    }
    | %empty { $$ = NULL; }
    ;

ExtDef:
    Specifier ExtDecList SEMI {
        $$ = plain_node("ExtDef", @$.first_line, 3,
            $1, $2, plain_token("SEMI", "", @3.first_line));
    }
    | Specifier ExtDecList error {
        plain_free($1);
        plain_free($2);
        if (yychar == TYPE || yychar == STRUCT) {
            yyerrok;
        }
        $$ = NULL;
    }
    | Specifier ExtDecList error SEMI {
        plain_free($1);
        plain_free($2);
        yyerrok;
        $$ = NULL;
    }
    | Specifier SEMI {
        $$ = plain_node("ExtDef", @$.first_line, 2,
            $1, plain_token("SEMI", "", @2.first_line));
    }
    | Specifier FunDec CompSt {
        $$ = plain_node("ExtDef", @$.first_line, 3, $1, $2, $3);
    }
    | error SEMI {
        yyerrok;
        $$ = NULL;
    }
    ;

ExtDecList:
    VarDec {
        $$ = plain_node("ExtDecList", @$.first_line, 1, $1);
    }
    | VarDec COMMA ExtDecList {
        $$ = plain_node("ExtDecList", @$.first_line, 3,
            $1, plain_token("COMMA", "", @2.first_line), $3);
    }
    ;

Specifier:
    TYPE {
        $$ = plain_node("Specifier", @$.first_line, 1,
            plain_text_token("TYPE", $1, @1.first_line));
    }
    | StructSpecifier {
        $$ = plain_node("Specifier", @$.first_line, 1, $1);
    }
    ;

StructSpecifier:
    STRUCT OptTag LC DefList RC {
        $$ = plain_node("StructSpecifier", @$.first_line, 5,
            plain_token("STRUCT", "", @1.first_line), $2,
            plain_token("LC", "", @3.first_line), $4,
            plain_token("RC", "", @5.first_line));
    }
    | STRUCT Tag {
        $$ = plain_node("StructSpecifier", @$.first_line, 2,
            plain_token("STRUCT", "", @1.first_line), $2);
    }
    ;

OptTag:
    ID {
        $$ = plain_node("OptTag", @$.first_line, 1,
            plain_text_token("ID", $1, @1.first_line));
    }
    | %empty { $$ = NULL; }
    ;

Tag:
    ID {
        $$ = plain_node("Tag", @$.first_line, 1,
            plain_text_token("ID", $1, @1.first_line));
    }
    ;

VarDec:
    ID {
        $$ = plain_node("VarDec", @$.first_line, 1,
            plain_text_token("ID", $1, @1.first_line));
    }
    | VarDec LB INT RB {
        $$ = plain_node("VarDec", @$.first_line, 4,
            $1, plain_token("LB", "", @2.first_line),
            plain_int_token($3, @3.first_line),
            plain_token("RB", "", @4.first_line));
    }
    ;

FunDec:
    ID LP VarList RP {
        $$ = plain_node("FunDec", @$.first_line, 4,
            plain_text_token("ID", $1, @1.first_line),
            plain_token("LP", "", @2.first_line), $3,
            plain_token("RP", "", @4.first_line));
    }
    | ID LP RP {
        $$ = plain_node("FunDec", @$.first_line, 3,
            plain_text_token("ID", $1, @1.first_line),
            plain_token("LP", "", @2.first_line),
            plain_token("RP", "", @3.first_line));
    }
    ;

VarList:
    ParamDec COMMA VarList {
        $$ = plain_node("VarList", @$.first_line, 3,
            $1, plain_token("COMMA", "", @2.first_line), $3);
    }
    | ParamDec {
        $$ = plain_node("VarList", @$.first_line, 1, $1);
    }
    ;

ParamDec:
    Specifier VarDec {
        $$ = plain_node("ParamDec", @$.first_line, 2, $1, $2);
    }
    ;

CompSt:
    LC DefList StmtList RC {
        $$ = plain_node("CompSt", @$.first_line, 4,
            plain_token("LC", "", @1.first_line), $2, $3,
            plain_token("RC", "", @4.first_line));
    }
    ;

StmtList:
    Stmt StmtList {
        $$ = plain_node("StmtList", @$.first_line, 2, $1, $2);
    }
    | %empty { $$ = NULL; }
    ;

Stmt:
    Exp SEMI {
        $$ = plain_node("Stmt", @$.first_line, 2,
            $1, plain_token("SEMI", "", @2.first_line));
    }
    | Exp error {
        plain_free($1);
        if (statement_boundary(yychar)) {
            yyerrok;
        }
        $$ = NULL;
    }
    | Exp error SEMI {
        plain_free($1);
        yyerrok;
        $$ = NULL;
    }
    | CompSt {
        $$ = plain_node("Stmt", @$.first_line, 1, $1);
    }
    | RETURN Exp SEMI {
        $$ = plain_node("Stmt", @$.first_line, 3,
            plain_token("RETURN", "", @1.first_line), $2,
            plain_token("SEMI", "", @3.first_line));
    }
    | RETURN Exp error {
        plain_free($2);
        if (statement_boundary(yychar)) {
            yyerrok;
        }
        $$ = NULL;
    }
    | RETURN Exp error SEMI {
        plain_free($2);
        yyerrok;
        $$ = NULL;
    }
    | RETURN error {
        if (statement_boundary(yychar)) {
            yyerrok;
        }
        $$ = NULL;
    }
    | RETURN error SEMI {
        yyerrok;
        $$ = NULL;
    }
    | IF LP Exp RP Stmt %prec LOWER_THAN_ELSE {
        $$ = plain_node("Stmt", @$.first_line, 5,
            plain_token("IF", "", @1.first_line),
            plain_token("LP", "", @2.first_line), $3,
            plain_token("RP", "", @4.first_line), $5);
    }
    | IF LP Exp RP Stmt ELSE Stmt {
        $$ = plain_node("Stmt", @$.first_line, 7,
            plain_token("IF", "", @1.first_line),
            plain_token("LP", "", @2.first_line), $3,
            plain_token("RP", "", @4.first_line), $5,
            plain_token("ELSE", "", @6.first_line), $7);
    }
    | WHILE LP Exp RP Stmt {
        $$ = plain_node("Stmt", @$.first_line, 5,
            plain_token("WHILE", "", @1.first_line),
            plain_token("LP", "", @2.first_line), $3,
            plain_token("RP", "", @4.first_line), $5);
    }
    | error SEMI {
        yyerrok;
        $$ = NULL;
    }
    ;
DefList:
    Def DefList {
        $$ = plain_node("DefList", @$.first_line, 2, $1, $2);
    }
    | %empty { $$ = NULL; }
    ;

Def:
    Specifier DecList SEMI {
        $$ = plain_node("Def", @$.first_line, 3,
            $1, $2, plain_token("SEMI", "", @3.first_line));
    }
    | Specifier DecList error {
        plain_free($1);
        plain_free($2);
        if (yychar == TYPE || yychar == STRUCT || statement_boundary(yychar)) {
            yyerrok;
        }
        $$ = NULL;
    }
    | Specifier DecList error SEMI {
        plain_free($1);
        plain_free($2);
        yyerrok;
        $$ = NULL;
    }
    | Specifier error SEMI {
        plain_free($1);
        yyerrok;
        $$ = NULL;
    }
    | Specifier error {
        plain_free($1);
        if (yychar == TYPE || yychar == STRUCT || statement_boundary(yychar)) {
            yyerrok;
        }
        $$ = NULL;
    }
    ;

DecList:
    Dec {
        $$ = plain_node("DecList", @$.first_line, 1, $1);
    }
    | Dec COMMA DecList {
        $$ = plain_node("DecList", @$.first_line, 3,
            $1, plain_token("COMMA", "", @2.first_line), $3);
    }
    ;

Dec:
    VarDec {
        $$ = plain_node("Dec", @$.first_line, 1, $1);
    }
    | VarDec ASSIGNOP Exp {
        $$ = plain_node("Dec", @$.first_line, 3,
            $1, plain_token("ASSIGNOP", "", @2.first_line), $3);
    }
    ;

Exp:
    Exp ASSIGNOP Exp {
        $$ = plain_node("Exp", @$.first_line, 3,
            $1, plain_token("ASSIGNOP", "", @2.first_line), $3);
    }
    | Exp AND Exp {
        $$ = plain_node("Exp", @$.first_line, 3,
            $1, plain_token("AND", "", @2.first_line), $3);
    }
    | Exp OR Exp {
        $$ = plain_node("Exp", @$.first_line, 3,
            $1, plain_token("OR", "", @2.first_line), $3);
    }
    | Exp RELOP Exp {
        $$ = plain_node("Exp", @$.first_line, 3,
            $1, plain_text_token("RELOP", $2, @2.first_line), $3);
    }
    | Exp PLUS Exp {
        $$ = plain_node("Exp", @$.first_line, 3,
            $1, plain_token("PLUS", "", @2.first_line), $3);
    }
    | Exp MINUS Exp {
        $$ = plain_node("Exp", @$.first_line, 3,
            $1, plain_token("MINUS", "", @2.first_line), $3);
    }
    | Exp STAR Exp {
        $$ = plain_node("Exp", @$.first_line, 3,
            $1, plain_token("STAR", "", @2.first_line), $3);
    }
    | Exp DIV Exp {
        $$ = plain_node("Exp", @$.first_line, 3,
            $1, plain_token("DIV", "", @2.first_line), $3);
    }
    | LP Exp RP {
        $$ = plain_node("Exp", @$.first_line, 3,
            plain_token("LP", "", @1.first_line), $2,
            plain_token("RP", "", @3.first_line));
    }
    | MINUS Exp %prec UMINUS {
        $$ = plain_node("Exp", @$.first_line, 2,
            plain_token("MINUS", "", @1.first_line), $2);
    }
    | NOT Exp {
        $$ = plain_node("Exp", @$.first_line, 2,
            plain_token("NOT", "", @1.first_line), $2);
    }
    | ID LP Args RP {
        $$ = plain_node("Exp", @$.first_line, 4,
            plain_text_token("ID", $1, @1.first_line),
            plain_token("LP", "", @2.first_line), $3,
            plain_token("RP", "", @4.first_line));
    }
    | ID LP RP {
        $$ = plain_node("Exp", @$.first_line, 3,
            plain_text_token("ID", $1, @1.first_line),
            plain_token("LP", "", @2.first_line),
            plain_token("RP", "", @3.first_line));
    }
    | Exp LB Exp RB %prec LB {
        $$ = plain_node("Exp", @$.first_line, 4,
            $1, plain_token("LB", "", @2.first_line), $3,
            plain_token("RB", "", @4.first_line));
    }
    | Exp DOT ID {
        $$ = plain_node("Exp", @$.first_line, 3,
            $1, plain_token("DOT", "", @2.first_line),
            plain_text_token("ID", $3, @3.first_line));
    }
    | ID {
        $$ = plain_node("Exp", @$.first_line, 1,
            plain_text_token("ID", $1, @1.first_line));
    }
    | INT {
        $$ = plain_node("Exp", @$.first_line, 1,
            plain_int_token($1, @1.first_line));
    }
    | FLOAT {
        $$ = plain_node("Exp", @$.first_line, 1,
            plain_float_token($1, @1.first_line));
    }
    ;

Args:
    Exp COMMA Args {
        $$ = plain_node("Args", @$.first_line, 3,
            $1, plain_token("COMMA", "", @2.first_line), $3);
    }
    | Exp {
        $$ = plain_node("Args", @$.first_line, 1, $1);
    }
    ;

%%

void yyerror(BaseAST **ast, char const *err_info) {
    (void)ast;
    if (yychar == INVALID && strcmp(err_info, YY_("syntax error")) == 0) {
        return;
    }
    fprintf(ERR_STREAM, "Error type B at Line %d: %s\n", yylloc.first_line, err_info);
    cmm_error_count++;
}
