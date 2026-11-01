#include "semantic.h"

#include "ast_ops.h"

#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "utils/common.h"

#define ERR_STREAM MUXDEF(CMM_OUTPUT_STDERR, stderr, stdout)

#ifndef CMM_ENABLE_FUNCTION_DECLARATIONS
#	define CMM_ENABLE_FUNCTION_DECLARATIONS 1
#endif
#ifndef CMM_ENABLE_COMPARE_ARRAY_SIZE
#	define CMM_ENABLE_COMPARE_ARRAY_SIZE 0
#endif
#ifndef CMM_ENABLE_NESTED_SCOPES
#	define CMM_ENABLE_NESTED_SCOPES 1
#endif
#ifndef CMM_ENABLE_STRUCTURAL_STRUCTS
#	define CMM_ENABLE_STRUCTURAL_STRUCTS 1
#endif

extern unsigned int cmm_error_count;
extern int cmm_last_error_line;

typedef enum {
	TY_ERROR,
	TY_INT,
	TY_FLOAT,
	TY_ARRAY,
	TY_STRUCT,
} TypeKind;

typedef struct Type Type;
typedef struct StructInfo StructInfo;

struct Type {
	TypeKind kind;
	Type *elem;          // TY_ARRAY
	int length;          // TY_ARRAY
	StructInfo *struc;   // TY_STRUCT
};

typedef struct StructField {
	const char *name;
	Type *type;
} StructField;

struct StructInfo {
	const char *tag;   // NULL for anonymous structs
	DEQUE_T(StructField) fields;
	Type *type;
};

typedef struct VarInfo {
	const char *name;
	Type *type;
} VarInfo;

typedef struct FuncInfo {
	const char *name;
	Type *ret;
	DEQUE_T(Type *) param_types;
	bool defined;
	int decl_line;
} FuncInfo;

typedef struct Scope {
	struct Scope *parent;
	STRMAP_T(VarInfo *) vars;
	STRMAP_T(StructInfo *) structs;
} Scope;

typedef struct Arena {
	DEQUE_T(void *) blocks;
} Arena;

typedef struct Checker {
	Arena arena;
	Type *t_int;
	Type *t_float;
	Type *t_error;
	STRMAP_T(FuncInfo *) funcs;
	DEQUE_T(FuncInfo *) all_funcs;
	DEQUE_T(StructInfo *) all_structs;
	Type *current_return;
} Checker;

struct SemanticContext {
	Checker *checker;
	Scope *scope;
};

static void semantic_error(int lineno, int type, const char *format, ...) {
	if(lineno == cmm_last_error_line) {
		return;
	}
	fprintf(ERR_STREAM, "Error type %d at Line %d: ", type, lineno);
	va_list args;
	va_start(args, format);
	vfprintf(ERR_STREAM, format, args);
	va_end(args);
	fputc('\n', ERR_STREAM);
	++cmm_error_count;
	cmm_last_error_line = lineno;
}

static void *arena_alloc(Arena *arena, size_t size) {
	void *block = calloc(1, size);
	if(block == NULL) {
		abort();
	}
	dq_push_back_handle(arena->blocks, block);
	return block;
}

static void arena_free(Arena *arena) {
	dq_foreach(arena->blocks, i) {
		free(dq_at(arena->blocks, i));
	}
	dq_free_handle(arena->blocks);
}

static Type *new_type(Checker *c, TypeKind kind) {
	Type *type = arena_alloc(&c->arena, sizeof *type);
	type->kind = kind;
	return type;
}

static bool is_numeric(Type *type) {
	return type != NULL && (type->kind == TY_INT || type->kind == TY_FLOAT);
}

static bool is_error_type(Type *type) {
	if(type == NULL) {
		return true;
	}
	if(type->kind == TY_ERROR) {
		return true;
	}
	if(type->kind == TY_ARRAY) {
		return is_error_type(type->elem);
	}
	return false;
}

static bool types_equal(Type *lhs, Type *rhs);

#if CMM_ENABLE_STRUCTURAL_STRUCTS
static bool structs_equal(StructInfo *lhs, StructInfo *rhs) {
	if(lhs == rhs) {
		return true;
	}
	if(lhs == NULL || rhs == NULL) {
		return false;
	}
	size_t count = dq_len(lhs->fields);
	if(count != dq_len(rhs->fields)) {
		return false;
	}
	for(size_t i = 0; i < count; ++i) {
		StructField *left = &dq_at(lhs->fields, i);
		StructField *right = &dq_at(rhs->fields, i);
		if(!types_equal(left->type, right->type)) {
			return false;
		}
	}
	return true;
}
#endif

