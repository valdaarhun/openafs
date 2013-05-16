package AFS::Load::Action;
use strict;
use POSIX;

=head1 NAME

AFS::Load::Action - test actions for afsload

=head1 SYNOPSIS

  step
      node * chdir "/afs/localcell/afsload"
  step
      node 0 creat file1 "file 1 contents"
      node 1 creat file2 "file 2 contents"
  step
      node * read file1 "file 1 contents"
      node * read file2 "file 2 contents"
  step
      node 0 unlink file1
      node 1 unlink file2

=head1 DESCRIPTION

This module and submodule defines the actions that can be specified in an
afsload test configuration file. The name of each action is the first thing
that appears after the 'node' directive and the node range specification.
Everything after the action name are the arguments for that action, which
are different for every action.

Each action is implemented as a small module in AFS::Load::Action::<name>,
where <name> is the name of the action. So, to implement a new action, simply
copy an existing action into a new module, and change the code.

Each action typically performs one filesystem operation, or a small series of
filesystem operations forming one logical operation. Each action may succeed
or fail; in the case of a failure an action provides an error code and
optionally an error string. In many cases the error code is the resultant
errno value for a filesystem operation, but that is not necessary; errno is
even recorded and reported separately in the case of a failure in case it is
relevant and different from the given error code.

The rest of this documentation just covers what each action does, and how to
use each one.

=cut

sub _interpret_impl($) {
	my $name = shift;
	my $class = "AFS::Load::Action::$name";
	if ($class->can('new')) {
		return $class;
	}
	die("Unknown action '$name' in configuration");
}

sub parse($$$@) {
	my $proto = shift;
	my $nAct = shift;

	my $implname = shift;
	my $impl = _interpret_impl($implname);

	my $ret = $impl->new(@_);
	$ret->{NACT} = $nAct;

	return $ret;
}

sub new($$) {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = {};
	bless $self, $class;
	return $self;
}

sub do($) {
	my $self = shift;
	my @ret = $self->doact();
	return @ret;
}

1;

=head1 chdir

=head2 EXAMPLE

  step
      node * chdir /afs/localcell/afsload

=head2 DESCRIPTION

The C<chdir> action just changes the working directory for the specified client
node. Using this and specifying paths in other actions as short, relative paths
can make the test configuration easier to read and write.

=head2 ARGUMENTS

The only argument is the directory to chdir to.

=head2 ERRORS

The same errors as the uafs_chdir() call, which should be the same errors as
you might expect from a regular chdir() call.

=cut

package AFS::Load::Action::chdir;
use strict;
use AFS::Load::Action;
use AFS::ukernel;
our @ISA = ("AFS::Load::Action");

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = $class->SUPER::new();

	bless($self, $class);

	my $args = $#_ + 1;
	if ($args != 1) {
		die("wrong number of args ($args) to chdir (should be 1)");
	}
	$self->{DIR} = $_[0];

	return $self;
}

sub doact($) {
	my $self = shift;
	my $code = AFS::ukernel::uafs_chdir($self->{DIR});
	if ($code) {
		return (int($!), '');
	}
	return (0,0);
}

sub str($) {
	my $self = shift;
	return "chdir($self->{DIR})";
}

1;

=head1 creat

=head2 EXAMPLE

  step
      node 0 creat file1 "file1 contents"

=head2 DESCRIPTION

Creates a file with the given filename with the given contents.

=head2 ARGUMENTS

The first argument is the file name to create, and the second argument is the
contents to write to the newly-created file.

=head2 ERRORS

Any error generated by uafs_open() or uafs_write() will cause an error. An
error will be generated if the file already exists.

=cut

package AFS::Load::Action::creat;
use strict;
use AFS::Load::Action;
use AFS::ukernel;
our @ISA = ("AFS::Load::Action");

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = $class->SUPER::new();

	bless($self, $class);

	my $args = $#_ + 1;
	if ($args != 2) {
		die("wrong number of args ($args) to creat (should be 2)");
	}
	$self->{FILE} = $_[0];
	$self->{DATA} = $_[1];

	return $self;
}

