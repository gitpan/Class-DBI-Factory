package My::Genre;

use strict;
use base qw(My::DBI);

My::Genre->table('genres');
My::Genre->columns(Primary => qw(id));
My::Genre->columns(Essential => qw(id title description));
My::Genre->has_many( albums => 'My::Album' );

sub moniker { 'genre' }
sub class_title { 'Genre' }
sub class_plural { 'Genres' }
sub class_description { 'The Genre class' }

1;