static bool types_equal(Type *lhs, Type *rhs) {
	if(lhs == rhs) {
		return true;
	}
	if(lhs == NULL || rhs == NULL || lhs->kind != rhs->kind) {
		return false;
	}
	switch(lhs->kind) {
	case TY_ARRAY:
#if CMM_ENABLE_COMPARE_ARRAY_SIZE
		return lhs->length == rhs->length && types_equal(lhs->elem, rhs->elem);
#else
		return types_equal(lhs->elem, rhs->elem);
#endif
	case TY_STRUCT:
#if CMM_ENABLE_STRUCTURAL_STRUCTS
		return structs_equal(lhs->struc, rhs->struc);
#else
		return lhs->struc == rhs->struc;
#endif
	default:
		return true;
	}
}

static VarInfo *find_var(Scope *scope, const char *name) {
#if CMM_ENABLE_NESTED_SCOPES
	for(; scope != NULL; scope = scope->parent) {
		VarInfo *var = strmap_get(scope->vars, name);
		if(var != NULL) {
			return var;
		}
	}
	return NULL;
#else
	if(scope == NULL) {
		return NULL;
	}
	return strmap_get(scope->vars, name);
#endif
}

static StructInfo *find_struct(Scope *scope, const char *name) {
#if CMM_ENABLE_NESTED_SCOPES
	for(; scope != NULL; scope = scope->parent) {
		StructInfo *info = strmap_get(scope->structs, name);
		if(info != NULL) {
			return info;
		}
	}
	return NULL;
#else
	if(scope == NULL) {
		return NULL;
	}
	return strmap_get(scope->structs, name);
#endif
}

static StructField *find_field(StructInfo *info, const char *name) {
	dq_foreach(info->fields, i) {
		StructField *field = &dq_at(info->fields, i);
		if(strcmp(field->name, name) == 0) {
			return field;
		}
	}
	return NULL;
}

static Scope *enter_scope(SemanticContext *ctx, Scope *storage) {
#if CMM_ENABLE_NESTED_SCOPES
	*storage = (Scope){.parent = ctx->scope};
	return storage;
#else
	(void)storage;
	return ctx->scope;
#endif
}

static void leave_scope(Scope *scope, Scope *storage) {
	(void)scope;
#if CMM_ENABLE_NESTED_SCOPES
	strmap_free_handle(storage->vars);
	strmap_free_handle(storage->structs);
#else
	(void)storage;
#endif
}

static StructInfo *new_struct_info(Checker *c, const char *tag) {
	StructInfo *info = arena_alloc(&c->arena, sizeof *info);
	info->tag = tag;
	info->type = new_type(c, TY_STRUCT);
	info->type->struc = info;
	dq_push_back_handle(c->all_structs, info);
	return info;
}

static Type *array_type(Checker *c, Type *elem, int length) {
	Type *type = new_type(c, TY_ARRAY);
	type->elem = elem;
	type->length = length;
	return type;
}

static Type *make_var_type(Checker *c, Type *base, DEQUE_T(int) dims,
						   size_t index) {
	if(index >= dq_len(dims)) {
		return base;
	}
	return array_type(c, make_var_type(c, base, dims, index + 1), dq_at(dims, index));
}

static void define_var(Checker *c, Scope *scope, const char *name, Type *type,
					   int lineno) {
	if(strmap_has(scope->vars, name)) {
		semantic_error(lineno, 3, "redefinition of variable '%s'", name);
		return;
	}
	if(find_struct(scope, name) != NULL) {
		semantic_error(lineno, 3, "variable '%s' conflicts with a previously defined struct", name);
	}
	VarInfo *info = arena_alloc(&c->arena, sizeof *info);
	info->name = name;
	info->type = type;
	strmap_put_handle(scope->vars, name, info);
}

static void register_struct(Checker *c, Scope *scope, StructInfo *info,
							int lineno) {
	(void)c;
	if(info->tag == NULL) {
		return;
	}
	StructInfo *previous = find_struct(scope, info->tag);
	VarInfo *variable = find_var(scope, info->tag);
	if(previous != NULL) {
		semantic_error(lineno, 16, "struct name '%s' conflicts with a previous definition", info->tag);
		return;
	}
	if(variable != NULL) {
		semantic_error(lineno, 16, "struct name '%s' conflicts with a previous variable", info->tag);
	}
	strmap_put_handle(scope->structs, info->tag, info);
}

