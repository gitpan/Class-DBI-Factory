package Thing;

use strict;
use base qw(Class::DBI);

Thing->table('things');
Thing->columns(Primary => qw(id));
Thing->columns(Essential => qw(id title description date));

sub class_title { 'Thing' }
sub class_plural { 'Things' }
sub class_description { 'Things of one kind or another.' }
sub class_precedes { undef }

sub factory { return Class::DBI::Factory->instance('_test'); }
sub db_Main { return shift->factory->dbh; }

1;
