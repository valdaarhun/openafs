/*
 * Copyright 2021, Sine Nomine Associates
 * All Rights Reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR `AS IS'' AND ANY EXPRESS OR
 * IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 * OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 * IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
 * NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 * THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

/*
 * Split strings using a shell-like syntax.
 */

#include <afsconfig.h>
#include <afs/param.h>

#include <roken.h>

#include <opr/queue.h>
#include <ctype.h>
#include <assert.h>

#include "cmd.h"

/* tokenize() token buffer. */
#define TOKEN_BUFFER_INITIAL_SIZE 256
struct token_buffer {
    char *buffer;        /**< Address of the allocated buffer. */
    size_t buffer_size;  /**< Current allocated buffer size. */
    size_t token_len;    /**< Current token length. */
    char *token_end;     /**< Address of the token nul terminator. */
};

/* cmd_Split() context. */
struct token_list {
    struct opr_queue q;
    int count;
};

/* cmd_Split() token elements. */
struct token_node {
    struct opr_queue q;
    char *token;
};

/**
 * Initialize an expandable token buffer.
 *
 * @param tb token buffer
 */
static int
init_token_buffer(struct token_buffer *tb)
{
    tb->buffer = calloc(TOKEN_BUFFER_INITIAL_SIZE, 1);
    if (tb->buffer == NULL)
	return ENOMEM;
    tb->buffer_size = TOKEN_BUFFER_INITIAL_SIZE;
    tb->token_len = 0;
    tb->token_end = tb->buffer;
    return 0;
}

/**
 * Clear the token buffer in preparation for the next token.
 *
 * @param tb token buffer
 */
static void
clear_token_buffer(struct token_buffer *tb)
{
    memset(tb->buffer, 0, tb->buffer_size);
    tb->token_end = tb->buffer;
    tb->token_len = 0;
}

/**
 * Free the token buffer.
 *
 * @param tb token buffer
 */
static void
free_token_buffer(struct token_buffer *tb)
{
    free(tb->buffer);
    tb->buffer = NULL;
    tb->buffer_size = 0;
    tb->token_end = NULL;
    tb->token_len = 0;
}

/**
 * Add a character to the token buffer.
 *
 * Realloc the token buffer if needed.
 *
 * @param tb token buffer
 * @param ch character to be added
 * @return 0 on success
 *   @retval ENOMEM  out of memory
 */
static int
accept_char(struct token_buffer *tb, char ch)
{
    assert(tb->token_len >= 0);
    if (tb->token_len + 1 == tb->buffer_size) {
	size_t space;
	char *buffer;

	tb->buffer_size *= 2;
	assert(tb->buffer_size > 0);
	buffer = realloc(tb->buffer, tb->buffer_size);
	if (buffer == NULL) {
	    free(tb->buffer);
	    tb->buffer = NULL;
	    return ENOMEM;
	}
	tb->buffer = buffer;

	/* Recalculate our end of token in the resized buffer. */
	tb->token_end = tb->buffer + tb->token_len;

	/* Clear from end of token to end of the resized buffer. */
	space = tb->buffer_size - tb->token_len - 1;
	assert(space > 0);
	memset(tb->token_end + 1, 0, space);
    }
    *tb->token_end++ = ch;
    tb->token_len++;
    return 0;
}

/**
 * Lexical analyzer for shell-like syntax.
 *
 * Convert a string into a series of tokens, splitting on whitespace, honoring
 * shell-like quoting, and backslash escape characters on unix-like systems.
 *
 * The emit callback function is called each time a token is found by the
 * parser. The token string is allocated by cmd_Tokenize() and passed to the
 * callback function. The caller is responsible for freeing tokens.
 *
 * @param[in] text  input string
 * @param[out] emit  called on each token found by the parser
 *
 * @return 0 on success
 *   @retval ENOMEM  out of memory
 *   @retval CMD_NOCLOSINGQUOTE  missing closing quote in text
 *   @retval CMD_NOESCAPEDCHAR  bad escape sequence in text
 */
