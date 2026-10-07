#include "ast/ast_defs.h"
#include "utils/macros.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define EXIT_FAIL MUXDEF(CMM_EXIT_FAILURE, EXIT_FAILURE, EXIT_SUCCESS)
#define ERR_STREAM MUXDEF(CMM_OUTPUT_STDERR, stderr, stdout)

extern FILE *yyin;
extern unsigned int cmm_error_count;
int yylex_destroy(void);
int yyparse(BaseAST **);

static void free_ast(PlainAST *node) {
	while(node != NULL) {
		PlainAST *next = node->sib;
		free_ast(node->child);
		free(node);
		node = next;
	}
}

static void print_ast(PlainAST *node, int indent) {
	if(node == NULL) return;
	for(int i = 0; i < indent; i++) {
		printf(" ");
	}
	printf("%s", node->type);
	if(node->child != NULL) printf(" (%d)", node->lineno);
	else if(strcmp(node->type, "ID") == 0) printf(": %s", node->data);
	else if(strcmp(node->type, "TYPE") == 0) printf(": %s", node->data);
	else if(strcmp(node->type, "INT") == 0) printf(": %s", node->data);
	else if(strcmp(node->type, "FLOAT") == 0) printf(": %s", node->data);

	printf("\n");
	print_ast(node->child, indent + 2);
	print_ast(node->sib, indent);
}

int main(int argc, char **argv) {
	if(argc != 2) {
		fprintf(ERR_STREAM, "Usage: %s /path/to/source\n", argv[0]);
		return EXIT_FAIL;
	}

	yyin = fopen(argv[1], "r");
	if(yyin == NULL) {
		perror(argv[1]);
		return EXIT_FAIL;
	}

	cmm_error_count = 0;
	BaseAST *base_ast = NULL;
	int parse_status = yyparse(&base_ast);
	fclose(yyin);
	yylex_destroy();

	PlainAST *ast = (PlainAST *)base_ast;
	if(parse_status != 0 || cmm_error_count != 0) {
		free_ast(ast);
		return EXIT_FAIL;
	}

	print_ast(ast, 0);
	return EXIT_SUCCESS;
}
