package My::DBI;
use strict;

use base qw( Class::DBI );
use vars qw( $VERSION );
$VERSION = '0.03';

# CDF->instance always returns one of a set of singletons.
# using the site id defined by a PerlSetVar directive in site.conf

sub factory {
	return Class::DBI::Factory->instance();
}

# overriding db_Main replaces the whole Ima::DBI database-handle-caching mechanism
# in this case to ask the factory for a handle instead.

sub db_Main { return shift->factory->dbh(@_) }
sub config { return shift->factory->config(@_) }
sub tt { return shift->factory->tt(@_) }

# these are useful sometimes, and are only included here so that they can be 
# omitted from data classes without causing any trouble.

sub class_title { '...' }
sub class_plural { '...' }
sub class_description { '...' }
sub is_ghost { 0 }

1;