int
cmd_Tokenize(const char *text, int (*emit)(char *token, void *rock), void *rock)
{
    int code;
    char *token = NULL;
    struct token_buffer tb;
    const char *tp;
    enum token_state {
	STATE_DELIM,  /* Reading whitespace between tokens. */
	STATE_BARE,   /* Reading unquoted token characters. */
	STATE_SQUOTE, /* Reading single quoted token characters. */
	STATE_DQUOTE, /* Reading double quoted token characters. */
	STATE_ESC,    /* Character following backslash. */
	STATE_QESC,   /* Character following backslash in double quoted. */
	STATE_END,    /* Tokenization successfully completed. */
	STATE_ERROR   /* Error encountered. */
    };
    enum token_state state = STATE_DELIM;

    code = init_token_buffer(&tb);
    if (code != 0)
	return code;

    for (tp = text; state != STATE_END && state != STATE_ERROR; tp++) {
	switch (state) {
	case STATE_DELIM:
	    switch (*tp) {
	    case '\0':
		state = STATE_END;
		break;
	    case '\'':
		state = STATE_SQUOTE;
		break;
	    case '"':
		state = STATE_DQUOTE;
		break;
	    case '\\':
		state = STATE_ESC;
		break;
	    case ' ':
	    case '\t':
	    case '\r':
	    case '\n':
		break; /* Skip whitespace. */
	    default:
		code = accept_char(&tb, *tp);
		if (code != 0)
		    goto fail;
		state = STATE_BARE;
		break;
	    }
	    break;
	case STATE_BARE:
	    switch (*tp) {
	    case '\0':
		if (emit != NULL) {
		    token = strdup(tb.buffer);
		    if (token == NULL) {
			code = ENOMEM;
			goto fail;
		    }
		    code = emit(token, rock);
		    if (code != 0) {
			free(token);
			token = NULL;
			goto fail;
		    }
		    token = NULL;
		}
		state = STATE_END;
		break;
	    case ' ':
	    case '\t':
	    case '\r':
	    case '\n':
		if (emit != NULL) {
		    token = strdup(tb.buffer);
		    if (token == NULL) {
			code = ENOMEM;
			goto fail;
		    }
		    code = emit(token, rock);
		    if (code != 0) {
			free(token);
			token = NULL;
			goto fail;
		    }
		    token = NULL;
		}
		clear_token_buffer(&tb);
		state = STATE_DELIM;
		break;
	    case '\'':
		state = STATE_SQUOTE;
		break;
	    case '"':
		state = STATE_DQUOTE;
		break;
	    case '\\':
		state = STATE_ESC;
		break;
	    default:
		code = accept_char(&tb, *tp);
		if (code != 0)
		    goto fail;
		break;
	    }
	    break;
	case STATE_SQUOTE:
	    switch(*tp) {
	    case '\0':
		code = CMD_NOCLOSINGQUOTE;
		state = STATE_ERROR;
		break;
	    case '\'':
		state = STATE_BARE;
		break;
	    default:
		code = accept_char(&tb, *tp);
		if (code != 0)
		    goto fail;
		break;
	    }
	    break;
	case STATE_DQUOTE:
	    switch(*tp) {
	    case '\0':
		code = CMD_NOCLOSINGQUOTE;
		state = STATE_ERROR;
		break;
	    case '"':
		state = STATE_BARE;
		break;
	    case '\\':
		state = STATE_QESC;
		break;
	    default:
		code = accept_char(&tb, *tp);
		if (code != 0)
		    goto fail;
		break;
	    }
	    break;
	case STATE_ESC:
	    switch(*tp) {
	    case '\0':
		code = CMD_NOESCAPEDCHAR;
		state = STATE_ERROR;
		break;
	    default:
		code = accept_char(&tb, *tp);
		if (code != 0)
		    goto fail;
		state = STATE_BARE;
		break;
	    }
	    break;
	case STATE_QESC:
	    switch(*tp) {
	    case '\0':
		code = CMD_NOESCAPEDCHAR;
		state = STATE_ERROR;
		break;
	    default:
		code = accept_char(&tb, *tp);
		if (code != 0)
		    goto fail;
		state = STATE_DQUOTE;
		break;
	    }
	    break;
	default:
	    code = CMD_INTERNALERROR;
	    state = STATE_ERROR;
	    break;
	}
    }

  fail:
    free_token_buffer(&tb);
    return code;
}

/**
 * Append a token to a list.
 *
 * @param token  token string
 * @param rock  callback context
 * @return 0 on success
 *   @retval ENOMEM  out of memory
 */
static int
append_token(char *token, void *rock)
{
    struct token_list *tokens = rock;
    struct token_node *node;

    node = calloc(1, sizeof(*node));
    if (node == NULL)
	return ENOMEM;
    node->token = token;
    tokens->count++;
    opr_queue_Append(&tokens->q, &node->q);
    return 0;
}

/**
 * Split a string using a shell-like syntax.
 *
 * The caller must free the argument strings with cmd_FreeSplit().
 *
 * @param[in] text     string to be split
 * @param[out] pargc   number of arguments
 * @param[out] pargv   argument string vector
 *
 * @return 0 on success
 *   @retval ENOMEM  out of memory
 *   @retval CMD_NOCLOSINGQUOTE  missing closing quote in text
 *   @retval CMD_NOESCAPEDCHAR  bad escape sequence in text
 */
int
cmd_Split(const char *text, int *pargc, char ***pargv)
{
    int code;
    struct token_list tokens;
    struct opr_queue *cursor, *store;
    int tc;
    char **tv;

    tokens.count = 0;
    opr_queue_Init(&tokens.q);
    code = cmd_Tokenize(text, append_token, &tokens);
    if (code != 0)
	goto fail;

    /* Convert the list to an argv string vector. */
    tc = 0;
    tv = calloc(tokens.count + 1, sizeof(*tv));
    if (tv == NULL) {
	code = ENOMEM;
	goto fail;
    }
    for (opr_queue_ScanSafe(&tokens.q, cursor, store)) {
	struct token_node *n = opr_queue_Entry(cursor, struct token_node, q);
	tv[tc++] = n->token;
	free(n);
    }

    *pargc = tokens.count;
    *pargv = tv;
    return 0;

  fail:
    for (opr_queue_ScanSafe(&tokens.q, cursor, store)) {
	struct token_node *n = opr_queue_Entry(cursor, struct token_node, q);
	free(n->token);
	free(n);
    }
    *pargc = 0;
    *pargv = NULL;
    return code;
}

/**
 * Free the string vector returned from cmd_Split()
 *
 * @param pargv  pointer a the string vector allocated by cmd_Split()
 */
void
cmd_FreeSplit(char ***pargv)
{
    char **arg;

    if (*pargv != NULL) {
	for (arg = *pargv; *arg != NULL; arg++) {
	    free(*arg);
	    *arg = NULL;
	}
	free(*pargv);
	*pargv = NULL;
    }
}
