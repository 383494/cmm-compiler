#include "ast_defs.h"
#include "ast_ops.h"
#include <stdlib.h>

static void BaseAST_init(void* buf, int lineno, void (*free_node)(void*)) {
	BaseAST* this = buf;
	this->lineno = lineno;
	this->free = free_node;
}

void free_ast(void* node) {
	CALLN((BaseAST*)node, free);
}

// converting DEQUE_T(T*) to DEQUE_T(BaseAST*) is strict-aliasing UB, but it just works
void free_ast_list(void* list) {
	DEQUE_T(BaseAST*) items = list;
	if(items == NULL) return;
	dq_foreach(items, i) {
		free_ast(dq_at(items, i));
	}
	dq_free_handle(items);
}

static void Program_free(void* buf) {
	Program* this = buf;
	free_ast_list(this->ext_defs);
	free(this);
}

static void SpecDef_free(void* buf) {
	SpecDef* this = buf;
	free_ast(this->super.spec);
	free(this);
}

static void VarInitDefs_free(void* buf) {
	VarInitDefs* this = buf;
	free_ast(this->super.spec);
	free_ast_list(this->var_decs);
	free(this);
}

static void UntypedVarDef_free(void* buf) {
	UntypedVarDef* this = buf;
	free(this->name);
	dq_free_handle(this->dims);
	free_ast(this->opt_init);
	free(this);
}

static void FunDec_free(void* buf) {
	FunDec* this = buf;
	free_ast(this->super.spec);
	free(this->name);
	free_ast_list(this->params);
	free_ast(this->opt_body);
	free(this);
}

static void TypeSpecifier_free(void* buf) {
	TypeSpecifier* this = buf;
	free(this->type);
	free(this);
}

static void StructDeclSpecifier_free(void* buf) {
	StructDeclSpecifier* this = buf;
	free(this->tag);
	free(this);
}

static void StructDefSpecifier_free(void* buf) {
	StructDefSpecifier* this = buf;
	free(this->opt_tag);
	free_ast_list(this->defs);
	free(this);
}

static void ParamDec_free(void* buf) {
	ParamDec* this = buf;
	free_ast(this->spec);
	free_ast(this->var_dec);
	free(this);
}

static void ExpStmt_free(void* buf) {
	ExpStmt* this = buf;
	free_ast(this->exp);
	free(this);
}

static void ReturnStmt_free(void* buf) {
	ReturnStmt* this = buf;
	free_ast(this->exp);
	free(this);
}

static void CompSt_free(void* buf) {
	CompSt* this = buf;
	free_ast_list(this->defs);
	free_ast_list(this->stmts);
	free(this);
}

static void IfStmt_free(void* buf) {
	IfStmt* this = buf;
	free_ast(this->cond);
	free_ast(this->then);
	free_ast(this->opt_else);
	free(this);
}

static void WhileStmt_free(void* buf) {
	WhileStmt* this = buf;
	free_ast(this->cond);
	free_ast(this->body);
	free(this);
}

static void Exp_free(void* buf) {
	Exp* this = buf;
	free(this->name);
	free_ast(this->lhs);
	free_ast(this->rhs);
	free_ast_list(this->args);
	free(this);
}

Program* Program_init(void* buf, int lineno, DEQUE_T(BaseDef*) ext_defs) {
	Program* this = buf;
	BaseAST_init(this, lineno, Program_free);
	this->ext_defs = ext_defs;
	return this;
}

SpecDef* SpecDef_init(void* buf, int lineno, BaseSpecifier* spec) {
	SpecDef* this = buf;
	BaseAST_init(this, lineno, SpecDef_free);
	this->super.spec = spec;
	this->super.ops = &sem_spec_def_ops;
	return this;
}

VarInitDefs* VarInitDefs_init(void* buf, int lineno, BaseSpecifier* spec,
							  DEQUE_T(UntypedVarDef*) var_decs) {
	VarInitDefs* this = buf;
	BaseAST_init(this, lineno, VarInitDefs_free);
	this->super.spec = spec;
	this->super.ops = &sem_var_init_defs_ops;
	this->var_decs = var_decs;
	return this;
}

