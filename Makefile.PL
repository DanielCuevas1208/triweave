use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME             => 'Triweave',
    VERSION_FROM     => 'lib/Triweave.pm',
    ABSTRACT         => 'Three-way text merging with word-level conflict handling',
    AUTHOR           => 'Triweave contributors',
    LICENSE          => 'perl',
    MIN_PERL_VERSION => '5.030',
    EXE_FILES        => ['bin/triweave'],
    PREREQ_PM        => {},
    TEST_REQUIRES    => { 'Test::More' => '0' },
);