%{
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ast/ast_defs.h"
#include "utils/common.h"

#define ERR_STREAM MUXDEF(CMM_OUTPUT_STDERR, stderr, stdout)

int yylex(void);
void yyerror(BaseAST **ast, char const *err_info);

unsigned int cmm_error_count = 0;
int cmm_last_error_line = 0;
%}

%code requires {
#include "ast/ast_defs.h"
}

%code provides {
void yyerror(BaseAST **ast, char const *err_info);
extern unsigned int cmm_error_count;
extern int cmm_last_error_line;
}

%code {
static bool starts_statement(int token) {
    switch (token) {
    case ID: case INT: case FLOAT: case LP: case MINUS: case NOT:
    case LC: case RETURN: case IF: case WHILE: case RC: case ELSE:
        return true;
    default:
        return false;
    }
}

static bool starts_external(int token) {
    return token == TYPE || token == STRUCT;
}

static bool starts_declaration(int token) {
    return token == TYPE || token == STRUCT || starts_statement(token);
}

static ExpKind relop_kind(char *text) {
    ExpKind kind;
    if (strcmp(text, "==") == 0) {
        kind = EXP_EQ;
    } else if (strcmp(text, "!=") == 0) {
        kind = EXP_NE;
    } else if (strcmp(text, "<") == 0) {
        kind = EXP_LT;
    } else if (strcmp(text, "<=") == 0) {
        kind = EXP_LE;
    } else if (strcmp(text, ">") == 0) {
        kind = EXP_GT;
    } else if (strcmp(text, ">=") == 0) {
        kind = EXP_GE;
    } else {
        abort();
    }
    free(text);
    return kind;
}

static Exp *binary_exp(int lineno, ExpKind kind, Exp *lhs, Exp *rhs) {
    Exp *this = NEW(Exp, lineno, kind);
    this->lhs = lhs;
    this->rhs = rhs;
    return this;
}

static Exp *unary_exp(int lineno, ExpKind kind, Exp *operand) {
    Exp *this = NEW(Exp, lineno, kind);
    this->lhs = operand;
    return this;
}

#define LIST_PUSH(list, item) \
    do {                      \
        dq_push_front_handle((list), (item)); \
    } while (0)
}

%parse-param { BaseAST **ast }
%locations