sub doact($) {
	my $self = shift;
	my $fd = AFS::ukernel::uafs_open($self->{FILE},
	                                 POSIX::O_CREAT | POSIX::O_EXCL | POSIX::O_WRONLY,
	                                 0644);
	if ($fd < 0) {
		return (int($!), 'open error');
	}

	my $code = AFS::ukernel::uafs_write($fd, $self->{DATA});
	if ($code < 0) {
		my $errno_save = int($!);
		AFS::ukernel::uafs_close($fd);
		return ($errno_save, 'write error');
	}

	AFS::ukernel::uafs_close($fd);

	return (0,0);
}

sub str($) {
	my $self = shift;
	return "creat($self->{FILE})";
}

1;

=head1 read

=head2 EXAMPLE

  step
      node 0 read file1 "file1 contents"

=head2 DESCRIPTION

Opens and reads a file and verifies that the file contains certain contents.

=head2 ARGUMENTS

The first argument is the file name to read, and the second argument is the
expected contents of the file.

=head2 ERRORS

Any error generated by the underlying filesystem ops will cause an error. An
error will also be generated if the file has contents different than what was
specified or has a different length than the given string. In which case, what
was actually in the file up to the length in the given string will be reported
in the error message.

=cut

package AFS::Load::Action::read;
use strict;
use AFS::Load::Action;
use AFS::ukernel;
our @ISA = ("AFS::Load::Action");

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = $class->SUPER::new();

	bless($self, $class);

	my $args = $#_ + 1;
	if ($args != 2) {
		die("wrong number of args ($args) to read (should be 2)");
	}
	$self->{FILE} = $_[0];
	$self->{DATA} = $_[1];

	return $self;
}

sub doact($) {
	my $self = shift;
	my $code;
	my $str;
	my @stat;
	my $fd = AFS::ukernel::uafs_open($self->{FILE},
	                                 POSIX::O_RDONLY,
	                                 0644);
	if ($fd < 0) {
		return (int($!), 'open error');
	}

	($code, @stat) = AFS::ukernel::uafs_fstat($fd);
	if ($code < 0) {
		my $errno_save = int($!);
		AFS::ukernel::uafs_close($fd);
		return ($errno_save, 'fstat error');
	}

	($code, $str) = AFS::ukernel::uafs_read($fd, length $self->{DATA});
	if ($code < 0) {
		my $errno_save = int($!);
		AFS::ukernel::uafs_close($fd);
		return ($errno_save, 'read error');
	}

	AFS::ukernel::uafs_close($fd);

	if ($str ne $self->{DATA}) {
		my $lenstr = '';
		if ($stat[7] != length $self->{DATA}) {
			$lenstr = " (total length $stat[7])";
		}
		return (-1, "got: $str$lenstr, expected: $self->{DATA}");
	}

	if ($stat[7] != length $self->{DATA}) {
		return (-1, "got file size: $stat[7], expected: ".(length $self->{DATA}));
	}

	return (0,0);
}

sub str($) {
	my $self = shift;
	return "read($self->{FILE})";
}

1;

=head1 cat

=head2 EXAMPLE

  step
      node 0 cat file1 file2

=head2 DESCRIPTION

Opens and reads the entire contents of all specified files, discarding any
read data.

=head2 ARGUMENTS

The argument list is a list of files to read.

=head2 ERRORS

Any error generated by the underlying filesystem ops will cause an error.
When an error occurs on reading one file, subsequent files will still be
attempted to be read, but an error will still be returned afterwards.

=cut

package AFS::Load::Action::cat;
use strict;
use AFS::Load::Action;
use AFS::ukernel;
our @ISA = ("AFS::Load::Action");

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = $class->SUPER::new();

	bless($self, $class);

	my $args = $#_ + 1;
	if ($args < 1) {
		die("wrong number of args ($args) to cat (should be at least 1)");
	}
	$self->{FILES} = [@_,];

	return $self;
}