UntypedVarDef* UntypedVarDef_init(void* buf, int lineno, char* name,
								  DEQUE_T(int) dims, Exp* opt_init) {
	UntypedVarDef* this = buf;
	BaseAST_init(this, lineno, UntypedVarDef_free);
	this->name = name;
	this->dims = dims;
	this->opt_init = opt_init;
	return this;
}

FunDec* FunDec_init(void* buf, int lineno, BaseSpecifier* spec, char* name,
					DEQUE_T(ParamDec*) params, CompSt* opt_body) {
	FunDec* this = buf;
	BaseAST_init(this, lineno, FunDec_free);
	this->super.spec = spec;
	this->super.ops = &sem_fun_dec_ops;
	this->name = name;
	this->params = params;
	this->opt_body = opt_body;
	return this;
}

TypeSpecifier* TypeSpecifier_init(void* buf, int lineno, char* type) {
	TypeSpecifier* this = buf;
	BaseAST_init(this, lineno, TypeSpecifier_free);
	this->super.ops = &sem_type_specifier_ops;
	this->type = type;
	return this;
}

StructDeclSpecifier* StructDeclSpecifier_init(void* buf, int lineno, char* tag) {
	StructDeclSpecifier* this = buf;
	BaseAST_init(this, lineno, StructDeclSpecifier_free);
	this->super.ops = &sem_struct_decl_specifier_ops;
	this->tag = tag;
	return this;
}

StructDefSpecifier* StructDefSpecifier_init(void* buf, int lineno, char* opt_tag,
											DEQUE_T(BaseDef*) defs) {
	StructDefSpecifier* this = buf;
	BaseAST_init(this, lineno, StructDefSpecifier_free);
	this->super.ops = &sem_struct_def_specifier_ops;
	this->opt_tag = opt_tag;
	this->defs = defs;
	return this;
}

ParamDec* ParamDec_init(void* buf, int lineno, BaseSpecifier* spec,
						UntypedVarDef* var_dec) {
	ParamDec* this = buf;
	BaseAST_init(this, lineno, ParamDec_free);
	this->spec = spec;
	this->var_dec = var_dec;
	return this;
}

ExpStmt* ExpStmt_init(void* buf, int lineno, Exp* exp) {
	ExpStmt* this = buf;
	BaseAST_init(this, lineno, ExpStmt_free);
	this->super.ops = &sem_exp_stmt_ops;
	this->exp = exp;
	return this;
}

ReturnStmt* ReturnStmt_init(void* buf, int lineno, Exp* exp) {
	ReturnStmt* this = buf;
	BaseAST_init(this, lineno, ReturnStmt_free);
	this->super.ops = &sem_return_stmt_ops;
	this->exp = exp;
	return this;
}

CompSt* CompSt_init(void* buf, int lineno, DEQUE_T(BaseDef*) defs,
					DEQUE_T(BaseStmt*) stmts) {
	CompSt* this = buf;
	BaseAST_init(this, lineno, CompSt_free);
	this->super.ops = &sem_comp_st_ops;
	this->defs = defs;
	this->stmts = stmts;
	return this;
}

IfStmt* IfStmt_init(void* buf, int lineno, Exp* cond, BaseStmt* then,
					BaseStmt* opt_else) {
	IfStmt* this = buf;
	BaseAST_init(this, lineno, IfStmt_free);
	this->super.ops = &sem_if_stmt_ops;
	this->cond = cond;
	this->then = then;
	this->opt_else = opt_else;
	return this;
}

WhileStmt* WhileStmt_init(void* buf, int lineno, Exp* cond, BaseStmt* body) {
	WhileStmt* this = buf;
	BaseAST_init(this, lineno, WhileStmt_free);
	this->super.ops = &sem_while_stmt_ops;
	this->cond = cond;
	this->body = body;
	return this;
}

Exp* Exp_init(void* buf, int lineno, ExpKind kind) {
	Exp* this = buf;
	BaseAST_init(this, lineno, Exp_free);
	this->kind = kind;
	this->ops = sem_exp_ops_for_kind(kind);
	return this;
}
