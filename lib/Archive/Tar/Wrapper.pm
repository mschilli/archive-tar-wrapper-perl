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
use File::Copy;
use File::Find;
use File::Basename;
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

    $self->{objdir} = tempdir(CLEANUP => 1);

    bless $self, $class;
}

###########################################
sub read {
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
sub locate {
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
sub add {
###########################################
    my($self, $rel_path, $path_or_stringref, $perm, $user) = @_;

    my $target = File::Spec->catfile($self->{tardir}, $rel_path);

    if(ref($path_or_stringref)) {
        open FILE, ">$target" or LOGDIE "Can't open $target ($!)";
        print FILE $path_or_stringref;
        close FILE;
    } else {
        my $target_dir = dirname($target);
        mkpath($target_dir, 0, 0755) unless -d $target_dir;
        copy $path_or_stringref, $target or
            LOGDIE "Can't copy $path_or_stringref to $target ($!)";
    }

    if(defined $user) {
        chown $user, $target or
            LOGDIE "Can't chown $target to $user ($!)";
    }

    if(defined $perm) {
        chmod $perm, $target or 
                LOGDIE "Can't chmod $target to $perm ($!)";
    }

    if(!defined $user and !defined $perm and !ref($path_or_stringref)) {
        perm_cp($path_or_stringref, $target) or
            LOGDIE "Can't perm_cp $path_or_stringref to $target ($!)";
    }

    1;
}

######################################
sub perm_cp {
######################################
    # Lifted from Ben Okopnik's
    # http://www.linuxgazette.com/issue87/misc/tips/cpmod.pl.txt

    my $perms = perm_get($_[0]);
    perm_set($_[1], $perms);
}

######################################
sub perm_get {
######################################
    my($filename) = @_;

    my @stats = (stat $filename)[2,4,5] or
        LOGDIE "Cannot stat $filename ($!)";

    return \@stats;
}

######################################
sub perm_set {
######################################
    my($filename, $perms) = @_;

    chown($perms->[1], $perms->[2], $filename) or
        LOGDIE "Cannot chown $filename ($!)";
    chmod($perms->[0] & 07777,    $filename) or
        LOGDIE "Cannot chmod $filename ($!)";
}

###########################################
sub remove {
###########################################
    my($self, $rel_path) = @_;

    my $target = File::Spec->catfile($self->{tardir}, $rel_path);

    rmtree($target) or LOGDIE "Can't rmtree $target ($!)";
}

###########################################
sub list_all {
###########################################
    my($self) = @_;

    my $cwd = getcwd();
    chdir $self->{tardir} or LOGDIE "Can't chdir to $self->{tardir} ($!)";

    my @entries = ();

    find(sub {
              return if -d;
              my $entry = $File::Find::name;
              $entry =~ s#\./##;
              push @entries, $entry;
            }, ".");

    chdir $cwd or LOGDIE "Can't chdir to $cwd ($!)";

    return @entries;
}

###########################################
sub list_reset {
###########################################
    my($self) = @_;

    my $list_file = File::Spec->catfile($self->{objdir}, "list");
    open FILE, ">$list_file" or LOGDIE "Can't open $list_file";

    my $cwd = getcwd();
    chdir $self->{tardir} or LOGDIE "Can't chdir to $self->{tardir} ($!)";

    find(sub {
              return if -d;
              my $entry = $File::Find::name;
              $entry =~ s#\./##;
              print FILE "$entry\n";
            }, ".");

    chdir $cwd or LOGDIE "Can't chdir to $cwd ($!)";

    close FILE;

    $self->offset(0);
}

###########################################
sub list_next {
###########################################
    my($self) = @_;

    my $offset = $self->offset();

    my $list_file = File::Spec->catfile($self->{objdir}, "list");
    open FILE, "<$list_file" or LOGDIE "Can't open $list_file";
    seek FILE, $offset, 0;
    my $entry = <FILE>;

    return undef unless defined $entry;

    $self->offset(tell FILE);

    chomp $entry;
    return [$entry, File::Spec->catfile($self->{tmpdir}, $entry)];
}

###########################################
sub offset {
###########################################
    my($self, $new_offset) = @_;

    my $offset_file = File::Spec->catfile($self->{objdir}, "offset");

    if(defined $new_offset) {
        open FILE, ">$offset_file" or LOGDIE "Can't open $offset_file";
        print FILE "$new_offset\n";
        close FILE;
    }

    open FILE, "<$offset_file" or LOGDIE "Can't open $offset_file";
    my $offset = <FILE>;
    chomp $offset;
    return $offset;
    close FILE;
}

###########################################
sub tarup {
###########################################
    my($self, $tarfile, $compress) = @_;

    my $cwd = getcwd();
    chdir $self->{tardir} or LOGDIE "Can't chdir to $self->{tardir} ($!)";

    unless(File::Spec::Functions::file_name_is_absolute($tarfile)) {
        $tarfile = File::Spec::Functions::rel2abs($tarfile, $cwd);
    }

    my $compr_opt = "";
    $compr_opt = "z" if $compress;

    my $cmd = "$self->{tar} ${compr_opt}cf $tarfile .";

    my $rc = system("$cmd 2>/dev/null");

    chdir $cwd or LOGDIE "Cannot chdir to $cwd";

    return 1 if $rc == 0;

    ERROR "$cmd: $!";
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

######################################
sub object_dir {
######################################
    my($self) = @_;

    my($fh, $filename) = tempfile(CLEANUP => 1);
    $self->{objdir} = $filename;
}

1;

__END__

=head1 NAME

Archive::Tar::Wrapper - API wrapper around the 'tar' utility

=head1 SYNOPSIS

    use Archive::Tar::Wrapper;

    my $arch = Archive::Tar::Wrapper->new();

        # Open a tarball, expand it into a temporary directory
    $arch->read("archive.tgz");

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

        # Remove an entry
    $arch->remove($logic_path);

        # Find the physical location of a temporary file
    my($tmp_path) = $arch->locate($tar_path);

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