%union {
    char *str_val;
    int int_val;
    float float_val;
    Program *program;
    BaseDef *base_def;
    BaseSpecifier *specifier;
    UntypedVarDef *vardef;
    FunDec *fundec;
    ParamDec *paramdec;
    CompSt *compst;
    BaseStmt *stmt;
    Exp *exp;
    BaseDef **def_list;
    UntypedVarDef **vardef_list;
    ParamDec **paramdec_list;
    BaseStmt **stmt_list;
    Exp **exp_list;
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

%type <program> Program
%type <base_def> ExtDef Def
%type <specifier> Specifier StructSpecifier
%type <str_val> OptTag Tag
%type <vardef> VarDec Dec
%type <fundec> FunDec
%type <paramdec> ParamDec
%type <compst> CompSt
%type <stmt> Stmt
%type <exp> Exp
%type <def_list> ExtDefList DefList
%type <vardef_list> ExtDecList DecList
%type <paramdec_list> VarList
%type <stmt_list> StmtList
%type <exp_list> Args

%destructor { free($$); } <str_val>
%destructor { free_ast($$); } <program> <base_def> <specifier> <vardef> <fundec> <paramdec> <compst> <stmt> <exp>
%destructor { free_ast_list($$); } <def_list> <vardef_list> <paramdec_list> <stmt_list> <exp_list>

%%

Program:
    ExtDefList {
        *ast = (BaseAST *)NEW(Program, @$.first_line, $1);
        $$ = NULL;
    }
    ;

ExtDefList:
    ExtDef ExtDefList {
        DEQUE_T(BaseDef*) list = $2;
        LIST_PUSH(list, $1);
        $$ = list;
    }
    | %empty { $$ = NULL; }
    ;

ExtDef:
    Specifier ExtDecList SEMI {
        // int x, y[2];
        $$ = (BaseDef *)NEW(VarInitDefs, @$.first_line, $1, $2);
    }
    | Specifier ExtDecList error {
        free_ast($1);
        free_ast_list($2);
        if (starts_external(yychar)) {
            yyerrok;
        }
        $$ = NULL;
    }
    | Specifier ExtDecList error SEMI {
        free_ast($1);
        free_ast_list($2);
        yyerrok;
        $$ = NULL;
    }
    | Specifier SEMI {
        // struct { ... };
        $$ = (BaseDef *)NEW(SpecDef, @$.first_line, $1);
    }
/*@if FEATURE_ENABLE_FUNCTION_DECLARATIONS@*/
    | Specifier FunDec SEMI {
        FunDec *this = $2;
        if (this == NULL) {
            free_ast($1);
        } else {
            this->super.spec = $1;
            this->opt_body = NULL;
            ((BaseAST *)this)->lineno = @$.first_line;
        }
        $$ = (BaseDef *)this;
    }
/*@endif@*/
    | Specifier FunDec CompSt {
        FunDec *this = $2;
        if (this == NULL) {
            free_ast($1);
            free_ast($3);
        } else {
            this->super.spec = $1;
            this->opt_body = $3;
            ((BaseAST *)this)->lineno = @$.first_line;
        }
        $$ = (BaseDef *)this;
    }
    | error SEMI {
        yyerrok;
        $$ = NULL;
    }
    ;

ExtDecList:
    VarDec {
        DEQUE_T(UntypedVarDef*) list = NULL;
        LIST_PUSH(list, $1);
        $$ = list;
    }
    | VarDec COMMA ExtDecList {
        DEQUE_T(UntypedVarDef*) list = $3;
        LIST_PUSH(list, $1);
        $$ = list;
    }
    ;

Specifier:
    TYPE {
        $$ = (BaseSpecifier *)NEW(TypeSpecifier, @$.first_line, $1);
    }
    | StructSpecifier {
        $$ = $1;
    }
    ;

StructSpecifier:
    STRUCT OptTag LC DefList RC {
        $$ = (BaseSpecifier *)NEW(StructDefSpecifier, @$.first_line, $2, $4);
    }
    | STRUCT Tag {
        $$ = (BaseSpecifier *)NEW(StructDeclSpecifier, @$.first_line, $2);
    }
    | STRUCT OptTag LC error RC {
        free($2);
        yyerrok;
        $$ = NULL;
    }
    ;

OptTag:
    ID {
        $$ = $1;
    }
    | %empty { $$ = NULL; }
    ;

Tag:
    ID {
        $$ = $1;
    }
    ;

VarDec:
    ID {
        $$ = NEW(UntypedVarDef, @$.first_line, $1, NULL, NULL);
    }
    | VarDec LB INT RB {
        UntypedVarDef *this = $1;
        dq_push_back_handle(this->dims, $3);
        $$ = this;
    }
    | VarDec LB error RB {
        yyerrok;
        $$ = $1;
    }
    ;

FunDec:
    ID LP VarList RP {
        $$ = NEW(FunDec, @$.first_line, NULL, $1, $3, NULL);
    }
    | ID LP RP {
        $$ = NEW(FunDec, @$.first_line, NULL, $1, NULL, NULL);
    }
    | ID LP error RP {
        free($1);
        yyerrok;
        $$ = NULL;
    }
    ;

VarList:
    ParamDec COMMA VarList {
        DEQUE_T(ParamDec*) list = $3;
        LIST_PUSH(list, $1);
        $$ = list;
    }
    | ParamDec {
        DEQUE_T(ParamDec*) list = NULL;
        LIST_PUSH(list, $1);
        $$ = list;
    }
    ;

ParamDec:
    Specifier VarDec {
        $$ = NEW(ParamDec, @$.first_line, $1, $2);
    }
    ;

CompSt:
    LC DefList StmtList RC {
        $$ = NEW(CompSt, @$.first_line, $2, $3);
    }
    ;

StmtList:
    Stmt StmtList {
        DEQUE_T(BaseStmt*) list = $2;
        LIST_PUSH(list, $1);
        $$ = list;
    }
    | %empty { $$ = NULL; }
    ;

Stmt:
    Exp SEMI {
        $$ = (BaseStmt *)NEW(ExpStmt, @$.first_line, $1);
    }
    | Exp error {
        free_ast($1);
        $$ = NULL;
    }
    | Exp error SEMI {
        free_ast($1);
        yyerrok;
        $$ = NULL;
    }
    | CompSt {
        $$ = (BaseStmt *)$1;
    }
    | RETURN Exp SEMI {
        $$ = (BaseStmt *)NEW(ReturnStmt, @$.first_line, $2);
    }
    | RETURN Exp error {
        free_ast($2);
        if (starts_statement(yychar)) {
            yyerrok;
        }
        $$ = NULL;
    }
    | RETURN Exp error SEMI {
        free_ast($2);
        yyerrok;
        $$ = NULL;
    }
    | RETURN error {
        if (starts_statement(yychar)) {
            yyerrok;
        }
        $$ = NULL;
    }
    | RETURN error SEMI {
        yyerrok;
        $$ = NULL;
    }
    | IF LP Exp RP Stmt %prec LOWER_THAN_ELSE {
        $$ = (BaseStmt *)NEW(IfStmt, @$.first_line, $3, $5, NULL);
    }
    | IF LP Exp RP Stmt ELSE Stmt {
        $$ = (BaseStmt *)NEW(IfStmt, @$.first_line, $3, $5, $7);
    }
    | WHILE LP Exp RP Stmt {
        $$ = (BaseStmt *)NEW(WhileStmt, @$.first_line, $3, $5);
    }
    | IF LP error RP Stmt %prec LOWER_THAN_ELSE {
        free_ast($5);
        yyerrok;
        $$ = NULL;
    }
    | IF LP error RP Stmt ELSE Stmt {
        free_ast($5);
        free_ast($7);
        yyerrok;
        $$ = NULL;
    }
    | WHILE LP error RP Stmt {
        free_ast($5);
        yyerrok;
        $$ = NULL;
    }
    | error SEMI {
        yyerrok;
        $$ = NULL;
    }
    ;

DefList:
    Def DefList {
        DEQUE_T(BaseDef*) list = $2;
        LIST_PUSH(list, $1);
        $$ = list;
    }
    | %empty { $$ = NULL; }
    ;

Def:
    Specifier DecList SEMI {
        $$ = (BaseDef *)NEW(VarInitDefs, @$.first_line, $1, $2);
    }
    | Specifier DecList error {
        free_ast($1);
        free_ast_list($2);
        if (starts_declaration(yychar)) {
            yyerrok;
        }
        $$ = NULL;
    }
    | Specifier DecList error SEMI {
        free_ast($1);
        free_ast_list($2);
        yyerrok;
        $$ = NULL;
    }
    | Specifier error SEMI {
        free_ast($1);
        yyerrok;
        $$ = NULL;
    }
    | Specifier error {
        free_ast($1);
        if (yychar == RC) {
            yyerrok;
        }
        $$ = NULL;
    }
    ;

DecList:
    Dec {
        DEQUE_T(UntypedVarDef*) list = NULL;
        LIST_PUSH(list, $1);
        $$ = list;
    }
    | Dec COMMA DecList {
        DEQUE_T(UntypedVarDef*) list = $3;
        LIST_PUSH(list, $1);
        $$ = list;
    }
    ;

Dec:
    VarDec {
        $$ = $1;
    }
    | VarDec ASSIGNOP Exp {
        UntypedVarDef *this = $1;
        this->opt_init = $3;
        $$ = this;
    }
    | VarDec ASSIGNOP error {
        free_ast($1);
        if (starts_statement(yychar)) {
            yyerrok;
        }
        $$ = NULL;
    }
    | VarDec ASSIGNOP LC error RC {
        free_ast($1);
        yyerrok;
        $$ = NULL;
    }
    ;

Exp:
    Exp ASSIGNOP Exp {
        $$ = binary_exp(@$.first_line, EXP_ASSIGN, $1, $3);
    }
    | Exp AND Exp {
        $$ = binary_exp(@$.first_line, EXP_AND, $1, $3);
    }
    | Exp OR Exp {
        $$ = binary_exp(@$.first_line, EXP_OR, $1, $3);
    }
    | Exp RELOP Exp {
        $$ = binary_exp(@$.first_line, relop_kind($2), $1, $3);
    }
    | Exp PLUS Exp {
        $$ = binary_exp(@$.first_line, EXP_ADD, $1, $3);
    }
    | Exp MINUS Exp {
        $$ = binary_exp(@$.first_line, EXP_SUB, $1, $3);
    }
    | Exp STAR Exp {
        $$ = binary_exp(@$.first_line, EXP_MUL, $1, $3);
    }
    | Exp DIV Exp {
        $$ = binary_exp(@$.first_line, EXP_DIV, $1, $3);
    }
    | LP Exp RP {
        $$ = $2;
    }
    | MINUS Exp %prec UMINUS {
        $$ = unary_exp(@$.first_line, EXP_NEG, $2);
    }
    | NOT Exp {
        $$ = unary_exp(@$.first_line, EXP_NOT, $2);
    }
    | ID LP Args RP {
        Exp *this = NEW(Exp, @$.first_line, EXP_CALL_EXPR);
        this->name = $1;
        this->args = $3;
        $$ = this;
    }
    | ID LP RP {
        Exp *this = NEW(Exp, @$.first_line, EXP_CALL_EXPR);
        this->name = $1;
        $$ = this;
    }
    | ID LP error RP {
        free($1);
        yyerrok;
        $$ = NULL;
    }
    | Exp LB Exp RB %prec LB {
        $$ = binary_exp(@$.first_line, EXP_SUBSCRIPT, $1, $3);
    }
    | Exp LB error RB %prec LB {
        free_ast($1);
        yyerrok;
        $$ = NULL;
    }
    | Exp DOT ID {
        Exp *this = NEW(Exp, @$.first_line, EXP_MEMBER);
        this->lhs = $1;
        this->name = $3;
        $$ = this;
    }
    | ID {
        Exp *this = NEW(Exp, @$.first_line, EXP_ID);
        this->name = $1;
        $$ = this;
    }
    | INT {
        Exp *this = NEW(Exp, @$.first_line, EXP_INT);
        this->int_val = $1;
        $$ = this;
    }
    | FLOAT {
        Exp *this = NEW(Exp, @$.first_line, EXP_FLOAT);
        this->float_val = $1;
        $$ = this;
    }
    ;

Args:
    Exp COMMA Args {
        DEQUE_T(Exp*) list = $3;
        LIST_PUSH(list, $1);
        $$ = list;
    }
    | Exp {
        DEQUE_T(Exp*) list = NULL;
        LIST_PUSH(list, $1);
        $$ = list;
    }
    ;

%%

void yyerror(BaseAST **ast, char const *err_info) {
    (void)ast;
    if (cmm_last_error_line == yylloc.first_line) {
        return;
    }
    if (yychar == INVALID && strcmp(err_info, YY_("syntax error")) == 0) {
        return;
    }
    fprintf(ERR_STREAM, "Error type B at Line %d: %s\n", yylloc.first_line, err_info);
    cmm_error_count++;
    cmm_last_error_line = yylloc.first_line;
}