sub doact($) {
	my $self = shift;
	my $code;
	my $err = 0;
	my $errstr = '';
	my $files = $self->{FILES};

	for my $file (@$files) {
		my $str;
		my $fd = AFS::ukernel::uafs_open($file,
		                                 POSIX::O_RDONLY,
		                                 0644);
		if ($fd < 0) {
			if ($err == 0) {
				$err = int($!);
			}
			$errstr .= "$file: open error\n";
			next;
		}

		$code = 1;
		while ($code > 0) {
			($code, $str) = AFS::ukernel::uafs_read($fd, 16384);
			if ($code < 0) {
				if ($err == 0) {
					$err = int($!);
				}
				$errstr .= "$file: read error\n";
			}
		}
		$str = undef;

		AFS::ukernel::uafs_close($fd);
	}

	if ($errstr) {
		return (-1, $errstr);
	}

	return (0,0);
}

sub str($) {
	my $self = shift;
	my $files = $self->{FILES};
	return "cat(".join(',', @$files).")";
}

1;

=head1 cp

=head2 EXAMPLE

  step
      node 0 cp 10M /dev/urandom foo.urandom

=head2 DESCRIPTION

Copies file data up to a certain amount.

=head2 ARGUMENTS

The first argument is the maximum amount of data to copy. It is a number of
bytes, optionally followed by a size suffix: K, M, G, or T. You can specify
-1 or "ALL" to copy until EOF on the source is encountered.

The second argument is the file to copy data out of. The third argument is the
destination file to copy into. The destination file may or may not exist; if it
exists, it is truncated before copying data.

Either file may be a file on local disk, but at least one must be in AFS. The
file will be treated as a file on local disk only if it starts with a leading
slash, and does not start with /afs/.

=head2 ERRORS

Any error generated by the underlying filesystem ops will cause an error.

=cut

package AFS::Load::Action::cp;

use strict;

use Number::Format qw(round unformat_number);

use AFS::Load::Action;
use AFS::ukernel;
our @ISA = ("AFS::Load::Action");

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = $class->SUPER::new();

	bless($self, $class);

	my $args = $#_ + 1;
	if ($args != 3) {
		die("wrong number of args ($args) to cp (should be 3)");
	}

	my $len = shift;
	$self->{SRC} = shift;
	$self->{DST} = shift;

	$len = uc($len);
	if ($len eq "ALL") {
		$self->{LEN} = -1;
	} else {
		$self->{LEN} = round(unformat_number($len), 0);
		if (not $self->{LEN}) {
			die("Invalid format ($len) given to cp");
		}
	}

	return $self;
}

sub _isafs($) {
	my $str = shift;
	if ($str =~ m:^([^/]|/afs/):) {
		# assume relative paths are in AFS
		# and of course anything starting with /afs/ is in AFS
		return 1;
	}
	return 0;
}

sub _cpin_sysread($$) {
	my ($inh, $len) = @_;
	my $buf;
	my $bytes = sysread($inh, $buf, $len);

	if (defined($bytes)) {
		return ($bytes, $buf);
	}
	return (-1, undef);
}

sub _cpout_syswrite($$) {
	my ($outh, $str) = @_;
	my $code;
	$code = syswrite($outh, $str, length $str);

	if (defined($code)) {
		return $code;
	}
	return -1;
}

sub _cp_close($) {
	my $fh = shift;
	if (close($fh)) {
		return 0;
	}
	return -1;
}

