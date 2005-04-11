###########################################
# Archive::Tar::Wrapper -- 2005, Mike Schilli <cpan@perlmeister.com>
###########################################

###########################################
package Archive::Tar::Wrapper;
###########################################

use strict;
use warnings;
use File::Temp qw(tempdir tempfile);
use Log::Log4perl qw(:easy);
use File::Spec::Functions;
use File::Spec;
use File::Path;
use Cwd;

our $VERSION = "0.01";

###########################################
sub new {
###########################################
    my($class, %options) = @_;

    my $self = {
        tmpdir  => tempdir(CLEANUP => 1),
        tar     => bin_find("tar"),
        %options,
    };

    $self->{tardir} = File::Spec->catfile($self->{tmpdir}, "tar");
    mkpath [$self->{tardir}], 0, 0755 or
        LOGDIE "Cannot mkpath $self->{tardir} ($!)";

    bless $self, $class;
}

###########################################
sub open {
###########################################
    my($self, $tarfile) = @_;

    my $cwd = getcwd();

    unless(File::Spec::Functions::file_name_is_absolute($tarfile)) {
        $tarfile = File::Spec::Functions::rel2abs($tarfile, $cwd);
    }

    chdir $self->{tardir} or 
        LOGDIE "Cannot chdir to $self->{tardir}";

    my $compr_opt = "";
    $compr_opt = "z" if $self->is_compressed($tarfile);

    my $cmd = "$self->{tar} ${compr_opt}xf $tarfile";

    DEBUG "Running $cmd";
    my $rc = system("$cmd 2>/dev/null");

    chdir $cwd or LOGDIE "Cannot chdir to $cwd";

    return 1 if $rc == 0;

    ERROR "$cmd: $!";
    return undef;
}

###########################################
sub is_compressed {
###########################################
    my($self, $tarfile) = @_;

    return 1 if $tarfile =~ /\.t?gz$/i;
    return 0;
}

###########################################
sub find {
###########################################
    my($self, $rel_path) = @_;

    my $real_path = File::Spec->catfile($self->{tardir}, $rel_path);

    if(-e $real_path) {
        DEBUG "$real_path exists";
        return $real_path;
    }
    DEBUG "$real_path doesn't exist";

    WARN "$rel_path not found in tarball";
    return undef;
}

###########################################
sub DESTROY {
###########################################
    my($self) = @_;
}

######################################
sub bin_find {
######################################
    my($exe) = @_;

    for my $path (split /:/, $ENV{PATH}) {
        my $full = File::Spec->catfile($path, $exe);
            return $full if -x $full;
    }
    return undef;
}

1;

__END__

=head1 NAME

Archive::Tar::Wrapper - API wrapper around the 'tar' utility

=head1 SYNOPSIS

    use Archive::Tar::Wrapper;

    my $arch = Archive::Tar::Wrapper->new();

        # Open a tarball, expand it into a temporary directory
    $arch->open("archive.tgz");

        # Iterate over all entries in the archive
    $arch->list_reset(); # Reset Iterator
                         # Iterate through archive
    while(my($tar_path, $phys_path) = $arch->list_next()) {
        print "$tar_path\n";
    }

        # Get a huge list with all entries
    for my $entry ($arch->list_all()) {
        my($tar_path, $real_path) = @$entry;
        print "Tarpath: $tar_path Tempfile: $real_path\n";
    }

        # Add a new entry
    $arch->add($logic_path, $file_or_stringref);

        # Find the physical location of a temporary file
    my($tmp_path) = $arch->find($tar_path);

        # Create a tarball
    $arch->tarup($tarfile, $compress);

=head1 DESCRIPTION

Archive::Tar::Wrapper is an API wrapper around the 'tar' command line
utility. It never stores anything in memory, but works on temporary
directory structures on disk instead. It provides a mapping between
the logical paths in the tarball and the 'real' files in the temporary
directory on disk.

It differs from Archive::Tar in two ways:

=over 4

=item *

Archive::Tar::Wrapper doesn't hold anything in memory. Everything is
stored on disk. 

=item *

Archive::Tar::Wrapper is 100% compliant with the platform's C<tar> 
utility, because it uses it internally.

=back

Copyright 2005 by Mike Schilli, all rights reserved.
This program is free software, you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 AUTHOR

2005, Mike Schilli <cpan@perlmeister.com>
