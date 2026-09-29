/* EEL2's parser: eel2.y's grammar as recursive descent over nseel-eval.c's tokens, building opcodes through
   nseel-compiler.c. Also rand() and __clear_cache, which the vendored EEL2 files call and do not define.
   spoti.pw's own code (../README.md). */
#include <math.h>
#include <stdint.h>
#include "ns-eel-int.h"

int nseellex(opcodeRec **output, YYLTYPE *location, compileContext *context);
void nseelerror(YYLTYPE *position, compileContext *context, const char *text);

/* Nesting deep enough to run a dispatch queue's thread out of stack is refused. */
enum { kMaxDepth = 256 };

typedef struct {
    compileContext *context;
    int token;
    opcodeRec *value;
    YYLTYPE location;
    int depth;
    int failed;
} Parser;

typedef struct {
    int token, function;
} Operator;

static void advance(Parser *p) {
    p->value = NULL;
    p->location.first_column = 0;
    p->token = nseellex(&p->value, &p->location, p->context);
}

/* The first error is the one reported, as Bison's parser stops at it. */
static opcodeRec *fail(Parser *p, YYLTYPE *at) {
    if (!p->failed) {
        p->failed = 1;
        nseelerror(at, p->context, "");
    }
    return NULL;
}

static int enter(Parser *p) {
    if (++p->depth <= kMaxDepth) return 1;
    fail(p, &p->location);
    return 0;
}

static int startsExpression(int token) {
    switch (token) {
    case VALUE: case IDENTIFIER: case STRING_LITERAL: case STRING_IDENTIFIER: case '(': case '+': case '-': case '!':
        return 1;
    }
    return 0;
}

static opcodeRec *expression(Parser *p);
static opcodeRec *ifElse(Parser *p);

/* more_params: expression | expression ',' more_params */
static opcodeRec *moreParameters(Parser *p) {
    if (!enter(p)) return NULL;
    opcodeRec *first = expression(p), *result = first;
    if (!p->failed && p->token == ',') {
        advance(p);
        opcodeRec *rest = moreParameters(p);
        result = p->failed ? NULL : nseel_createMoreParametersOpcode(p->context, first, rest);
    }
    p->depth--;
    return p->failed ? NULL : result;
}

/* The calls of assignable_value, from the '(' after the name: f(), f(a), f(a)(b), f(a, b), f(a, b, ...). */
static opcodeRec *call(Parser *p, opcodeRec *name, YYLTYPE at) {
    if (!enter(p)) return NULL;
    advance(p);
    int err = 0;
    opcodeRec *result = NULL;
    if (p->token == ')') {
        YYLTYPE close = p->location;
        advance(p);
        result = nseel_setCompiledFunctionCallParameters(p->context, name, nseel_createCompiledValue(p->context, 0.0), 0, 0, 0, &err);
        if (!result) fail(p, err == 0 ? &at : &close);
        p->depth--;
        return result;
    }
    opcodeRec *first = expression(p);
    if (p->failed) return NULL;
    if (p->token == ')') {
        YYLTYPE close = p->location;
        advance(p);
        if (p->token == '(') {
            YYLTYPE open = p->location;
            advance(p);
            opcodeRec *post = expression(p);
            if (p->failed) return NULL;
            if (p->token != ')') return fail(p, &p->location);
            advance(p);
            result = nseel_setCompiledFunctionCallParameters(p->context, name, first, 0, 0, post, &err);
            if (!result) fail(p, err == -1 ? &open : err == 0 ? &at : &close);
        } else {
            result = nseel_setCompiledFunctionCallParameters(p->context, name, first, 0, 0, 0, &err);
            if (!result) fail(p, err == 0 ? &at : &close);
        }
    } else if (p->token == ',') {
        YYLTYPE comma = p->location;
        advance(p);
        opcodeRec *second = expression(p);
        if (p->failed) return NULL;
        if (p->token == ')') {
            YYLTYPE close = p->location;
            advance(p);
            result = nseel_setCompiledFunctionCallParameters(p->context, name, first, second, 0, 0, &err);
            if (!result) fail(p, err == 0 ? &at : err == 2 ? &close : &comma);
        } else if (p->token == ',') {
            YYLTYPE secondComma = p->location;
            advance(p);
            opcodeRec *rest = moreParameters(p);
            if (p->failed) return NULL;
            if (p->token != ')') return fail(p, &p->location);
            YYLTYPE close = p->location;
            advance(p);
            result = nseel_setCompiledFunctionCallParameters(p->context, name, first, second, rest, 0, &err);
            if (!result) fail(p, err == 0 ? &at : err == 2 ? &close : err == 4 ? &comma : &secondComma);
        } else {
            return fail(p, &p->location);
        }
    } else {
        return fail(p, &p->location);
    }
    p->depth--;
    return p->failed ? NULL : result;
}