static ExprValue error_value(SemanticContext *ctx) {
	return (ExprValue){.type = ctx->checker->t_error, .lvalue = false};
}

static ExprValue expr_value(Type *type, bool lvalue) {
	return (ExprValue){.type = type, .lvalue = lvalue};
}

static ExprValue check_exp(SemanticContext *ctx, Exp *exp) {
	if(exp == NULL || exp->ops == NULL || exp->ops->check == NULL) {
		return error_value(ctx);
	}
	return CALL(exp, ops->check, ctx);
}

static Type *resolve_spec(SemanticContext *ctx, BaseSpecifier *spec) {
	if(spec == NULL || spec->ops == NULL || spec->ops->resolve == NULL) {
		return ctx->checker->t_error;
	}
	return CALL(spec, ops->resolve, ctx);
}

static void check_stmt(SemanticContext *ctx, BaseStmt *stmt) {
	CALLN(stmt, ops->check, ctx);
}

static bool numeric_operands(SemanticContext *ctx, Exp *exp,
							 Type **operand_type) {
	ExprValue lhs = check_exp(ctx, exp->lhs);
	ExprValue rhs = check_exp(ctx, exp->rhs);
	if(is_error_type(lhs.type) || is_error_type(rhs.type)) {
		return false;
	}
	if(!is_numeric(lhs.type) || !is_numeric(rhs.type) ||
	   lhs.type->kind != rhs.type->kind) {
		semantic_error(exp->super.lineno, 7, "invalid operand types for operator");
		return false;
	}
	*operand_type = lhs.type;
	return true;
}

static bool integer_operands(SemanticContext *ctx, Exp *exp) {
	ExprValue lhs = check_exp(ctx, exp->lhs);
	ExprValue rhs = check_exp(ctx, exp->rhs);
	if(is_error_type(lhs.type) || is_error_type(rhs.type)) {
		return false;
	}
	if(lhs.type->kind != TY_INT || rhs.type->kind != TY_INT) {
		semantic_error(exp->super.lineno, 7, "logical operands must have type int");
		return false;
	}
	return true;
}

static void check_condition(SemanticContext *ctx, Exp *cond) {
	Type *type = check_exp(ctx, cond).type;
	if(is_error_type(type)) {
		return;
	}
	if(type->kind != TY_INT) {
		semantic_error(cond->super.lineno, 7, "condition must have type int");
	}
}

static void check_compst_body(SemanticContext *ctx, CompSt *comp) {
	dq_foreach(comp->defs, i) {
		BaseDef *def = dq_at(comp->defs, i);
		CALLN(def, ops->check, ctx);
	}
	dq_foreach(comp->stmts, i) {
		check_stmt(ctx, dq_at(comp->stmts, i));
	}
}

static void check_spec_def(BaseDef *base, SemanticContext *ctx) {
	SpecDef *this = (SpecDef *)base;
	CALLN(this->super.spec, ops->declare, ctx);
}

static void check_var_init_defs(BaseDef *base, SemanticContext *ctx) {
	VarInitDefs *this = (VarInitDefs *)base;
	Checker *c = ctx->checker;
	Type *base_type = resolve_spec(ctx, this->super.spec);
	dq_foreach(this->var_decs, i) {
		UntypedVarDef *var = dq_at(this->var_decs, i);
		Type *type = make_var_type(c, base_type, var->dims, 0);
		define_var(c, ctx->scope, var->name, type, var->super.lineno);
		if(var->opt_init == NULL) {
			continue;
		}
		Type *init = check_exp(ctx, var->opt_init).type;
		if(is_error_type(type) || is_error_type(init)) {
			continue;
		}
		if(type->kind == TY_ARRAY || !types_equal(type, init)) {
			semantic_error(var->super.lineno, 5, "type mismatch in initialization of '%s'", var->name);
		}
	}
}

static bool function_signature_equal(FuncInfo *info, Type *ret,
									 DEQUE_T(Type *) params) {
	if(!types_equal(info->ret, ret)) {
		return false;
	}
	if(dq_len(info->param_types) != dq_len(params)) {
		return false;
	}
	dq_foreach(params, i) {
		if(!types_equal(dq_at(info->param_types, i), dq_at(params, i))) {
			return false;
		}
	}
	return true;
}

