use strict;
use lib qw( ../lib ./test );
use DBI;
use Cwd;
use Test::More;

BEGIN {
    eval "use DBD::SQLite";
    plan $@ ? (skip_all => 'Tests require DBD::SQLite') : (tests => 19);
    use_ok('Class::DBI::Factory');
}

my $here = cwd;
my $now = scalar time;
my $factory = Class::DBI::Factory->instance('_test', "$here/test/cdf.conf");

ok( $factory, 'factory object configured and built' );

my $dsn = "dbi:SQLite:dbname=cdftest.db";
my $config = set_up_database($dsn);
$factory->set_db($config);

ok( $factory->dbh, 'connected to ' . $config->{db_type});

my $thing = $factory->create(thing => {
	title => 'Wellington boot remover',
	description => 'Inclined metal foot rest with a notch at the far end ready to receive the heel of a wellington boot and hold it in position while the foot is removed from it.',
	date => $now,
});

is( $thing->title, 'Wellington boot remover', 'factory->create' );

$factory->create(thing => {
	title => 'Ironing Board',
	description => 'Cloth-covered surface of adjustable height shaped so as to provide a suitable surface for the application of hot iron to wrinkled clothing.',
	date => $now,
});

$factory->create(thing => {
	title => 'Spice rack',
	description => 'Small, two-tier construction of warped pine shelves above which wonky dowels attempt to prevent the toppling of each row of tall, thin spice jars designed to contain as little pulverised spice as possible while still appearing large and full.',
	date => $now,
});

$factory->create(thing => {
	title => 'Bread board',
	description => 'Flat, usually wooden surface which collects crumbs and accepts gouges during the slicing of bread.',
	date => $now,
});

my $id = $thing->id;
my $rething = $factory->retrieve('thing', $id);

is( $thing, $rething, 'factory->retrieve' );

my $iterator = $factory->search_like('thing', title => '%board');

is( $iterator->count, 2, 'factory->search_like');

my $count = $factory->count('thing');

is( $count, 4, 'factory->count');

my $list = $factory->list('thing', date => $now, sortby => 'title');

ok( $list, 'list construction');

my $total = $list->total;

is( $total, 4, 'list size');

my @contents = $list->contents;

is( $contents[0]->title, 'Bread board', 'list ordering');

my $other_list = $factory->list_from($iterator);
my $count = $other_list->total;

is( $count, 2, 'list from iterator');

SKIP: {
    eval { require Class::DBI::Pager };
    skip "Class::DBI::Pager not installed", 1 if $@;
    my $pager = $factory->pager('thing', 2);
    my @things = $pager->retrieve_all;
    is( $pager->last_page, 2, 'pager construction');
}

my $dbh = $factory->dbh;
isa_ok( $dbh, "Ima::DBI::db", 'factory->dbh' );

SKIP: {
    eval { require Template };
    skip "Template not installed", 3 if $@;
    
    my $tt = $factory->tt;
    isa_ok( $tt, "Template", 'factory->template' );
    
    my $html;
    my $template = '[% test %]';
    $factory->process(\$template, { test => 'pass' } , \$html);
    is( $html, 'pass', 'factory->parse');

    $template = "[% factory.retrieve('thing', " . $thing->id . ").title %]";
    $html = '';
    $factory->process(\$template, { factory => $factory } , \$html);
    is( $html, $thing->title, 'template calls to factory methods');
}

$factory->debug_level(1);

is( $factory->debug_level, 1, 'debug level set');

is_deeply( $factory->debug(1, ' '), (" \n"), 'message over debug threshold shown');

is( $factory->debug(2, ' '), undef, 'message under debug threshold muted');



END {
    undef $factory;
    print "\nTest database deleted.\n\n" if $config->{db_type} eq 'SQLite' && unlink "${here}/cdftest.db";
}

sub set_up_database {
    my $dsn = shift;
	my $dbh;
	eval { $dbh = DBI->connect($dsn,"",""); };
    die "connecting to (and creating) SQLite database './cdftest.db' failed: $!" if $@;
    $dbh->do('create table things (id integer primary key, title varchar(255), description text, date int);');
    return {
        db_type => 'SQLite',
        db_name => 'cdftest.db',
        db_username => '',
        db_password => '',
        db_host => '',
        db_port => '',
    };
} 


