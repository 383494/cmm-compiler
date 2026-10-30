#include "ast/ast_defs.h"
#include "utils/macros.h"
#include <stdio.h>
#include <stdlib.h>

#define EXIT_FAIL MUXDEF(CMM_EXIT_FAILURE, EXIT_FAILURE, EXIT_SUCCESS)
#define ERR_STREAM MUXDEF(CMM_OUTPUT_STDERR, stderr, stdout)

extern FILE *yyin;
extern unsigned int cmm_error_count;
int yylex_destroy(void);
int yyparse(BaseAST **);

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
	BaseAST *ast = NULL;
	int parse_status = yyparse(&ast);
	fclose(yyin);
	yylex_destroy();

	free_ast(ast);
	if(parse_status != 0 || cmm_error_count != 0) {
		return EXIT_FAIL;
	}

	return EXIT_SUCCESS;
}