/* rvalue and assignable_value up to their subscripts: a number, strings, a name, a call, a parenthesis. */
static opcodeRec *primary(Parser *p, int *assignable) {
    *assignable = 0;
    switch (p->token) {
    case VALUE: {
        opcodeRec *value = p->value;
        advance(p);
        return value;
    }
    case STRING_LITERAL: {
        struct eelStringSegmentRec *first = (struct eelStringSegmentRec *)p->value, *last = first;
        advance(p);
        while (p->token == STRING_LITERAL) {
            last->_next = (struct eelStringSegmentRec *)p->value;
            last = last->_next;
            advance(p);
        }
        return nseel_eelMakeOpcodeFromStringSegments(p->context, first);
    }
    case IDENTIFIER: {
        opcodeRec *name = p->value;
        YYLTYPE at = p->location;
        advance(p);
        *assignable = 1;
        if (p->token == '(') return call(p, name, at);
        opcodeRec *symbol = nseel_resolve_named_symbol(p->context, name, -1, NULL);
        return symbol ? symbol : fail(p, &at);
    }
    case '(': {
        if (!enter(p)) return NULL;
        advance(p);
        opcodeRec *inner = expression(p);
        if (p->failed) return NULL;
        if (p->token != ')') return fail(p, &p->location);
        advance(p);
        p->depth--;
        *assignable = 1;
        return inner;
    }
    }
    return fail(p, &p->location);
}

/* rvalue '[' ']' and rvalue '[' expression ']', which are assignable. */
static opcodeRec *subscripts(Parser *p, opcodeRec *value, int *assignable) {
    while (!p->failed && p->token == '[') {
        advance(p);
        opcodeRec *index = NULL;
        if (p->token != ']') {
            index = expression(p);
            if (p->failed) return NULL;
            if (p->token != ']') return fail(p, &p->location);
        }
        advance(p);
        value = nseel_createMemoryAccess(p->context, value, index);
        *assignable = 1;
    }
    return p->failed ? NULL : value;
}

static int assignFunction(int token) {
    switch (token) {
    case '=': return FN_ASSIGN;
    case TOKEN_ADD_OP: return FN_ADD_OP;
    case TOKEN_SUB_OP: return FN_SUB_OP;
    case TOKEN_MOD_OP: return FN_MOD_OP;
    case TOKEN_OR_OP: return FN_OR_OP;
    case TOKEN_AND_OP: return FN_AND_OP;
    case TOKEN_XOR_OP: return FN_XOR_OP;
    case TOKEN_DIV_OP: return FN_DIV_OP;
    case TOKEN_MUL_OP: return FN_MUL_OP;
    case TOKEN_POW_OP: return FN_POW_OP;
    }
    return -1;
}

/* assignment: rvalue, an assignable value and an operator, or a string's strcpy and strcat. */
static opcodeRec *assignment(Parser *p) {
    int assignable = 0;
    opcodeRec *target;
    if (p->token == STRING_IDENTIFIER) {
        target = p->value;
        advance(p);
        if (p->token == '=' || p->token == TOKEN_ADD_OP) {
            const char *function = p->token == '=' ? "strcpy" : "strcat";
            advance(p);
            opcodeRec *source = ifElse(p);
            return p->failed ? NULL : nseel_createFunctionByName(p->context, function, 2, target, source, NULL);
        }
    } else {
        target = primary(p, &assignable);
        if (p->failed) return NULL;
    }
    target = subscripts(p, target, &assignable);
    if (p->failed) return NULL;
    int function = assignFunction(p->token);
    if (!assignable || function < 0) return target;
    advance(p);
    opcodeRec *source = ifElse(p);
    return p->failed ? NULL : nseel_createSimpleCompiledFunction(p->context, function, 2, target, source);
}

static opcodeRec *unary(Parser *p) {
    int op = p->token;
    if (op != '+' && op != '-' && op != '!') return assignment(p);
    if (!enter(p)) return NULL;
    advance(p);
    opcodeRec *operand = unary(p);
    p->depth--;
    if (p->failed) return NULL;
    if (op == '+') return operand;
    return nseel_createSimpleCompiledFunction(p->context, op == '-' ? FN_UMINUS : FN_NOT, 1, operand, 0);
}

