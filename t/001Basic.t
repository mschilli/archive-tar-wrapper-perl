######################################################################
# Test suite for Archive::Tar::Wrapper
# by Mike Schilli <cpan@perlmeister.com>
######################################################################

use warnings;
use strict;
use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($ERROR);

use File::Temp qw(tempfile);

my $TARDIR = "data";
$TARDIR = "t/$TARDIR" unless -d $TARDIR;

use Test::More tests => 19;
BEGIN { use_ok('Archive::Tar::Wrapper') };

my $arch = Archive::Tar::Wrapper->new();

ok($arch->read("$TARDIR/foo.tgz"), "opening compressed tarfile");

ok($arch->locate("001Basic.t"), "find 001Basic.t");
ok($arch->locate("./001Basic.t"), "find ./001Basic.t");

ok(!$arch->locate("nonexist"), "find nonexist");

# Add a new file
my $tmploc = $arch->locate("001Basic.t");
ok($arch->add("foo/bar/baz", $tmploc), "adding file");
ok($arch->locate("foo/bar/baz"), "find added file");

ok($arch->add("foo/bar/permtest", $tmploc, 0770), "adding file");

# Make a tarball
my($fh, $filename) = tempfile(CLEANUP => 1);
ok($arch->write($filename), "Tarring up");

# List 
my $a2 = Archive::Tar::Wrapper->new();
ok($a2->read($filename), "Reading in new tarball");
my $elements = $a2->list_all();
my $got = join " ", sort @$elements;
is($got, "001Basic.t foo/bar/baz foo/bar/permtest", "Check list");

my $f1 = $a2->locate("001Basic.t");
my $f2 = $a2->locate("foo/bar/baz");
ok(-s $f1 > 0, "Checking tarball files sizes");
ok(-s $f2 > 0, "Checking tarball files sizes");

is(-s $f1, -s $f2, "Comparing tarball files sizes");

my $f3 = $a2->locate("foo/bar/permtest");
my $perm = ((stat($f3))[2] & 07777);
is($perm, 0770, "permtest");

# Iterators
$arch->list_reset();
my @elements = ();
while(my $entry = $arch->list_next()) {
    push @elements, $entry->[0];
}
$got = join " ", sort @elements;
is($got, "001Basic.t foo/bar/baz foo/bar/permtest", "Check list");

# Check optional file names for extraction
#data/bar.tar 
#drwxrwxr-x mschilli/mschilli 0 2005-07-24 12:15:34 bar/
#-rw-rw-r-- mschilli/mschilli 11 2005-07-24 12:15:27 bar/bar.dat
#-rw-rw-r-- mschilli/mschilli 11 2005-07-24 12:15:34 bar/foo.dat

my $a3 = Archive::Tar::Wrapper->new();
$a3->read("$TARDIR/bar.tar", "bar/bar.dat");
$elements = $a3->list_all();

is(scalar @$elements, 1, "only one file extracted");
is($elements->[0], "bar/bar.dat", "only one file extracted");

# Ask for non-existent files in tarball
my $a4 = Archive::Tar::Wrapper->new();

    # Suppress the warning
Log::Log4perl->get_logger("")->level($FATAL);

my $rc = $a4->read("$TARDIR/bar.tar", "bar/bar.dat", "quack/schmack");
is($rc, undef, "Failure to ask for non-existent files");
