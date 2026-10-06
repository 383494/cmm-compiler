#include "ast_defs.h"

BaseAST* BaseAST_init(void* buf) {
	return (BaseAST*)buf;
}

#define CREATE_DEFUALT_INIT(parent, name) \
	name* name##_init(void* buf) {        \
		return (name*)buf;                \
	}