sub doact($) {
	my $self = shift;
	my $code;
	my $err = 0;
	my $errstr = '';

	my $inh;
	my $outh;
	my $readf;
	my $writef;
	my $inclosef;
	my $outclosef;

	if (_isafs($self->{SRC})) {
		$inh = AFS::ukernel::uafs_open($self->{SRC}, POSIX::O_RDONLY, 0644);
		if ($inh < 0) {
			return (int($!), "input open error (AFS)");
		}

		$readf = \&AFS::ukernel::uafs_read;
		$inclosef = \&AFS::ukernel::uafs_close;
	} else{
		open($inh, "< $self->{SRC}") or
			return (int($!), "input open error (local)");

		$readf = \&_cpin_sysread;
		$inclosef = \&_cp_close;
	}

	if (_isafs($self->{DST})) {
		$outh = AFS::ukernel::uafs_open($self->{DST},
		                                POSIX::O_WRONLY | POSIX::O_TRUNC | POSIX::O_CREAT,
		                                0644);
		if ($outh < 0) {
			return (int($!), "output open error (AFS)");
		}
		$writef = \&AFS::ukernel::uafs_write;
		$outclosef = \&AFS::ukernel::uafs_close;
	} else {
		open($outh, "> $self->{DST}") or
			return (int($!), "output open error(local)");
		$writef = \&_cpout_syswrite;
		$outclosef = \&_cp_close;
	}

	my $str;
	my $remaining = $self->{LEN};
	while ($remaining) {
		
		my $len = 16384;
		my $rbytes;
		my $wbytes;

		if ($remaining > 0 && $remaining < $len) {
			$len = $remaining;
		}

		($rbytes, $str) = &$readf($inh, $len);
		if ($rbytes < 0) {
			my $errno_save = int($!);

			&$inclosef($inh);
			&$outclosef($outh);

			return ($errno_save, "read error");
		}

		if ($rbytes == 0) {
			last;
		}

		$wbytes = &$writef($outh, $str);
		if ($wbytes != $rbytes) {
			my $errno_save = int($!);

			&$inclosef($inh);
			&$outclosef($outh);

			return ($errno_save, "write error ($wbytes/$rbytes)");
		}

		if ($remaining > 0) {
			$remaining -= $rbytes;
		}
	}

	&$inclosef($inh);
	if (&$outclosef($outh) != 0) {
		return (int($!), "close error");
	}

	return (0,0);
}

sub str($) {
	my $self = shift;
	return "cp(".join(',', $self->{LEN}, $self->{SRC}, $self->{DST}).")";
}

1;

=head1 truncwrite

=head2 EXAMPLE

  step
      node 0 truncwrite file1 "different contents"

=head2 DESCRIPTION

Opens and truncates an existing file, then writes some data to it.

=head2 ARGUMENTS

The first argument is the file name to open and truncate, and the second
argument is the data to write to the file.

=head2 ERRORS

Any error generated by the underlying filesystem ops will cause an error. Note
that the file must already exist for this to succeed.

=cut

package AFS::Load::Action::truncwrite;
use strict;
use AFS::Load::Action;
use AFS::ukernel;
our @ISA = ("AFS::Load::Action");

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = $class->SUPER::new();

	bless($self, $class);

	my $args = $#_ + 1;
	if ($args != 2) {
		die("wrong number of args ($args) to truncwrite (should be 2)");
	}
	$self->{FILE} = $_[0];
	$self->{DATA} = $_[1];

	return $self;
}

sub doact($) {
	my $self = shift;
	my $fd = AFS::ukernel::uafs_open($self->{FILE},
	                                 POSIX::O_WRONLY | POSIX::O_TRUNC,
	                                 0644);
	if ($fd < 0) {
		return (int($!), 'open error');
	}

	my ($code) = AFS::ukernel::uafs_write($fd, $self->{DATA});
	if ($code < 0) {
		my $errno_save = int($!);
		AFS::ukernel::uafs_close($fd);
		return ($errno_save, 'write error');
	}

	AFS::ukernel::uafs_close($fd);

	if ($code eq length $self->{DATA}) {
		return (0,0);
	}

	return (-1, "got: $code bytes written, expected: ".(length $self->{DATA}));
}

sub str($) {
	my $self = shift;
	return "truncwrite($self->{FILE}, $self->{DATA})";
}

1;

=head1 append

=head2 EXAMPLE

  step
      node 0 append file1 "more data"

=head2 DESCRIPTION

Opens an existing file, and appends some data to it.

=head2 ARGUMENTS

The first argument is the file name to open, and the second argument is the
data to append to the file.

=head2 ERRORS

Any error generated by the underlying filesystem ops will cause an error. Note
that the file must already exist for this to succeed.

=cut