/* A left-associative level of binary operators over the next level down. */
static opcodeRec *binary(Parser *p, opcodeRec *(*operand)(Parser *), const Operator *operators, int count) {
    opcodeRec *left = operand(p);
    while (!p->failed) {
        int function = -1;
        for (int i = 0; i < count; i++) {
            if (operators[i].token == p->token) function = operators[i].function;
        }
        if (function < 0) break;
        advance(p);
        opcodeRec *right = operand(p);
        if (p->failed) return NULL;
        left = nseel_createSimpleCompiledFunction(p->context, function, 2, left, right);
    }
    return p->failed ? NULL : left;
}

#define LEVEL(name, next, ...) \
    static opcodeRec *name(Parser *p) { \
        static const Operator operators[] = {__VA_ARGS__}; \
        return binary(p, next, operators, (int)(sizeof operators / sizeof *operators)); \
    }

LEVEL(powers, unary, {'^', FN_POW})
LEVEL(modulos, powers, {'%', FN_MOD}, {TOKEN_SHL, FN_SHL}, {TOKEN_SHR, FN_SHR})
LEVEL(divisions, modulos, {'/', FN_DIVIDE})
LEVEL(products, divisions, {'*', FN_MULTIPLY})
LEVEL(differences, products, {'-', FN_SUB})
LEVEL(sums, differences, {'+', FN_ADD})
LEVEL(bitwise, sums, {'&', FN_AND}, {'|', FN_OR}, {'~', FN_XOR})
LEVEL(comparisons, bitwise, {'<', FN_LT}, {'>', FN_GT}, {TOKEN_LTE, FN_LTE}, {TOKEN_GTE, FN_GTE}, {TOKEN_EQ, FN_EQ},
      {TOKEN_EQ_EXACT, FN_EQ_EXACT}, {TOKEN_NE, FN_NE}, {TOKEN_NE_EXACT, FN_NE_EXACT})
LEVEL(logical, comparisons, {TOKEN_LOGICAL_AND, FN_LOGICAL_AND}, {TOKEN_LOGICAL_OR, FN_LOGICAL_OR})

/* if_else_expr: a ? b : c, a ? : c and a ? b, a ':' always going to the nearest '?'. */
static opcodeRec *ifElse(Parser *p) {
    opcodeRec *condition = logical(p);
    if (p->failed || p->token != '?') return condition;
    if (!enter(p)) return NULL;
    advance(p);
    opcodeRec *then = NULL, *otherwise = NULL;
    if (p->token == ':') {
        advance(p);
        otherwise = ifElse(p);
    } else {
        then = ifElse(p);
        if (!p->failed && p->token == ':') {
            advance(p);
            otherwise = ifElse(p);
        }
    }
    p->depth--;
    return p->failed ? NULL : nseel_createIfElse(p->context, condition, then, otherwise);
}

/* expression: statements joined by ';', which may also end one. */
static opcodeRec *expression(Parser *p) {
    opcodeRec *result = ifElse(p);
    while (!p->failed && p->token == ';') {
        advance(p);
        if (!startsExpression(p->token)) continue;
        opcodeRec *next = ifElse(p);
        if (p->failed) return NULL;
        result = nseel_createSimpleCompiledFunction(p->context, FN_JOIN_STATEMENTS, 2, result, next);
    }
    return p->failed ? NULL : result;
}

int nseelparse(compileContext *context) {
    Parser p = {.context = context};
    advance(&p);
    opcodeRec *result = expression(&p);
    if (!p.failed && p.token != 0) fail(&p, &p.location);
    if (p.failed) return 1;
    context->result = result;
    return 0;
}

/* rand(x): uniform in [0, x), x at least 1. xorshift64*, its state the process's like upstream's. */
EEL_F NSEEL_CGEN_CALL nseel_int_rand(EEL_F f) {
    static uint64_t state = 0x9e3779b97f4a7c15ull;
    state ^= state >> 12;
    state ^= state << 25;
    state ^= state >> 27;
    EEL_F x = floor(f);
    if (x < 1) x = 1;
    return (EEL_F)((state * 0x2545f4914f6cdd1dull) >> 11) * (1.0 / 9007199254740992.0) * x;
}

/* The compiler flushes the instruction cache over what it wrote, as it would over JIT code; the portable
   target's bytecode is only ever read as data, and the iOS link has no compiler runtime to provide it. */
void __clear_cache(void *start, void *end) {
}
