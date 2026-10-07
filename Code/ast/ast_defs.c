#include "ast_defs.h"

BaseAST* BaseAST_init(void* buf) {
	return (BaseAST*)buf;
}

#define CREATE_DEFAULT_INIT(parent, name, ...) \
	name* name##_init(void* buf) {             \
		parent##_init(buf);                    \
		return (name*)buf;                     \
	}

APPLY(CREATE_DEFAULT_INIT, ASTs)
