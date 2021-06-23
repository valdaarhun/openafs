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
 * cmd_Tokenize() and cmd_Split() tests.
 */

#include <afsconfig.h>
#include <afs/param.h>
#include <roken.h>
#include <afs/cmd.h>
#include <tests/tap/basic.h>
#include <ctype.h>


struct test_case {
    char *line;
    char *argv[16];
};

static struct test_case valid_lines[] = {
    /* Empty and blank strings. */
    {
	.line = "",
	.argv = {NULL}
    },
    {
	.line = "    ",
	.argv = {NULL}
    },
    {
	.line = "\t\n",
	.argv = {NULL}
    },
    /* Tokens separated with whitespace and no quotes. */
    {
	.line = "hello world",
	.argv = {"hello", "world", NULL}
    },
    {
	.line = "hello, world!",
	.argv = {"hello,", "world!", NULL}
    },
    {
	.line = "testing: one two   three",
	.argv = {"testing:", "one", "two", "three", NULL}
    },
    {
	.line = "tabs\tand newlines\nare whitespace",
	.argv = {"tabs", "and", "newlines", "are", "whitespace", NULL}
    },
    /* Simple quotes. */
    {
	.line = "'single quotes with spaces' and 4 more args",
	.argv = {"single quotes with spaces", "and", "4", "more", "args", NULL}
    },
    {
	.line = "\"double quotes with spaces\" and 4 more args",
	.argv = {"double quotes with spaces", "and", "4", "more", "args", NULL}
    },
    {
	.line = "unquoted args 'followed by quoted'",
	.argv = {"unquoted", "args", "followed by quoted", NULL}
    },
    {
	.line = "unquoted args \"followed by double quoted\"",
	.argv = {"unquoted", "args", "followed by double quoted", NULL}
    },
    {
	.line = "\"Not all those who wander are lost\" - Tolkien",
	.argv = {"Not all those who wander are lost", "-", "Tolkien", NULL}
    },
    /* Escaped spaces. */
    {
	.line = "this\\ is\\ one\\ arg",
	.argv = {"this is one arg", NULL}
    },
    {
	.line = "this is\\ two\\ args",
	.argv = {"this", "is two args", NULL}
    },
    /* Escaped single quotes. */
    {
	.line = "dont\\'t worry, be happy",
	.argv = {"dont't", "worry,", "be", "happy", NULL}
    },
    {
	.line = "\\'not quoted\\'",
	.argv = {"'not", "quoted'", NULL}
    },
    /* Embedded quote characters. */
    {
	.line = "\"don't worry,\" be happy",
	.argv = {"don't worry,", "be", "happy", NULL}
    },
    {
	.line = "don\"'\"t' 'worry, be happy",
	.argv = {"don't worry,", "be", "happy", NULL}
    },
    /* Quotes characters are modal. */
    {
	.line = "this is three' 'args",
	.argv = {"this", "is", "three args", NULL}
    },
    {
	.line = "this is t'hree arg's",
	.argv = {"this", "is", "three args", NULL}
    },
    {
	.line = "this is three\" \"args",
	.argv = {"this", "is", "three args", NULL}
    },
    {
	.line = "this is t\"hree arg\"s",
	.argv = {"this", "is", "three args", NULL}
    },
    /* Nested quotes. */
    {
	.line = "\"double with 'single' quotes\"",
	.argv = {"double with 'single' quotes", NULL}
    },
    {
	.line = "\"double with escaped \\\"double\\\" quotes\"",
	.argv = {"double with escaped \"double\" quotes", NULL}
    },
    {
	.line = "\"double with 'single' and escaped \\\"double\\\" quotes\"",
	.argv = {"double with 'single' and escaped \"double\" quotes", NULL}
    },
    {
	.line = "'single with escaped \\\"double\\\" quotes'",
	.argv = {"single with escaped \\\"double\\\" quotes", NULL}
    },
    {
	.line = "'single with quote-escaped \"'\"single\"'\" quotes'",
	.argv = {"single with quote-escaped \"single\" quotes", NULL}
    },
    {
	.line = "'\"Not all those who wander are lost\" - Tolkien'",
	.argv = {"\"Not all those who wander are lost\" - Tolkien", NULL}
    },
    {
	.line = "\"\\\"Not all those who wander are lost\\\" - Tolkien\"",
	.argv = {"\"Not all those who wander are lost\" - Tolkien", NULL}
    },
    {0}
};

static struct test_case no_closing_quotes[] = {
    {.line = "'"},
    {.line = "\""},
    {.line = "'missing closing single quote"},
    {.line = "missing closing 'single quote"},
    {.line = "missing closing single quote'"},
    {.line = "\"missing closing double quote"},
    {.line = "'\"\"missing closing single quote"},
    {.line = "'backslashes are \\'literals\\' in single quotes'"},
    {0}
};

static struct test_case no_escaped_character[] = {
    {.line = "\\"},
    {.line = "a character must follow a backslash\\"},
    {0}
};

