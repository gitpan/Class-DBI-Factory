#!/usr/bin/perl

use strict;

use Term::Prompt qw(termwrap prompt);
use IO::File;
use File::Path;
use File::Ncopy;
use Template;

$|++;
my $config = {};

print termwrap("\nThis installer will attempt to create a working demonstration of Class::DBI::Factory, in the form of a (*very*) simple website.");
print "\n";

print termwrap("\n(Which won't do you much good unless you have a working apache/mod_perl installation through which to view it...)");
print "\n";

print termwrap("\nAll you have to do here is tell us what directory to install into (the default is ~/cdf/) and provide a url and port for the demo site. This script will then copy all the site components to the right place and write the appropriate configuration files.");
print "\n\n";

my $path = prompt("x", "Where shall we install site components?", '', '~/cdf/');
my $url = prompt("x", "What url shall we use for the demo?", '', 'localhost');
my $port = prompt("x", "What server port shall we use for the demo?", '', '80');

$path =~ s/\/$//;
$path =~ s/^\~/$ENV{HOME}/;
$path = "/$path" unless $path =~ /^\//;

print termwrap("\nRight. We're ready to copy site files into $path and write configuration files that will cause the cdf demo to listen for requests on $url:$port. it won't actually do anything until you Include the site configuration file in your httpd.conf, so this should be safe.");
print "\n\n";

exit unless prompt("y", "Do you want to proceed?", '', 'n');

if ( -e $path) {
    die ("'$path' exists and is not a directory") unless -d $path;
    die ("'$path' exists and is not writable") unless -r $path;
} else {
    eval { File::Path::mkpath($path); };	
    die ("create_path failed for '$path': $@") if $@;
}	

dcopy("./data", $path);
dcopy("./templates", $path);
dcopy("./lib", $path);
dcopy("./public_html", $path);

print "* creating directory $path/conf\n";
mkdir "$path/conf" || die $!;

print "* creating directory $path/scripts\n";
mkdir "$path/scripts" || die $!;

my $tt = Template->new( INCLUDE_PATH => '.' );
my $parameters = {
    demo_url => $url,
    demo_port => $port,
    demo_root => $path,
};

for ('conf/cdf.conf', 'conf/site.conf', 'scripts/startup.pl') {
    print "* processing $_\n";
    my $output;
    $tt->process($_, $parameters, \$output);
    write_file("$path/$_", $output);
}

print "*** installation complete\n";

print termwrap("\nAll that remains is to include the newly created host in your Apache configuration. Unless you've got a very esoteric setup, it's probably as simple as making sure that this line (or an equivalent) is in your httpd.conf:\n");
print termwrap("\n\tNameVirtualHost *:$port\n");
print termwrap("\nAnd adding this one beneath it:\n");
print termwrap("\n\tInclude $path/conf/site.conf\n");
print termwrap("\nRestart that Apache and you should be able to see the demo site - such as it is - at $url:$port/browse/\n");
print termwrap("\nFor more documentation, please look in the README included in the same directory as this installer, and in the POD in Class::DBI::Factory. Fuller docs for the demo will follow if anyone seems interested.\n\n");
print "\n";





sub dcopy {
    my ($from, $to) = @_;
    print "* copying $from to $to\n";
    File::NCopy->new( recursive => 1 )->copy( $from, $to ) || die $!;
}

sub write_file {
	my ($path, $content) = @_;
	my $fh = new IO::File "> $path";
	if (defined $fh) {
		print $fh $content;
		$fh->close;
	}
	print "* file written: $path\n";
}