package AFS::Load::Action::append;
use strict;
use AFS::Load::Action;
use AFS::ukernel;
our @ISA = ("AFS::Load::Action");

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = $class->SUPER::new();

	bless($self, $class);

	my $args = $#_ + 1;
	if ($args != 2) {
		die("wrong number of args ($args) to append (should be 2)");
	}
	$self->{FILE} = $_[0];
	$self->{DATA} = $_[1];

	return $self;
}

sub doact($) {
	my $self = shift;
	my $fd = AFS::ukernel::uafs_open($self->{FILE},
	                                 POSIX::O_WRONLY | POSIX::O_APPEND,
	                                 0644);
	if ($fd < 0) {
		return (int($!), 'open error');
	}

	my ($code) = AFS::ukernel::uafs_write($fd, $self->{DATA});
	if ($code < 0) {
		my $errno_save = int($!);
		AFS::ukernel::uafs_close($fd);
		return ($errno_save, 'write error');
	}

	AFS::ukernel::uafs_close($fd);

	if ($code eq length $self->{DATA}) {
		return (0,0);
	}

	return (-1, "got: $code bytes written, expected: ".(length $self->{DATA}));
}

sub str($) {
	my $self = shift;
	return "append($self->{FILE}, $self->{DATA})";
}

1;

=head1 unlink

=head2 EXAMPLE

  step
      node 0 unlink file1 [file2] ... [fileN]

=head2 DESCRIPTION

Unlinks the specified file(s).

=head2 ARGUMENTS

All arguments are files to unlink.

=head2 ERRORS

Any error generated by the underlying uafs_unlink() call. An error will be
returned if unlinking any file generates an error, but we will attempt to
unlink all specified files.

=cut

package AFS::Load::Action::unlink;
use strict;
use AFS::Load::Action;
use AFS::ukernel;
our @ISA = ("AFS::Load::Action");

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = $class->SUPER::new();

	bless($self, $class);

	my $args = $#_ + 1;
	if ($args < 1) {
		die("wrong number of args ($args) to unlink (should be at least 1)");
	}
	$self->{FILES} = [@_];

	return $self;
}

sub doact($) {
	my $self = shift;
	my $ret = 0;
	my @errfiles = ();
	my $files = $self->{FILES};

	for my $file (@$files) {
		my $code = AFS::ukernel::uafs_unlink($file);
		if ($code) {
			if (not length(@errfiles)) {
				$ret = int($!);
			}
			push(@errfiles, $file);
		}
	}

	if (@errfiles) {
		return ($ret, join(', ', @errfiles));
	}
	return (0,0);
}

sub str($) {
	my $self = shift;
	my $files = $self->{FILES};
	return "unlink(".(join(',', @$files)).")";
}

1;

=head1 rename

=head2 EXAMPLE

  step
      node 0 rename file1 file2

=head2 DESCRIPTION

Renames a file within a volume.

=head2 ARGUMENTS

The first argument is the file to move, and the second argument is the new
name to move it to.

=head2 ERRORS

Any error generated by the underlying uafs_rename() call.

=cut

package AFS::Load::Action::rename;
use strict;
use AFS::Load::Action;
use AFS::ukernel;
our @ISA = ("AFS::Load::Action");

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = $class->SUPER::new();

	bless($self, $class);

	my $args = $#_ + 1;
	if ($args != 2) {
		die("wrong number of args ($args) to rename (should be 2)");
	}
	$self->{SRC} = $_[0];
	$self->{DST} = $_[1];

	return $self;
}

sub doact($) {
	my $self = shift;
	my $code = AFS::ukernel::uafs_rename($self->{SRC}, $self->{DST});
	if ($code) {
		return (int($!), '');
	}
	return (0,0);
}

sub str($) {
	my $self = shift;
	return "rename($self->{SRC}, $self->{DST})";
}

1;

=head1 hlink

=head2 EXAMPLE

  step
      node 0 hlink file1 file2

=head2 DESCRIPTION

Hard-links a file within a directory.

=head2 ARGUMENTS

The first argument is the source file, and the second argument is the name of
the new hard link.

=head2 ERRORS

Any error generated by the underlying uafs_link() call.

=cut