static int
count_args(char **argv)
{
    int i;

    for (i = 0; argv[i] != NULL; i++)
	;  /* empty */
    return i;
}

struct check_context {
    int count;
    int argc;
    char **argv;
};

static int
check_token(char *token, void *rock)
{
    struct check_context *context = rock;

    if (context->count < context->argc) {
	is_string(token, context->argv[context->count], "token %d is '%s'",
		  context->count, context->argv[context->count]);
    }
    context->count++;
    free(token);
    return 0;
}

static void
test_tokenize_valid_lines(void)
{
    struct test_case *t;
    struct check_context context;
    int code;

    for (t = valid_lines; t->line != NULL; t++) {
	memset(&context, 0, sizeof(context));
	context.argc = count_args(t->argv);
	context.argv = t->argv;
	diag("tokenizing: %s", t->line);
	code = cmd_Tokenize(t->line, check_token, &context);
	is_int(0, code, "cmd_Tokenize succeeds");
	is_int(context.count, context.argc, "argc is %d", context.argc);
    }
}

static void
test_tokenize_no_closing_quotes(void)
{
    struct test_case *t;
    int code;

    for (t = no_closing_quotes; t->line != NULL; t++) {
	diag("tokenizing: %s", t->line);
	code = cmd_Tokenize(t->line, NULL, NULL);
	is_int(CMD_NOCLOSINGQUOTE, code,
	    "cmd_Tokenize fails with CMD_NOCLOSINGQUOTE when the closing quote "
	    "is missing");
    }
    return;
}

static void
test_tokenize_no_escaped_character(void)
{
    struct test_case *t;
    int code;

    for (t = no_escaped_character; t->line != NULL; t++) {
	diag("tokenizing: %s", t->line);
	code = cmd_Tokenize(t->line, NULL, NULL);
	is_int(CMD_NOESCAPEDCHAR, code,
	    "cmd_Tokenize fails with CMD_NOESCAPEDCHAR when no character "
	    "follows a blashslash");
    }
}

static void
is_argv(int got_argc, char **got_argv, char **expected_argv)
{
    int expected_argc = count_args(expected_argv);
    int passes;
    int fails;
    int i;

    /* Check the argument count. */
    if (got_argc != expected_argc) {
	ok(0, "got argc %d, expected %d", got_argc, expected_argc);
	return;
    }

    /* Check each argument. */
    for (passes = 0, fails = 0, i = 0; i <= got_argc; i++) {
	char *got = got_argv[i];
	char *expected = expected_argv[i];

	diag("argv[%d] is '%s'", i, got);
	if (got == NULL && expected == NULL) {
	    if (i != expected_argc)
		fails++;
	} else if (got == NULL || expected == NULL) {
	    fails++;
	} else if (strcmp(got, expected) == 0) {
	    passes++;
	} else {
	    fails++;
	}
    }
    if (passes != expected_argc)
	fails++;

    ok(fails == 0, "argv matches");
}

void
test_split_valid_lines(void)
{
    struct test_case *t;
    int code;
    int argc;
    char **argv;

    for (t = valid_lines; t->line != NULL; t++) {
	diag("splitting: %s", t->line);
	code = cmd_Split(t->line, &argc, &argv);
	is_int(0, code, "cmd_Split succeeds");
	if (code == 0)
	    is_argv(argc, argv, t->argv);
	else
	    skip("cmd_Split failed");
	cmd_FreeSplit(&argv);
	if (argv != NULL)
	    bail("cmd_FreeSplit did not set argv to NULL");
    }
}

static void
test_split_no_closing_quotes(void)
{
    struct test_case *t;
    int code;
    int argc = 0;
    char **argv = NULL;

    for (t = no_closing_quotes; t->line != NULL; t++) {
	diag("splitting: %s", t->line);
	code = cmd_Split(t->line, &argc, &argv);
	is_int(CMD_NOCLOSINGQUOTE, code,
	    "cmd_Split fails with CMD_NOCLOSINGQUOTE when the closing quote "
	    "is missing");
	if (code == 0)
	    cmd_FreeSplit(&argv);
	if (argv != NULL)
	    bail("argv was not freed");
    }
}

static void
test_split_no_escaped_character(void)
{
    struct test_case *t;
    int code;
    int argc = 0;
    char **argv = NULL;

    for (t = no_escaped_character; t->line != NULL; t++) {
	diag("splitting: %s", t->line);
	code = cmd_Split(t->line, &argc, &argv);
	is_int(CMD_NOESCAPEDCHAR, code,
	    "cmd_Split fails with CMD_NOESCAPEDCHAR when no character "
	    "follows a blashslash");
	if (code == 0)
	    cmd_FreeSplit(&argv);
	if (argv != NULL)
	    bail("argv was not freed");
    }
}

int
main(int argc, char **argv)
{
    plan(202);

    test_tokenize_valid_lines();
    test_tokenize_no_closing_quotes();
    test_tokenize_no_escaped_character();

    test_split_valid_lines();
    test_split_no_closing_quotes();
    test_split_no_escaped_character();

    return 0;
}