static void check_fun_dec(BaseDef *base, SemanticContext *ctx) {
	FunDec *this = (FunDec *)base;
	Checker *c = ctx->checker;
	Type *ret = resolve_spec(ctx, this->super.spec);

	DEQUE_T(Type *) params = NULL;
	dq_foreach(this->params, i) {
		ParamDec *param = dq_at(this->params, i);
		Type *base_type = resolve_spec(ctx, param->spec);
		Type *type = make_var_type(c, base_type, param->var_dec->dims, 0);
		dq_push_back_handle(params, type);
	}

#if CMM_ENABLE_FUNCTION_DECLARATIONS
	bool is_declaration = this->opt_body == NULL;
#else
	bool is_declaration = false;
#endif

	FuncInfo *info = strmap_get(c->funcs, this->name);
	if(info == NULL) {
		info = arena_alloc(&c->arena, sizeof *info);
		info->name = this->name;
		info->ret = ret;
		info->param_types = params;
		params = NULL;
		info->defined = !is_declaration;
		info->decl_line = is_declaration ? this->super.super.lineno : 0;
		strmap_put_handle(c->funcs, this->name, info);
		dq_push_back_handle(c->all_funcs, info);
	} else {
		if(!is_declaration && info->defined) {
			semantic_error(this->super.super.lineno, 4, "redefinition of function '%s'", this->name);
		} else if(!function_signature_equal(info, ret, params)) {
			if(!is_declaration) {
				semantic_error(this->super.super.lineno, 19, "definition of function '%s' conflicts with its declaration", this->name);
			} else if(info->defined) {
				semantic_error(this->super.super.lineno, 19, "declaration of function '%s' conflicts with its definition", this->name);
			} else {
				semantic_error(this->super.super.lineno, 19, "conflicting declarations of function '%s'", this->name);
			}
		}
		if(!is_declaration) {
			info->defined = true;
		} else if(info->decl_line == 0) {
			info->decl_line = this->super.super.lineno;
		}
		dq_free_handle(params);
		params = NULL;
	}

	if(this->opt_body != NULL) {
		Scope scope_storage;
		Scope *scope = enter_scope(ctx, &scope_storage);
		dq_foreach(this->params, i) {
			ParamDec *param = dq_at(this->params, i);
			Type *type;
			if(i < dq_len(info->param_types)) {
				type = dq_at(info->param_types, i);
			} else {
				Type *base_type = resolve_spec(ctx, param->spec);
				type = make_var_type(c, base_type, param->var_dec->dims, 0);
			}
			define_var(c, scope, param->var_dec->name, type, param->var_dec->super.lineno);
		}

		Type *previous_return = c->current_return;
		c->current_return = ret;
		SemanticContext body = {.checker = c, .scope = scope};
		check_compst_body(&body, this->opt_body);
		c->current_return = previous_return;
		leave_scope(scope, &scope_storage);
	}
}

static Type *check_type_specifier(BaseSpecifier *base, SemanticContext *ctx) {
	TypeSpecifier *this = (TypeSpecifier *)base;
	if(strcmp(this->type, "int") == 0) {
		return ctx->checker->t_int;
	}
	if(strcmp(this->type, "float") == 0) {
		return ctx->checker->t_float;
	}
	return ctx->checker->t_error;
}

static void declare_type_specifier(BaseSpecifier *base, SemanticContext *ctx) {
	(void)base;
	(void)ctx;
}

static Type *check_struct_decl_specifier(BaseSpecifier *base,
										 SemanticContext *ctx) {
	StructDeclSpecifier *this = (StructDeclSpecifier *)base;
	StructInfo *info = find_struct(ctx->scope, this->tag);
	if(info == NULL) {
		semantic_error(base->super.lineno, 17, "undefined struct '%s'", this->tag);
		return ctx->checker->t_error;
	}
	return info->type;
}

static void declare_struct_decl_specifier(BaseSpecifier *base,
										  SemanticContext *ctx) {
	(void)base;
	(void)ctx;
}