package AFS::Load::Action::hlink;
use strict;
use AFS::Load::Action;
use AFS::ukernel;
our @ISA = ("AFS::Load::Action");

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = $class->SUPER::new();

	bless($self, $class);

	my $args = $#_ + 1;
	if ($args != 2) {
		die("wrong number of args ($args) to hlink (should be 2)");
	}
	$self->{SRC} = $_[0];
	$self->{DST} = $_[1];

	return $self;
}

sub doact($) {
	my $self = shift;
	my $code = AFS::ukernel::uafs_link($self->{SRC}, $self->{DST});
	if ($code) {
		return (int($!), '');
	}
	return (0,0);
}

sub str($) {
	my $self = shift;
	return "hlink($self->{SRC}, $self->{DST})";
}

1;

=head1 slink

=head2 EXAMPLE

  step
      node 0 slink file1 file2

=head2 DESCRIPTION

Symlinks a file within a directory.

=head2 ARGUMENTS

The first argument is the source file, and the second argument is the name of
the new symlink.

=head2 ERRORS

Any error generated by the underlying uafs_symlink() call.

=cut

package AFS::Load::Action::slink;
use strict;
use AFS::Load::Action;
use AFS::ukernel;
our @ISA = ("AFS::Load::Action");

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = $class->SUPER::new();

	bless($self, $class);

	my $args = $#_ + 1;
	if ($args != 2) {
		die("wrong number of args ($args) to slink (should be 2)");
	}
	$self->{SRC} = $_[0];
	$self->{DST} = $_[1];

	return $self;
}

sub doact($) {
	my $self = shift;
	my $code = AFS::ukernel::uafs_symlink($self->{SRC}, $self->{DST});
	if ($code) {
		return (int($!), '');
	}
	return (0,0);
}

sub str($) {
	my $self = shift;
	return "slink($self->{SRC}, $self->{DST})";
}

1;

=head1 access_r

=head2 EXAMPLE

  step
      node 0 access_r file1

=head2 DESCRIPTION

Verifies that a file exists and is readable.

=head2 ARGUMENTS

The only argument is a file to check readability.

=head2 ERRORS

Any error generated by the underlying uafs_open() call.

=cut

package AFS::Load::Action::access_r;
use strict;
use AFS::Load::Action;
use AFS::ukernel;
our @ISA = ("AFS::Load::Action");

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = $class->SUPER::new();

	bless($self, $class);

	my $args = $#_ + 1;
	if ($args != 1) {
		die("wrong number of args ($args) to access_r (should be 1)");
	}
	$self->{FILE} = $_[0];

	return $self;
}

sub doact($) {
	my $self = shift;
	my $fd = AFS::ukernel::uafs_open($self->{FILE}, POSIX::O_RDONLY, 0644);
	if ($fd < 0) {
		return (int($!), '');
	}
	AFS::ukernel::uafs_close($fd);
	return (0,0);
}

sub str($) {
	my $self = shift;
	return "access_r($self->{FILE})";
}

1;

=head1 fail

=head2 EXAMPLE

  step
      node 0 fail ENOENT access_r file1

=head2 DESCRIPTION

Verifies that another action fails with a specific error code. This is useful
when an easy way to specify an action is to specify when another action fails,
instead of needing to write a new action.

For example, the above example runs the C<access_r> action on file1, and
succeeds if the C<access_r> action returns with an ENOENT error.

=head2 ARGUMENTS

The first argument is the error code that the subsequent action should fail
with. This can be a number, or an errno symbolic constant. The next argument
is the name of any other action, and the remaining arguments are whatever
arguments should be supplied to that action.

=head2 ERRORS

We only raise an error if the specified action generates a different error than
what was specified, or if no error was raised. In which case, the error that
was generated (if any) is reported.

=cut

package AFS::Load::Action::fail;
use strict;
use AFS::Load::Action;
use AFS::ukernel;
use Errno;
our @ISA = ("AFS::Load::Action");

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = $class->SUPER::new();

	bless($self, $class);

	my $code = shift;
	my $args = $#_ + 1;
	if ($args < 2) {
		die("wrong number of args ($args) to fail (should be at least 2)");
	}

	if (!($code =~ m/^\d$/)) {
		my $nCode = eval("if (exists &Errno::$code) { return &Errno::$code; } else { return undef; }");
		if (!defined($nCode)) {
			die("Invalid symbolic error name $code\n");
		}
		$code = $nCode;
	}
	$self->{ERRCODE} = $code;
	$self->{ACT} = AFS::Load::Action->parse(-1, @_);

	return $self;
}

