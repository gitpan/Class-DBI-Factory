package My::Track;

use strict;
use base qw(My::DBI);

My::Track->table('tracks');
My::Track->columns(Primary => qw(id));
My::Track->columns(Essential => qw(id title description position duration miserableness album));
My::Track->has_a( album => 'My::Album' );

sub moniker { 'track' }
sub class_title { 'Track' }
sub class_plural { 'Tracks' }
sub class_description { 'CDF is designed to be subclassed and extended. It works out of the box, but its most likely role is as a framework for something much more complex.' }

1;
