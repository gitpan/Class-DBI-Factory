package My::Artist;

use strict;
use base qw(My::DBI);

My::Artist->table('artists');
My::Artist->columns(Primary => qw(id));
My::Artist->columns(Essential => qw(id title description));
My::Artist->has_many( albums => 'My::Album' );

sub class_title { 'Artist' }
sub class_plural { 'Artists' }
sub class_description { 'CDF comes with readymade mod_perl handler, configuration and pagination classes.' }

1;
