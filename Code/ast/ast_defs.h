#pragma once
#include "../utils/list.h"
#include "../utils/macros.h"

#define MAX_ID_LEN 32

typedef struct {
	// virtual functions here
	int delete_me_later;   // make compiler happy
} BaseAST;

#define DEF_AST(parent, name, ...) \
	struct name {                  \
		parent super;              \
		__VA_ARGS__                \
	};                             \
	name* name##_init(void*);

#define DECL_AST(parent, name, ...) \
	typedef struct name name;

#define ASTs(_)                                                   \
	_(BaseAST, PlainAST, char type[MAX_ID_LEN], data[MAX_ID_LEN]; \
	  int lineno;                                                 \
	  PlainAST * child, *sib;)                                    \
	_(BaseAST, Program, ExtDefList* decls;)                       \
	_(BaseAST, ExtDefList, List* list;)

APPLY(DECL_AST, ASTs)
APPLY(DEF_AST, ASTs)

// Args CompSt Dec Def Exp ExtDef FunDec OptTag ParamDec Specifier Stmt StructSpecifier Tag VarDec
// DecList DefList ExtDecList ExtDefList StmtList VarList
