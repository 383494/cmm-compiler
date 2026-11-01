#pragma once

#include "ast_defs.h"

// AST should not have syntax errors
void semantic_check(Program *program);
