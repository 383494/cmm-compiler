#pragma once

#include "ast_defs.h"
#include <stdbool.h>

struct Type;

typedef struct SemanticContext SemanticContext;

typedef struct ExprValue {
	struct Type *type;
	bool lvalue;
} ExprValue;

typedef struct DefOps {
	void (*check)(BaseDef *this, SemanticContext *ctx);
} DefOps;

typedef struct SpecOps {
	struct Type *(*resolve)(BaseSpecifier *this, SemanticContext *ctx);
	void (*declare)(BaseSpecifier *this, SemanticContext *ctx);
} SpecOps;

typedef struct StmtOps {
	void (*check)(BaseStmt *this, SemanticContext *ctx);
} StmtOps;

typedef struct ExpOps {
	ExprValue (*check)(Exp *this, SemanticContext *ctx);
} ExpOps;

extern const DefOps sem_spec_def_ops;
extern const DefOps sem_var_init_defs_ops;
extern const DefOps sem_fun_dec_ops;
extern const SpecOps sem_type_specifier_ops;
extern const SpecOps sem_struct_decl_specifier_ops;
extern const SpecOps sem_struct_def_specifier_ops;
extern const StmtOps sem_exp_stmt_ops;
extern const StmtOps sem_return_stmt_ops;
extern const StmtOps sem_comp_st_ops;
extern const StmtOps sem_if_stmt_ops;
extern const StmtOps sem_while_stmt_ops;

const ExpOps *sem_exp_ops_for_kind(ExpKind kind);