static Type *check_struct_def_specifier(BaseSpecifier *base,
										SemanticContext *ctx) {
	StructDefSpecifier *this = (StructDefSpecifier *)base;
	Checker *c = ctx->checker;
	StructInfo *info = new_struct_info(c, this->opt_tag);
	dq_foreach(this->defs, i) {
		VarInitDefs *vars = (VarInitDefs *)dq_at(this->defs, i);
		if(vars == NULL) {
			continue;
		}
		Type *field_base = resolve_spec(ctx, vars->super.spec);
		dq_foreach(vars->var_decs, j) {
			UntypedVarDef *var = dq_at(vars->var_decs, j);
			if(var->opt_init != NULL) {
				semantic_error(var->super.lineno, 15, "initializer is not allowed in a struct definition");
			}
			Type *field_type = make_var_type(c, field_base, var->dims, 0);
			if(find_field(info, var->name) != NULL) {
				semantic_error(var->super.lineno, 15, "duplicate field '%s' in struct definition", var->name);
				continue;
			}
			StructField field = {.name = var->name, .type = field_type};
			dq_push_back_handle(info->fields, field);
		}
	}
	register_struct(c, ctx->scope, info, base->super.lineno);
	return info->type;
}

static void declare_struct_def_specifier(BaseSpecifier *base,
										 SemanticContext *ctx) {
	(void)check_struct_def_specifier(base, ctx);
}

static void check_exp_stmt(BaseStmt *base, SemanticContext *ctx) {
	ExpStmt *this = (ExpStmt *)base;
	(void)check_exp(ctx, this->exp);
}

static void check_return_stmt(BaseStmt *base, SemanticContext *ctx) {
	ReturnStmt *this = (ReturnStmt *)base;
	Checker *c = ctx->checker;
	Type *actual = check_exp(ctx, this->exp).type;
	if(c->current_return == NULL || is_error_type(actual) ||
	   is_error_type(c->current_return)) {
		return;
	}
	if(!types_equal(actual, c->current_return)) {
		semantic_error(this->super.super.lineno, 8, "return type does not match function return type");
	}
}

static void check_comp_st(BaseStmt *base, SemanticContext *ctx) {
	CompSt *this = (CompSt *)base;
	Scope child_storage;
	Scope *child = enter_scope(ctx, &child_storage);
	SemanticContext inner = {.checker = ctx->checker, .scope = child};
	check_compst_body(&inner, this);
	leave_scope(child, &child_storage);
}

static void check_if_stmt(BaseStmt *base, SemanticContext *ctx) {
	IfStmt *this = (IfStmt *)base;
	check_condition(ctx, this->cond);
	check_stmt(ctx, this->then);
	check_stmt(ctx, this->opt_else);
}

static void check_while_stmt(BaseStmt *base, SemanticContext *ctx) {
	WhileStmt *this = (WhileStmt *)base;
	check_condition(ctx, this->cond);
	check_stmt(ctx, this->body);
}

static ExprValue check_exp_ID(Exp *this, SemanticContext *ctx) {
	VarInfo *var = find_var(ctx->scope, this->name);
	if(var == NULL) {
		semantic_error(this->super.lineno, 1, "undefined variable '%s'", this->name);
		return expr_value(ctx->checker->t_error, true);
	}
	return expr_value(var->type, true);
}

static ExprValue check_exp_INT(Exp *this, SemanticContext *ctx) {
	(void)this;
	return expr_value(ctx->checker->t_int, false);
}

static ExprValue check_exp_FLOAT(Exp *this, SemanticContext *ctx) {
	(void)this;
	return expr_value(ctx->checker->t_float, false);
}

static ExprValue check_exp_ASSIGN(Exp *this, SemanticContext *ctx) {
	ExprValue lhs = check_exp(ctx, this->lhs);
	ExprValue rhs = check_exp(ctx, this->rhs);
	if(!lhs.lvalue) {
		semantic_error(this->super.lineno, 6, "left operand of assignment is not an lvalue");
		return expr_value(is_error_type(lhs.type) ? ctx->checker->t_error : lhs.type, false);
	}
	if(is_error_type(lhs.type) || is_error_type(rhs.type)) {
		return error_value(ctx);
	}
	if(lhs.type->kind == TY_ARRAY || !types_equal(lhs.type, rhs.type)) {
		semantic_error(this->super.lineno, 5, "type mismatch in assignment");
		return error_value(ctx);
	}
	return expr_value(lhs.type, false);
}

static ExprValue check_exp_AND(Exp *this, SemanticContext *ctx) {
	if(!integer_operands(ctx, this)) {
		return error_value(ctx);
	}
	return expr_value(ctx->checker->t_int, false);
}

