######################################################################
# Test suite for Archive::Tar::Wrapper
# by Mike Schilli <cpan@perlmeister.com>
######################################################################

use warnings;
use strict;
use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($ERROR);

my $TARDIR = "data";
$TARDIR = "t/$TARDIR" unless -d $TARDIR;

use Test::More qw(no_plan);
BEGIN { use_ok('Archive::Tar::Wrapper') };

my $arch = Archive::Tar::Wrapper->new();

ok($arch->open("$TARDIR/foo.tgz"), "opening compressed tarfile");

ok($arch->find("001Basic.t"), "find 001Basic.t");
ok($arch->find("./001Basic.t"), "find ./001Basic.t");

ok(!$arch->find("nonexist"), "find nonexist");
