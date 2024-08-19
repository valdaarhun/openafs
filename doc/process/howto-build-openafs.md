# How to build OpenAFS

This is a developer oriented guide on how to build OpenAFS on unix-like
platforms.  See [howto-create-packages.md](howto-create-packages.md) to learn
how to create installation packages for various unix-like platforms.

## Build requirements

The following tools are needed to build OpenAFS:

- a C Language compiler (gcc, clang, etc)
- make
- assembler
- linker
- ranlib
- lex
- yacc
- install
- perl (only to build the documentation)

The C compiler used must be capable of building kernel modules for the target
platform.

In addition to the above, the following tools are needed to build OpenAFS from
a Git checkout:

- git
- autoconf (version 2.64 or later)
- automake
- libtool


### RedHat/Fedora/CentOS/AlmaLinux/Rocky

The following RPM packages are required to build OpenAFS on RPM based
distributions.

* autoconf
* automake
* bison
* elfutils-devel
* flex
* fuse-devel
* gcc
* glibc-devel
* krb5-devel
* libtool
* make
* ncurses-devel
* openssl-devel
* pam-devel
* perl-devel
* perl-ExtUtils-Embed
* swig

The `kernel-devel` package matching your current running kernel version is
required to build the OpenAFS kernel module.  It is recommended to upgrade your
running kernel to the most current version and reboot if needed before
installing the `kernel-devel` package.

Install the kernel development package with the command.
    ```
    $ yum install "kernel-devel-uname-r==$(uname -r)"
    ```

### Debian

The following Debian packages are required to build OpenAFS on Debian and
Debian based distributions.

* autoconf
* automake
* bison
* comerr-dev
* cpio
* dblatex
* debhelper
* dkms
* docbook-xsl
* doxygen
* flex
* libfuse-dev
* libkrb5-dev
* libncurses5-dev
* libpam0g-dev
* libxml2-utils
* perl
* pkg-config
* swig
* xsltproc

### FreeBSD

The following packages are required to build OpenAFS on FreeBSD.

* autoconf
* automake
* dblatex
* docbook-xsl
* fusefs-libs
* libtool
* libxslt
* perl
* pkgconf
* python
* ruby
* zip

In addition, FreeBSD systems require kernel sources and a configured kernel
build directory (see section "FreeBSD Notes" in the README file).

### Oracle Solaris 11.4

**Oracle Developer Studio** C compiler is required to build the OpenAFS kernel
module for Solaris and is usually used to build the userspace binaries as well.
**Oracle Developer Studio** can be installed using the Solaris package
installer or from a tar file.  See the [Oracle
Documentation](https://docs.oracle.com/) for more information.

In addition to the C compiler, the following packages are required to build
OpenAFS on Solaris.

* autoconf
* automake
* bison
* flex
* gnu-binutils
* gnu-coreutils
* gnu-sed
* library/security/openssl
* libtool
* make
* onbld
* pkg-config
* runtime/perl
* text/locale

## Code Checkout

OpenAFS code can be checked out using Git.  Git checkouts do not include files
generated by autoconf. You can run `regen.sh` (at the top level) to create
these files. You will need to have autoconf and automake installed on your
system to run `regen.sh`.

The current development series is in the branch named `master`. The stable
releases are on separate branches named something like
`openafs-stable_<version>` with a separate branch for each major stable release
series.

### Step-by-step

1. Obtain the Git software. If you are using a system with a standard
   software repository, Git may already be available as a package named
   something like git or git-core.  Otherwise, go to http://git-scm.com/

2. Run the command:
    ```
    $ git clone git://git.openafs.org/openafs.git
    ```
   This will download the full repository and leave a checked-out tree in
   a subdirectory of the current directory named openafs.

3. Generate the additional required files:
    ```
    $ cd openafs
    $ ./regen.sh
    ```
## Building

Run `configure` with the desired options.
    ```
    $ ./configure --enable-checking
    ```
To see the available configure options, run `./configure --help`.

Run `make` to build the full tree:
    ```
    $ make
    ```
Run the included unit tests:
    ```
    $ make check
    ```
Create an installation tree with `make`.
    ```
    $ make install DESTDIR=<path-to-staging-directory>
    ```
Where `<path-to-staging-directory>` is a directory to stage the installation,
such as `/tmp/openafs`.