static ExprValue check_exp_OR(Exp *this, SemanticContext *ctx) {
	if(!integer_operands(ctx, this)) {
		return error_value(ctx);
	}
	return expr_value(ctx->checker->t_int, false);
}

static ExprValue check_numeric_binary(Exp *this, SemanticContext *ctx) {
	Type *operand = NULL;
	if(!numeric_operands(ctx, this, &operand)) {
		return error_value(ctx);
	}
	return expr_value(operand, false);
}

static ExprValue check_exp_ADD(Exp *this, SemanticContext *ctx) {
	return check_numeric_binary(this, ctx);
}

static ExprValue check_exp_SUB(Exp *this, SemanticContext *ctx) {
	return check_numeric_binary(this, ctx);
}

static ExprValue check_exp_MUL(Exp *this, SemanticContext *ctx) {
	return check_numeric_binary(this, ctx);
}

static ExprValue check_exp_DIV(Exp *this, SemanticContext *ctx) {
	return check_numeric_binary(this, ctx);
}

static ExprValue check_relational(Exp *this, SemanticContext *ctx) {
	Type *operand = NULL;
	if(!numeric_operands(ctx, this, &operand)) {
		return error_value(ctx);
	}
	return expr_value(ctx->checker->t_int, false);
}

static ExprValue check_exp_EQ(Exp *this, SemanticContext *ctx) {
	return check_relational(this, ctx);
}

static ExprValue check_exp_NE(Exp *this, SemanticContext *ctx) {
	return check_relational(this, ctx);
}

static ExprValue check_exp_LT(Exp *this, SemanticContext *ctx) {
	return check_relational(this, ctx);
}

static ExprValue check_exp_LE(Exp *this, SemanticContext *ctx) {
	return check_relational(this, ctx);
}

static ExprValue check_exp_GT(Exp *this, SemanticContext *ctx) {
	return check_relational(this, ctx);
}

static ExprValue check_exp_GE(Exp *this, SemanticContext *ctx) {
	return check_relational(this, ctx);
}

static ExprValue check_exp_NEG(Exp *this, SemanticContext *ctx) {
	ExprValue operand = check_exp(ctx, this->lhs);
	if(is_error_type(operand.type)) {
		return error_value(ctx);
	}
	if(!is_numeric(operand.type)) {
		semantic_error(this->super.lineno, 7, "invalid operand type for unary '-'");
		return error_value(ctx);
	}
	return expr_value(operand.type, false);
}

static ExprValue check_exp_NOT(Exp *this, SemanticContext *ctx) {
	ExprValue operand = check_exp(ctx, this->lhs);
	if(is_error_type(operand.type)) {
		return error_value(ctx);
	}
	if(operand.type->kind != TY_INT) {
		semantic_error(this->super.lineno, 7, "operand of '!' must have type int");
		return error_value(ctx);
	}
	return expr_value(ctx->checker->t_int, false);
}

static ExprValue check_exp_CALL_EXPR(Exp *this, SemanticContext *ctx) {
	Checker *c = ctx->checker;
	DEQUE_T(Type *) arg_types = NULL;
	dq_foreach(this->args, i) {
		ExprValue arg = check_exp(ctx, dq_at(this->args, i));
		dq_push_back_handle(arg_types, arg.type);
	}

	FuncInfo *func = strmap_get(c->funcs, this->name);
	if(func == NULL) {
		if(find_var(ctx->scope, this->name) != NULL) {
			semantic_error(this->super.lineno, 11, "'%s' is not a function", this->name);
		} else {
			semantic_error(this->super.lineno, 2, "undefined function '%s'", this->name);
		}
		dq_free_handle(arg_types);
		return error_value(ctx);
	}

	bool mismatch = dq_len(arg_types) != dq_len(func->param_types);
	size_t count = dq_len(arg_types);
	if(dq_len(func->param_types) < count) {
		count = dq_len(func->param_types);
	}
	for(size_t i = 0; i < count; ++i) {
		Type *actual = dq_at(arg_types, i);
		Type *expected = dq_at(func->param_types, i);
		if(!is_error_type(actual) && !is_error_type(expected) &&
		   !types_equal(actual, expected)) {
			mismatch = true;
		}
	}
	if(mismatch) {
		semantic_error(this->super.lineno, 9, "argument count or type mismatch in call to '%s'", this->name);
	}
	dq_free_handle(arg_types);
	return expr_value(func->ret, false);
}

