use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

WriteMakefile(
    NAME         => 'Class::DBI::Factory',
    VERSION_FROM => 'lib/Class/DBI/Factory.pm',
    AUTHOR       => 'william ross (wross@cpan.org)',
    ABSTRACT     => 'Factory access to a set of Class::DBI classes.',
    PREREQ_PM    => { 
    	Class::DBI => 0.92,
    	Data::Dumper => 0,
    	Class::DBI::FromCGI => 0,
    	AppConfig => 0,
    },
);
