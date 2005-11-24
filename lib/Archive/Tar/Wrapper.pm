###########################################
# Archive::Tar::Wrapper -- 2005, Mike Schilli <cpan@perlmeister.com>
###########################################

###########################################
package Archive::Tar::Wrapper;
###########################################

use strict;
use warnings;
use File::Temp qw(tempdir);
use Log::Log4perl qw(:easy);
use File::Spec::Functions;
use File::Spec;
use File::Path;
use File::Copy;
use File::Find;
use File::Basename;
use IPC::Run qw(run);
use Cwd;

our $VERSION = "0.06";

###########################################
sub new {
###########################################
    my($class, %options) = @_;

    my $self = {
        tar               => undef,
        tmpdir            => undef,
        tar_read_options  => '',
        tar_write_options => '',
        %options,
    };

    $self->{tar}     = bin_find("tar") unless $self->{tar};

    $self->{tmpdir}  = tempdir($self->{tmpdir} ? 
                                    (DIR => $self->{tmpdir}) : ());

    $self->{tardir} = File::Spec->catfile($self->{tmpdir}, "tar");
    mkpath [$self->{tardir}], 0, 0755 or
        LOGDIE "Cannot mkpath $self->{tardir} ($!)";

    $self->{objdir} = tempdir();

    bless $self, $class;
}

###########################################
sub read {
###########################################
    my($self, $tarfile, @files) = @_;

    my $cwd = getcwd();

    unless(File::Spec::Functions::file_name_is_absolute($tarfile)) {
        $tarfile = File::Spec::Functions::rel2abs($tarfile, $cwd);
    }

    chdir $self->{tardir} or 
        LOGDIE "Cannot chdir to $self->{tardir}";

    my $compr_opt = "";
    $compr_opt = "z" if $self->is_compressed($tarfile);

    my $cmd = [$self->{tar}, "${compr_opt}xf$self->{tar_read_options}", 
               $tarfile, @files];

    DEBUG "Running @$cmd";

    my $rc = run($cmd, \my($in, $out, $err));

    if(!$rc) {
         ERROR "@$cmd failed: $err";
         chdir $cwd or LOGDIE "Cannot chdir to $cwd";
         return undef;
    }

    WARN $err if $err;

    chdir $cwd or LOGDIE "Cannot chdir to $cwd";

    return 1;
}

