package My::Handler;
use strict;
use base qw( Class::DBI::Factory::Handler );

use vars qw( $VERSION );
$VERSION = '0.02';

# your session management goes here...

sub task_sequence { qw(check_permission adjust_input do_op return_output) };
sub check_permission { 1 };

1;