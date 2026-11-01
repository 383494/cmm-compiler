#pragma once
#include "utils/common.h"

typedef struct BaseAST {
	int lineno;
	void (*free)(void* this);   // recursively free this and its children
} BaseAST;

#define DEF_AST(parent, name, ...) \
	struct name {                  \
		parent super;              \
		__VA_ARGS__                \
	};

#define DECL_AST(parent, name, ...) \
	typedef struct name name;

typedef struct DefOps DefOps;
typedef struct SpecOps SpecOps;
typedef struct StmtOps StmtOps;
typedef struct ExpOps ExpOps;

#define EXP_KINDS(_) \
	_(ID)            \
	_(INT)           \
	_(FLOAT)         \
	_(ASSIGN)        \
	_(AND)           \
	_(OR)            \
	_(ADD)           \
	_(SUB)           \
	_(MUL)           \
	_(DIV)           \
	_(NEG)           \
	_(NOT)           \
	_(CALL_EXPR)     \
	_(SUBSCRIPT)     \
	_(MEMBER)        \
	_(EQ)            \
	_(NE)            \
	_(LT)            \
	_(LE)            \
	_(GT)            \
	_(GE)

typedef enum {
#define EXP_ENUM(name) EXP_##name,
	APPLY(EXP_ENUM, EXP_KINDS)
#undef EXP_ENUM
} ExpKind;

#define ASTs(_)                                                                   \
	_(BaseAST, Program, DEQUE_T(BaseDef*) ext_defs;)                              \
	_(BaseAST, BaseDef, BaseSpecifier* spec; const DefOps* ops;)                  \
	_(BaseDef, SpecDef, ;)                                                        \
	_(BaseDef, VarInitDefs, DEQUE_T(UntypedVarDef*) var_decs;)                    \
	_(BaseAST, UntypedVarDef, char* name; DEQUE_T(int) dims; Exp * opt_init;)     \
	_(BaseDef, FunDec, char* name; DEQUE_T(ParamDec*) params; CompSt * opt_body;) \
	_(BaseAST, BaseSpecifier, const SpecOps* ops;)                                \
	_(BaseSpecifier, TypeSpecifier, char* type;)                                  \
	_(BaseSpecifier, StructDeclSpecifier, char* tag;)                             \
	_(BaseSpecifier, StructDefSpecifier, char* opt_tag; DEQUE_T(BaseDef*) defs;)  \
	_(BaseAST, ParamDec, BaseSpecifier* spec; UntypedVarDef * var_dec;)           \
	_(BaseAST, BaseStmt, const StmtOps* ops;)                                     \
	_(BaseStmt, ExpStmt, Exp* exp;)                                               \
	_(BaseStmt, ReturnStmt, Exp* exp;)                                            \
	_(BaseStmt, CompSt, DEQUE_T(BaseDef*) defs; DEQUE_T(BaseStmt*) stmts;)        \
	_(BaseStmt, IfStmt, Exp* cond; BaseStmt * then; BaseStmt * opt_else;)         \
	_(BaseStmt, WhileStmt, Exp* cond; BaseStmt * body;)                           \
	_(BaseAST, Exp, ExpKind kind; const ExpOps* ops; char* name; int int_val;     \
	  float float_val;                                                            \
	  Exp * lhs;                                                                  \
	  Exp * rhs;                                                                  \
	  DEQUE_T(Exp*) args;)

APPLY(DECL_AST, ASTs)
APPLY(DEF_AST, ASTs)

void free_ast(void* node);
void free_ast_list(void* list);   // list should be DEQUE_T(T*)

Program* Program_init(void* buf, int lineno, DEQUE_T(BaseDef*) ext_defs);
SpecDef* SpecDef_init(void* buf, int lineno, BaseSpecifier* spec);
VarInitDefs* VarInitDefs_init(void* buf, int lineno, BaseSpecifier* spec,
							  DEQUE_T(UntypedVarDef*) var_decs);
UntypedVarDef* UntypedVarDef_init(void* buf, int lineno, char* name,
								  DEQUE_T(int) dims, Exp* opt_init);
FunDec* FunDec_init(void* buf, int lineno, BaseSpecifier* spec, char* name,
					DEQUE_T(ParamDec*) params, CompSt* opt_body);
TypeSpecifier* TypeSpecifier_init(void* buf, int lineno, char* type);
StructDeclSpecifier* StructDeclSpecifier_init(void* buf, int lineno, char* tag);
StructDefSpecifier* StructDefSpecifier_init(void* buf, int lineno, char* opt_tag,
											DEQUE_T(BaseDef*) defs);
ParamDec* ParamDec_init(void* buf, int lineno, BaseSpecifier* spec,
						UntypedVarDef* var_dec);
ExpStmt* ExpStmt_init(void* buf, int lineno, Exp* exp);
ReturnStmt* ReturnStmt_init(void* buf, int lineno, Exp* exp);
CompSt* CompSt_init(void* buf, int lineno, DEQUE_T(BaseDef*) defs,
					DEQUE_T(BaseStmt*) stmts);
IfStmt* IfStmt_init(void* buf, int lineno, Exp* cond, BaseStmt* then,
					BaseStmt* opt_else);
WhileStmt* WhileStmt_init(void* buf, int lineno, Exp* cond, BaseStmt* body);
Exp* Exp_init(void* buf, int lineno, ExpKind kind);
