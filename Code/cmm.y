
%{

#include "ast/ast_defs.h"

int yylex();
void yyerror(char const*);

#define CAST_AST(type, name, val) type name = (type)val

%}

%parse-param { BaseAST** ast }

%union {
	char *str_val;
	int int_val;
    float float_val;
	BaseAST *ast_val;
    List *list_val; // list of BaseAST
}

%token <int_val> INT 
%token <float_val> FLOAT 
%token <str_val> ID
%token SEMI COMMA ASSIGNOP RELOP
%token PLUS MINUS STAR DIV
%token AND OR NOT DOT
%token TYPE
%token LP RP LB RB LC RC
%token STRUCT RETURN
%token IF ELSE WHILE
%nonassoc LOWER_THAN_ELSE
%nonassoc ELSE

%type <ast_val> Args CompSt Dec Def Exp ExtDef FunDec OptTag ParamDec Specifier Stmt StructSpecifier Tag VarDec 
%type <ast_val> DecList DefList ExtDecList ExtDefList StmtList VarList

%%

Program:
    ExtDefList {
        *ast = $1;
    }
    ;

ExtDefList:
    ExtDef ExtDefList {
        CAST_AST(PlainAST, ast, $2);
        $$ = ast;
    }
    | {
        $$ = NULL;
    }
    ;

ExtDef:
    Specifier ExtDecList SEMI {
        // int x;
        NEW(PlainAST, ast);
        strcpy(ast->type, "ExtDef");
        CAST_AST(PlainAST, x3, $3);
        CAST_AST(PlainAST, x2, $2);
        x2->sib = x3;
        CAST_AST(PlainAST, x1, $1);
        x1->sib = x2;
        ast->child = x1;
        ast->lineno = min(min(x1->lineno, x2->lineno), x3->lineno);
        $$ = ast;
    }
    | Specifier SEMI {
        // struct;
        NEW(PlainAST, ast);
        strcpy(ast->type, "ExtDef");
        CAST_AST(PlainAST, x2, $2);
        CAST_AST(PlainAST, x1, $1);
        x1->sib = x2;
        ast->child = x1;
        ast->lineno = min(x1->lineno, x2->lineno);
        $$ = ast;
    }
    | Specifier FunDec CompSt {
        // int f(){}
        NEW(PlainAST, ast);
        strcpy(ast->type, "ExtDef");
        CAST_AST(PlainAST, x3, $3);
        CAST_AST(PlainAST, x2, $2);
        x2->sib = x3;
        CAST_AST(PlainAST, x1, $1);
        x1->sib = x2;
        ast->child = x1;
        ast->lineno = min(min(x1->lineno, x2->lineno), x3->lineno);
        $$ = ast;
    }
    ;

ExtDecList:
    VarDec {
        NEW(PlainAST, ast);
        strcpy(ast->type, "ExtDecList");
        CAST_AST(PlainAST, x1, $1);
        x1->sib = NULL;
        ast->child = x1;
        ast->lineno = x1->lineno;
        $$ = ast;
    }
    | VarDec COMMA ExtDecList {
        NEW(PlainAST, ast);
        strcpy(ast->type, "ExtDecList");
        CAST_AST(PlainAST, x3, $3);
        CAST_AST(PlainAST, x2, $2);
        x2->sib = x3;
        CAST_AST(PlainAST, x1, $1);
        x1->sib = x2;
        ast->child = x1;
        ast->lineno = min(min(x1->lineno, x2->lineno), x3->lineno);
        $$ = ast;
    }
    ;

Specifier: TYPE 
    | StructSpecifier 
    ;

StructSpecifier: STRUCT OptTag LC DefList RC 
    | STRUCT Tag 
    ;

OptTag: ID 
    |   
    ;

Tag: ID 
    ;

VarDec: ID 
    | VarDec LB INT RB 
    ;

FunDec: ID LP VarList RP 
    | ID LP RP 
    ;

VarList: ParamDec COMMA VarList 
    | ParamDec 
    ;

ParamDec: Specifier VarDec 
    ;

CompSt: LC DefList StmtList RC 
    ;

StmtList: Stmt StmtList 
    |  
    ;

Stmt: Exp SEMI 
    | CompSt 
    | RETURN Exp SEMI 
    | IF LP Exp RP Stmt %prec LOWER_THAN_ELSE
    | IF LP Exp RP Stmt ELSE Stmt 
    | WHILE LP Exp RP Stmt 
    ;

DefList: Def DefList 
    |   
    ;

Def: Specifier DecList SEMI 
    ;

DecList: Dec 
    | Dec COMMA DecList 
    ;

Dec: VarDec 
    | VarDec ASSIGNOP Exp 
    ;

Exp: Exp ASSIGNOP Exp 
    | Exp AND Exp 
    | Exp OR Exp 
    | Exp RELOP Exp 
    | Exp PLUS Exp 
    | Exp MINUS Exp 
    | Exp STAR Exp 
    | Exp DIV Exp 
    | LP Exp RP 
    | MINUS Exp 
    | NOT Exp 
    | ID LP Args RP 
    | ID LP RP 
    | Exp LB Exp RB 
    | Exp DOT ID 
    | ID 
    | INT 
    | FLOAT 
    ;

Args: Exp COMMA Args 
    | Exp 
    ;

%%

void yyerror(char const *err_info) {
    printf("ERROR: %s", err_info);
}
