use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

WriteMakefile(
    NAME         => 'Class::DBI::Factory',
    VERSION_FROM => 'lib/Class/DBI/Factory.pm',
    AUTHOR       => 'William Ross (wross@cpan.org)',
    ABSTRACT     => 'Factory interface to a set of Class::DBI classes, with optional mod_perl (1 or 2) application framework.',
    PREREQ_PM    => { 
    	Class::DBI => 0.96,
    	Ima::DBI => 0.33,
    	AppConfig => 0,
    	Test::Exception => 0,
    	Email::Send => 0,
    	Error => 0,
    },
);
