package My::DBI;

use strict;
use Class::DBI::Pager;
use base qw( Class::DBI::SQLite );
use vars qw( $VERSION );
$VERSION = '0.01';

# CDF->instance always returns one of a set of singletons.
# using the site id defined by a PerlSetVar directive in site.conf

sub factory {
	my $self = shift;
	return $self->{_factory} if ref $self && $self->{_factory};
	my $factory = Class::DBI::Factory->instance();
	$self->{_factory} = $factory if ref $self;
	return $factory;
}

# overriding db_Main replaces the whole Ima::DBI database-handle-caching mechanism
# in this case to ask the factory for a handle instead.

sub db_Main { return shift->factory->dbh(@_) }
sub config { return shift->factory->config(@_) }
sub tt { return shift->factory->tt(@_) }

# these are just useful sometimes, and are only included here so that they can be 
# omitted from data classes without causing any trouble.

sub class_title { '...' }
sub class_plural { '...' }
sub class_description { '...' }
sub class_precedes { return }

1;

