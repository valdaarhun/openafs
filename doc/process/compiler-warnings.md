# Warnings

## OpenAFS Warning detection

There's been a concerted effort over the last few years, by many developers,
to reduce the number of warnings in the OpenAFS tree. In an attempt to
prevent warnings from creeping back in, we now have the ability to break the
build when new warnings appear.

This is only available for systems with gcc 4.2 or later or clang 3.2 or
later, and is disabled unless the `--enable-checking` option is supplied to
configure. Because we can't remove all of the warnings, we permit file by
file (and warning by warning) disabling of specific warnings. The
`--enable-checking=all` option prevents
this, and errors for any file containing a warning.  (At present, using
`--enable-checking=all` will error out quite early in the build, so this
is only useful for developers attempting to clean up compiler warnings.)

## Disabling warnings

If warnings are unavoidable in a particular part of the build, they may be
disabled in an number of ways.

You can disable a single warning type in a particular file by using GCC
pragmas. If a warning can be disabled with a pragma, then the switch to use
will be listed in the error message you receive from the compiler. Pragmas
should be wrapped in `IGNORE_SOME_GCC_WARNINGS`, so that they aren't used
with non-gcc compilers, and can be disabled if desired. For example:

    #ifdef IGNORE_SOME_GCC_WARNINGS
    # pragma GCC diagnostic warning "-Wold-style-definition"
    #endif

It would appear that when built with `-Werror`, the llvm clang compiler will
still upgrade warnings that are suppressed in this way to errors. In this case,
the fix is to mark that warning as ignored, but only for clang. For example:

    #ifdef IGNORE_SOME_GCC_WARNINGS
    # ifdef __clang__
    #  pragma GCC diagnostic ignored "-Wdeprecated-declarations"
    # else
    #  pragma GCC diagnostic warning "-Wdeprecated-declarations"
    # endif
    #endif

If the source cannot be changed to add a pragma, you might be able to use the
autoconf function `AX_APPEND_COMPILE_FLAGS` to create a new macro that disables
the warning and then use macro for the build options for that file. For an
example, see how the autoconf macro `CFLAGS_NOIMPLICIT_FALLTHROUGH` is defined and
used.

Finally, if there isn't a way to disable the specific warning, you will need to
disable all warnings for the file in question. You can do this by supplying
the autoconf macro `@CFLAGS_NOERROR@` in the build options for the file. For
example:

    lex.yy.o : lex.yy.c y.tab.c
           ${CC} -c ${CFLAGS} @CFLAGS_NOERROR@ lex.yy.c

## Inhibited warnings

If you add a new warning inhibition, also add it to the list below.

* `uss/lex.i`
  - warning: `fallthrough`
  - reason: clang fallthrough, flex generated code

* `comerr/et_lex.lex.l`
  - warning: `fallthrough`
  - reason: clang fallthrough, flex generated code pragma set to ignored where
            included in `error_table.y`

* `afs/afs_syscall.c`
  - warning: `old-style`

* `afs/afs_syscall.c`
  - warning: `strict-proto`

* `afs/afs_syscall.c` (ukernel)
  - warning: `all`
  - reason: syscall pointer issues

* `afsd/afsd_kernel.c`
  - warning: `deprecated`
  - reason : `daemon()` marked as deprecated on Darwin

* `bozo/bosserver.c`
  - warning: `deprecated`
  - reason: `daemon()` marked as deprecated on Darwin

* `bucoord/ubik_db_if.c`
  - warning: `strict-proto`
  - reason: `ubik_Call_SingleServer`

* `bucoord/commands.c`
  - warning: `all`
  - reason: signed vs unsigned for dates

* `external/heimdal/hcrypto/validate.c`
  - warning: `all`
  - reason: statement with empty body

* `external/heimdal/hcrypto/evp.c`
  - warning: `cast-function-type`
  - reason: Linux kernel build uses -Wcast-function-type

* `external/heimdal/hcrypto/evp-algs.c`
  - warning: `cast-function-type`
  - reason: Linux kernel build uses -Wcast-function-type

* `external/heimdal/krb5/crypto.c`
  - warning: `use-after-free`
  - reason: False positive on certain GCC compilers

* `kauth/admin_tools.c`
  - warning: `strict-proto`
  - reason: `ubik_Call`

* `kauth/authclient.c`
  - warning: `strict-proto`
  - reason: `ubik_Call` nonsense

* `libadmin/kas/afs_kasAdmin.c`
  - warning: `strict-proto`
  - reason: `ubik_Call` nonsense

* `libadmin/samples/rxstat_query_peer.c`
  - warning: `all`
  - reason: `util_RPCStatsStateGet` types

* `libadmin/samples/rxstat_query_process.c`
  - warning: `all`
  - reason: `util_RPCStatsStateGet` types

* `libadmin/test/client.c`
  - warning: `all`
  - reason: `util_RPCStatsStateGet` types

* `ubik/ubikclient.c`
  - warning: `strict-protos`
  - reason: `ubik_Call`

* `volser/vol-dump.c`
  - warning: `format`
  - reason: `afs_sfsize_t`

* `rxkad/ticket5.c`
  - warning: `format-truncation`
  - reason: inside included file v5der.c in the function
            `_heim_time2generalizedtime`, the two snprintf calls
            raise format-truncation warnings due to the arithmetic
            on `tm_year` and `tm_mon` fields

* `lwp/process.c`
  - warning: `dangling-pointer`
  - reason: Ignore the legitimate use of saving the address of a stack variable