static ExprValue check_exp_SUBSCRIPT(Exp *this, SemanticContext *ctx) {
	ExprValue base = check_exp(ctx, this->lhs);
	ExprValue index = check_exp(ctx, this->rhs);
	if(is_error_type(base.type)) {
		return expr_value(ctx->checker->t_error, true);
	}
	if(base.type->kind != TY_ARRAY) {
		semantic_error(this->super.lineno, 10, "subscript operator applied to a non-array");
		return expr_value(ctx->checker->t_error, true);
	}
	if(!is_error_type(index.type) && index.type->kind != TY_INT) {
		semantic_error(this->super.lineno, 12, "array subscript is not an integer");
	}
	return expr_value(base.type->elem, base.lvalue);
}

static ExprValue check_exp_MEMBER(Exp *this, SemanticContext *ctx) {
	ExprValue base = check_exp(ctx, this->lhs);
	if(is_error_type(base.type)) {
		return expr_value(ctx->checker->t_error, true);
	}
	if(base.type->kind != TY_STRUCT) {
		semantic_error(this->super.lineno, 13, "member access on a non-struct");
		return expr_value(ctx->checker->t_error, true);
	}
	StructField *field = find_field(base.type->struc, this->name);
	if(field == NULL) {
		semantic_error(this->super.lineno, 14, "struct has no field named '%s'", this->name);
		return expr_value(ctx->checker->t_error, true);
	}
	return expr_value(field->type, base.lvalue);
}

#define EXP_OPS_DEF(name) \
	static const ExpOps exp_##name##_ops = {.check = check_exp_##name};
APPLY(EXP_OPS_DEF, EXP_KINDS)
#undef EXP_OPS_DEF

const ExpOps *sem_exp_ops_for_kind(ExpKind kind) {
	switch(kind) {
#define EXP_CASE(name) \
	case EXP_##name:   \
		return &exp_##name##_ops;
		APPLY(EXP_CASE, EXP_KINDS)
#undef EXP_CASE
	}
	return NULL;
}

const DefOps sem_spec_def_ops = {.check = check_spec_def};
const DefOps sem_var_init_defs_ops = {.check = check_var_init_defs};
const DefOps sem_fun_dec_ops = {.check = check_fun_dec};

const SpecOps sem_type_specifier_ops = {.resolve = check_type_specifier,
										.declare = declare_type_specifier};
const SpecOps sem_struct_decl_specifier_ops = {
	.resolve = check_struct_decl_specifier,
	.declare = declare_struct_decl_specifier,
};
const SpecOps sem_struct_def_specifier_ops = {
	.resolve = check_struct_def_specifier,
	.declare = declare_struct_def_specifier,
};

const StmtOps sem_exp_stmt_ops = {.check = check_exp_stmt};
const StmtOps sem_return_stmt_ops = {.check = check_return_stmt};
const StmtOps sem_comp_st_ops = {.check = check_comp_st};
const StmtOps sem_if_stmt_ops = {.check = check_if_stmt};
const StmtOps sem_while_stmt_ops = {.check = check_while_stmt};

void semantic_check(Program *program) {
	if(program == NULL) {
		return;
	}

	Checker checker = {0};
	checker.t_int = new_type(&checker, TY_INT);
	checker.t_float = new_type(&checker, TY_FLOAT);
	checker.t_error = new_type(&checker, TY_ERROR);

	Scope global = {0};
	SemanticContext ctx = {.checker = &checker, .scope = &global};
	dq_foreach(program->ext_defs, i) {
		BaseDef *def = dq_at(program->ext_defs, i);
		CALLN(def, ops->check, &ctx);
	}

#if CMM_ENABLE_FUNCTION_DECLARATIONS
	dq_foreach(checker.all_funcs, i) {
		FuncInfo *info = dq_at(checker.all_funcs, i);
		if(info->decl_line != 0 && !info->defined) {
			semantic_error(info->decl_line, 18, "function '%s' declared but not defined", info->name);
		}
	}
#endif

	dq_foreach(checker.all_structs, i) {
		dq_free_handle(dq_at(checker.all_structs, i)->fields);
	}
	dq_foreach(checker.all_funcs, i) {
		dq_free_handle(dq_at(checker.all_funcs, i)->param_types);
	}
	dq_free_handle(checker.all_structs);
	dq_free_handle(checker.all_funcs);
	strmap_free_handle(global.vars);
	strmap_free_handle(global.structs);
	strmap_free_handle(checker.funcs);
	arena_free(&checker.arena);
}
