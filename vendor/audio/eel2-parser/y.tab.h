/* The tokens nseel-eval.c's lexer returns and the location it fills in, for nseel-parse.c; ns-eel-int.h
   includes it by this name. */
#ifndef SG_NSEEL_TOKENS_H
#define SG_NSEEL_TOKENS_H

enum {
    VALUE = 258,
    IDENTIFIER,
    TOKEN_SHL,
    TOKEN_SHR,
    TOKEN_LTE,
    TOKEN_GTE,
    TOKEN_EQ,
    TOKEN_EQ_EXACT,
    TOKEN_NE,
    TOKEN_NE_EXACT,
    TOKEN_LOGICAL_AND,
    TOKEN_LOGICAL_OR,
    TOKEN_ADD_OP,
    TOKEN_SUB_OP,
    TOKEN_MOD_OP,
    TOKEN_OR_OP,
    TOKEN_AND_OP,
    TOKEN_XOR_OP,
    TOKEN_DIV_OP,
    TOKEN_MUL_OP,
    TOKEN_POW_OP,
    STRING_LITERAL,
    STRING_IDENTIFIER,
};

typedef struct YYLTYPE {
    int first_line;
    int first_column;
    int last_line;
    int last_column;
} YYLTYPE;

#endif
