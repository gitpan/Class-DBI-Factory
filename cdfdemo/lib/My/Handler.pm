package My::Handler;
use strict;
use base qw( Class::DBI::Factory::Handler );
use Data::Dumper;

use vars qw( $VERSION );
$VERSION = '0.02';

sub task_sequence {
    return qw(read_input do_op return_output);
}

1;