package My::Album;

use strict;
use base qw(My::DBI);

My::Album->table('albums');
My::Album->columns(Primary => qw(id));
My::Album->columns(Essential => qw(id title description genre artist));

My::Album->has_a( artist => 'My::Artist' );
My::Album->has_a( genre => 'My::Genre' );
My::Album->has_many( tracks => 'My::Track', {order_by => 'position'} );

sub class_title { 'Album' }
sub class_plural { 'Albums' }
sub class_description { 'The album class.' }

1;
