use strict;
use lib qw( ../lib ./test );
use DBI;
use Cwd;
use Test::More;
use Test::Exception;
use Apache::Constants qw(:response);

BEGIN {
    eval "use DBD::SQLite";
    plan $@ ? (skip_all => 'Tests require DBD::SQLite') : (tests => 39);
    use_ok('Class::DBI::Factory');
    use_ok('Class::DBI::Factory::Config');
    use_ok('Class::DBI::Factory::Handler');
    use_ok('Class::DBI::Factory::List');
    use_ok('Class::DBI::Factory::Ghost');
    use_ok('Class::DBI::Factory::Exception', qw(:try));
}

my $here = cwd;
my $now = scalar time;

$ENV{_SITE_ID} = '_test';
$ENV{_CDF_CONFIG} = "$here/test/cdf.conf";

my $factory = Class::DBI::Factory->instance;

ok( $factory, 'factory object configured and built' );

print "\nCONFIG\n\n";

isa_ok($factory->config, 'Class::DBI::Factory::Config', 'CDFC properly loaded:');
isa_ok($factory->config->{_ac}, 'AppConfig', 'CDFC AppConfig:');
is($factory->config->get('refresh_interval'), '3600', 'config values');
is($factory->config->get('template_root'), '<undef>', 'config non-values');



print "\nFACTORY\n\n";

my $dsn = "dbi:SQLite:dbname=cdftest.db";
my $config = set_up_database($dsn);
$factory->set_db($config);

ok( $factory->dbh && $factory->dbh->ping, 'connected to ' . $config->{db_type});

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

my $dbh = $factory->dbh;
isa_ok( $dbh, "DBIx::ContextualFetch::db", 'factory->dbh' );

throws_ok { $factory->load_class('No::Chance::Boyo'); } 'Exception::SERVER_ERROR', 'SERVER_ERROR exception thrown by bad load_class call';
throws_ok { $factory->fugeddaboutit('thing', 1); } 'Exception::SERVER_ERROR', 'SERVER_ERROR exception thrown by AUTOLOAD with disallowed method name';

SKIP: {
    eval "require Template;";
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

    $template = "[% IF 1 %][% factory.retrieve('thing', " . $thing->id . ").title %]";
    $html = '';
    throws_ok { $factory->process(\$template, { factory => $factory } , \$html); } 'Exception::SERVER_ERROR', 'SERVER_ERROR exception thrown by broken template';
}

print "\nHANDLER\n\n";

print "Handler tests would require Apache::Test and Apache::MM and that seems like overkill here. Do get in touch if you disagree (or would like to write some :)\n";

print "\nLIST\n\n";

my $list = $factory->list('thing', date => $now, sortby => 'title');

ok( $list, 'list construction');

my $total = $list->total;

is( $total, 4, 'list size');

my @contents = $list->contents;

is( $contents[0]->title, 'Bread board', 'list ordering');

my $other_list = $factory->list_from($iterator);
my $count = $other_list->total;

is( $count, 2, 'list from iterator');

throws_ok { $factory->list('anything'); } 'Exception::NOT_FOUND', 'NOT_FOUND exception thrown by list call with non-moniker';
throws_ok { $factory->list_from(); } 'Exception::GLITCH', 'GLITCH exception thrown by bad list_from call';

print "\nGHOST\n\n";

my $ghost = $factory->ghost_object('thing', {
    title => 'testy',
    description => 'wooooo',
});

ok ($ghost, 'ghost object created');
is ($ghost->is_ghost, '1', 'ghost knows it\'s a ghost');
is ($ghost->type, 'thing', 'ghost linked to correct data class');
ok ($ghost->find_column('title'), 'ghost finds correct columns');
is ($ghost->title, 'testy', 'ghost holds column values');
isa_ok ($ghost->make, 'Thing', 'ghost make() object');

print "\nEXCEPTIONS\n\n";

# Handler tests mostly relate to exceptions

throws_ok { test_404(); } 'Exception::NOT_FOUND', 'NOT_FOUND exception thrown';

try {
    test_404();
}
catch Exception::NOT_FOUND with {
    my $ex = shift;
    is ($ex->view, 'notfound', 'exception displays correct view');
    is ($ex->text, 'Just testing', 'exception returns correct text');
    is ($ex->stringify, 'Just testing', 'exception stringifies politely');
}
otherwise {
    print "bad!";
};

sub test_404 {
    throw Exception::NOT_FOUND(
        -text => "Just testing", 
        -view=>'404',
    );
}

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