###########################################
sub is_compressed {
###########################################
    my($self, $tarfile) = @_;

    return 1 if $tarfile =~ /\.t?gz$/i;

        # Sloppy check for gzip files
    open FILE, "<$tarfile" or die "Cannot open $tarfile";
    binmode FILE;
    my $read = sysread(FILE, my $two, 2, 0) or die "Cannot sysread";
    close FILE;
    return 1 if 
        ord(substr($two, 0, 1)) eq 0x1F and 
        ord(substr($two, 1, 1)) eq 0x8B;

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

    return \@entries;
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
    return [$entry, File::Spec->catfile($self->{tmpdir}, "tar", $entry)];
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
sub write {
###########################################
    my($self, $tarfile, $compress) = @_;

    my $cwd = getcwd();
    chdir $self->{tardir} or LOGDIE "Can't chdir to $self->{tardir} ($!)";

    unless(File::Spec::Functions::file_name_is_absolute($tarfile)) {
        $tarfile = File::Spec::Functions::rel2abs($tarfile, $cwd);
    }

    my $compr_opt = "";
    $compr_opt = "z" if $compress;

    opendir DIR, "." or LOGDIE "Cannot open $self->{tardir}";
    my @top_entries = grep { $_ !~ /^\.\.?$/ } readdir DIR;
    closedir DIR;

    my $cmd = [$self->{tar}, "${compr_opt}cf$self->{tar_write_options}", 
               $tarfile, @top_entries];

    DEBUG "Running @$cmd";
    my $rc = run($cmd, \my($in, $out, $err));

    if(!$rc) {
         ERROR "@$cmd failed: $err";
         return undef;
    }

    WARN $err if $err;

    chdir $cwd or LOGDIE "Cannot chdir to $cwd";

    return 1;
}

###########################################
sub DESTROY {
###########################################
    my($self) = @_;

    rmtree($self->{objdir}) if exists $self->{objdir};
    rmtree($self->{tmpdir}) if exists $self->{tmpdir};
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
    $arch->read("archive.tgz");

        # Iterate over all entries in the archive
    $arch->list_reset(); # Reset Iterator
                         # Iterate through archive
    while(my $entry = $arch->list_next()) {
        my($tar_path, $phys_path) = @$entry;
        print "$tar_path\n";
    }

        # Get a huge list with all entries
    for my $entry (@{$arch->list_all()}) {
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
    $arch->write($tarfile, $compress);

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

=head1 METHODS

=over 4

=item B<my $arch = Archive::Tar::Wrapper-E<gt>new()>

Constructor for the tar wrapper class. Finds the C<tar> executable
by searching C<PATH> and returning the first hit. In case you want
to use a different tar executable, you can specify it as a parameter:

    my $arch = Archive::Tar::Wrapper->new(tar => '/path/to/tar');

Since C<Archive::Tar::Wrapper> creates temporary directories to store
tar data, the location of the temporary directory can be specified:

    my $arch = Archive::Tar::Wrapper->new(tmpdir => '/path/to/tmpdir');

Additional options can be passed to the C<tar> command by using the
C<tar_read_options> and C<tar_write_options> parameters. Example:

     my $arch = Archive::Tar::Wrapper->new(
                   tar_read_options => "p"
                );

will use C<tar xfp archive.tgz> to extract the tarball instead of just
C<tar xf archive.tgz>.

=item B<$arch-E<gt>read("archive.tgz")>

C<read()> opens the given tarball, expands it into a temporary directory
and returns 1 on success und C<undef> on failure. 
The temporary directory holding the tar data gets cleaned up when C<$arch>
goes out of scope.

C<read> handles both compressed and uncompressed files. To find out if
a file is compressed or uncompressed, it tries to guess by extension,
then by checking the first couple of bytes in the tarfile.

If only a limited number of files is needed from a tarball, they
can be specified after the tarball name:

    $arch->read("archive.tgz", "path/file.dat", "path/sub/another.txt");

The file names are passed unmodified to the C<tar> command, make sure
that the file paths match exactly what's in the tarball, otherwise
C<read()> will fail.

=item B<$arch-E<gt>list_reset()>

Resets the list iterator. To be used before the first call to
B<$arch->list_next()>.

=item B<my($tar_path, $phys_path) = $arch-E<gt>list_next()>

Returns the next item in the tarfile. It returns a list of two scalars:
the relative path of the item in the tarfile and the physical path
to the unpacked file or directory on disk. To determine if the item
is a file or directory, use perl's C<-f> and C<-d> operators on the
physical path.

=item B<my $items = $arch-E<gt>list_all()>

Returns a reference to a (possibly huge) array of items in the
tarfile. Each item is a reference to an array, containing two
elements: the relative path of the item in the tarfile and the
physical path to the unpacked file or directory on disk.

To iterate over the list, the following construct can be used:

        # Get a huge list with all entries
    for my $entry (@{$arch->list_all()}) {
        my($tar_path, $real_path) = @$entry;
        print "Tarpath: $tar_path Tempfile: $real_path\n";
    }

If the list of items in the tarfile is big, use C<list_reset()> and
C<list_next()> instead of C<list_all>.

=item B<$arch-E<gt>add($logic_path, $file_or_stringref)>

Add a new file to the tarball. C<$logic_path> is the virtual path
of the file within the tarball. C<$file_or_stringref> is either
a scalar, in which case it holds the physical path of a file
on disk to be transferred (i.e. copied) to the tarball. Or it is
a reference to a scalar, in which case its content is interpreted
to be the data of the file.

=item B<$arch-E<gt>remove($logic_path)>

Removes a file from the tarball. C<$logic_path> is the virtual path
of the file within the tarball.

=item B<$arch-E<gt>locate($logic_path)>

Finds the physical location of a file, specified by C<$logic_path>, which
is the virtual path of the file within the tarball. Returns a path to 
the temporary file C<Archive::Tar::Wrapper> created to manipulate the
tarball on disk.

=item B<$arch-E<gt>write($tarfile, $compress)>

Write out the tarball by tarring up all temporary files and directories
and store it in C<$tarfile> on disk. If C<$compress> holds a true value,
compression is used.

=back

=head1 KNOWN LIMITATIONS

=over 4

=item *

Currently, only C<tar> programs supporting the C<z> option (for 
compressing/decompressing) are supported. Future version will use
C<gzip> alternatively.

=item *

Currently, you can't add empty directories to a tarball directly.
You could add a temporary file within a directory, and then
C<remove()> the file.

=item *

If you delete a file, the empty directories it was located in 
stay in the tarball. You could try to C<locate()> them and delete
them. This will be fixed, though.

=item *

Filenames containing newlines are causing problems with the list
iterators. To be fixed.

=back

=head1 LEGALESE

Copyright 2005 by Mike Schilli, all rights reserved.
This program is free software, you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 AUTHOR

2005, Mike Schilli <cpan@perlmeister.com>
