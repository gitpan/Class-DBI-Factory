use strict;
use lib qw( ../lib ./test );

use Term::Prompt qw(termwrap prompt);
use DBI;
use Cwd;
use Test::More tests => 13;

BEGIN { use_ok('Class::DBI::Factory'); }

my $here = cwd;
my $now = scalar time;
my $factory = Class::DBI::Factory->instance('_test', "$here/test/cdf.conf");

ok( $factory, 'factory object configured and built' );

my $config = set_up_database();
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

my $pager = $factory->pager('thing', 2);
my @things = $pager->retrieve_all;

is( $pager->last_page, 2, 'pager construction');

$factory->debug_level(1);

is( $factory->debug_level, 1, 'debug level set');

$factory->debug(1, 'this is a debugging warning. you should only see one.');
$factory->debug(2, 'this is a debugging warning. you should only see one.');
$factory->debug_level(0);
$factory->debug(1, 'this is a debugging warning. you should only see one.');



END {
    undef $factory;
    print "\nTest database deleted.\n\n" if $config->{db_type} eq 'SQLite' && unlink "${here}/cdftest.db";
}








sub set_up_database {
	my $dbh;
	eval { $dbh = DBI->connect("dbi:SQLite:dbname=cdftest.db","",""); };

	unless ($@) {
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
	
	print termwrap("\nSQLite doesn't seem to be installed. We can use mysql instead, if you can supply the name of a test database and a username and password that will give us access to it.");
	print "\n\n";
	
	my $config = { db_type => 'mysql', db_host => 'localhost' };
	my $connected = 0;
	
	until($connected) {
		$config->{db_port} = prompt("x", "mysql port", 'default is very likely', $config->{db_port} || '3306');
		$config->{db_name} = prompt("x", "database name?", '', $config->{db_name} || 'cdftest');
		$config->{db_username} = prompt("x", "database user name?", '', $config->{db_username} || 'root');
		$config->{db_password} = prompt("x", $config->{db_username} . "'s mysql password?", '! for blank', $config->{db_password});
		$config->{db_password} = '' if $config->{db_password} eq '!';
		my $dsn = "DBI:$$config{db_type}:database=$$config{db_name};host=localhost;port=$$config{db_port}";

		eval{ $dbh = DBI->connect($dsn, $config->{db_username}, $config->{db_password}, {'RaiseError' => 1}); };

		if ($@) {
			print termwrap("\nConnecting to database failed, with the message:\n\n$@\nPlease check and try again.");
			print "\n\n";
		} else {
			$connected = 1;
		}
	}
	
 	my $q = $dbh->do('show tables');
	my $t = $dbh->do('describe things') unless $q eq '0E0';
	$dbh->do('create table things (id int not null auto_increment, title varchar(255), description text,  date int, primary key (id));') unless $t;
	return $config;
}