sub doact($) {
	my $self = shift;
	my @ret = $self->{ACT}->doact();

	if ($ret[0] == $self->{ERRCODE}) {
		return (0,0);
	}

	return (-1, "got error: $ret[0] (string: $ret[1]), expected: $self->{ERRCODE}");
}

sub str($) {
	my $self = shift;
	return "fail(".$self->{ACT}->str().")";
}

1;

=head1 ignore

=head2 EXAMPLE

  step
      node 0 ignore unlink file1

=head2 DESCRIPTION

Performs another action, ignoring any given errors and always returning
success.

=head2 ARGUMENTS

The first argument is the name of any other action, and the remaining
arguments are whatever arguments should be supplied to that action.

=head2 ERRORS

None.

=cut

package AFS::Load::Action::ignore;
use strict;
use AFS::Load::Action;
use AFS::ukernel;
use Errno;
our @ISA = ("AFS::Load::Action");

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = $class->SUPER::new();

	bless($self, $class);

	my $args = $#_ + 1;
	if ($args < 1) {
		die("wrong number of args ($args) to ignore (should be at least 1)");
	}

	$self->{ACT} = AFS::Load::Action->parse(-1, @_);

	return $self;
}

sub doact($) {
	my $self = shift;
	my @ret = $self->{ACT}->doact();

	return (0,0);
}

sub str($) {
	my $self = shift;
	return "ignore(".$self->{ACT}->str().")";
}

1;

=head1 mkdir

=head2 EXAMPLE

  step
      node 0 mkdir dir1

=head2 DESCRIPTION

Creates a directory.

=head2 ARGUMENTS

The only argument is the directory to create.

=head2 ERRORS

The same errors as the uafs_mkdir() call.

=cut

package AFS::Load::Action::mkdir;
use strict;
use AFS::Load::Action;
use AFS::ukernel;
our @ISA = ("AFS::Load::Action");

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = $class->SUPER::new();

	bless($self, $class);

	my $args = $#_ + 1;
	if ($args != 1) {
		die("wrong number of args ($args) to mkdir (should be 1)");
	}
	$self->{DIR} = $_[0];

	return $self;
}

sub doact($) {
	my $self = shift;
	my $code = AFS::ukernel::uafs_mkdir($self->{DIR}, 0775);
	if ($code) {
		return (int($!), '');
	}
	return (0,0);
}

sub str($) {
	my $self = shift;
	return "mkdir($self->{DIR})";
}

1;

=head1 rmdir

=head2 EXAMPLE

  step
      node 0 rmdir dir1

=head2 DESCRIPTION

Removes a directory.

=head2 ARGUMENTS

The only argument is the directory to remove.

=head2 ERRORS

The same errors as the uafs_rmdir() call.

=cut

package AFS::Load::Action::rmdir;
use strict;
use AFS::Load::Action;
use AFS::ukernel;
our @ISA = ("AFS::Load::Action");

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = $class->SUPER::new();

	bless($self, $class);

	my $args = $#_ + 1;
	if ($args != 1) {
		die("wrong number of args ($args) to rmdir (should be 1)");
	}
	$self->{DIR} = $_[0];

	return $self;
}

sub doact($) {
	my $self = shift;
	my $code = AFS::ukernel::uafs_rmdir($self->{DIR});
	if ($code) {
		return (int($!), '');
	}
	return (0,0);
}

sub str($) {
	my $self = shift;
	return "rmdir($self->{DIR})";
}

=head1 AUTHORS

Andrew Deason E<lt>adeason@sinenomine.netE<gt>, Sine Nomine Associates.

=head1 COPYRIGHT

Copyright 2010-2011 Sine Nomine Associates.

=cut

1;