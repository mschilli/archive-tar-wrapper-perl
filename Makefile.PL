######################################################################
# Makefile.PL for Archive::Tar::Wrapper
# 2005, Mike Schilli <cpan@perlmeister.com>
######################################################################
use ExtUtils::MakeMaker;
WriteMakefile(
    'NAME'         => 'Archive::Tar::Wrapper',
    'VERSION_FROM' => 'lib/Archive/Tar/Wrapper.pm', # finds $VERSION
    'PREREQ_PM'    => {}, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM => 'lib/Archive/Tar/Wrapper.pm',
       AUTHOR     => 'Mike Schilli <cpan@perlmeister.com>') : ()),
);
