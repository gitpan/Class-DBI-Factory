package Class::DBI::Factory::Config;

use strict;
use AppConfig qw(:argcount);

use vars qw( $VERSION $AUTOLOAD );

$VERSION = '0.75';

=head1 NAME

Class::DBI::Factory::Config - an AppConfig-based configuration mechanism for Class::DBI::Factory

=head1 SYNOPSIS
    
	$config = Class::DBI::Factory::Config->new({
		-file => 
	});

	my @classes = $config->classes;
	
	my $tdir = $config->get('template_dir');
	
	my @referers = $config->get('allowed_referer');

=head1 INTRODUCTION

This is just a thin bit of glue that sits between AppConfig and Class::DBI::Factory. Its main purpose is to define the skeleton of parameters that AppConfig uses, but it also provides some useful shorthands for accessing commonly-needed parameters.

In the normal course of events you will never need to work with or subclass this module, or indeed know anything about it. The factory class will take care of constructing and maintaining its own configuration object and following the instructions contained therein.

AppConfig was chosen primarily because it is used by the Template Toolkit and therefore already loaded by my applications. If you're not using TT you may prefer to substitute some other configuration mechanism. You can also subclass more selectively, of course.

=head1 DATA SKELETON

The skeleton defined by this module is used by AppConfig to parse configuration files. It details the variables that we are expecting and what to do with each one. Simple variables don't need to be mentioned, but anything with multiple values or more than one level should be prescribed here.

=head2 skeleton()

This method returns a hashref that describes the configuration data it expects to encounter. You can refer to the documentation for AppConfig for details of how this works, but for most purposes you should only need to work with the list_parameters, hash_parameters and default_values methods.

You can subclass the whole skeleton() method, but for most purposes it will probably suffice to override some of the methods it calls:

=head2 list_parameters

Returns a list of parameter names that should be handled as lists of values rather than as simple scalars.

=head2 extra_list_parameters

This is included for convenience: if you want to extend the standard list of list parameters, rather than replacing it, then override this method and return your additions as a list of parameter names.

=head2 hash_parameters

Returns a list of parameter names that should be handled as hashes - ie the configuration files will specify both key and value. 

=head2 extra_hash_parameters

This is included for convenience: if you want to extend the standard list of hash parameters, rather than replacing it, then override this method and return your additions as a list of parameter names. 

(At the moment the standard list is empty, but that may not be true for future versions, so it's safer to use the extra methods.)

=head2 default_values

Returns a hash of (parameter name => value), in which the value may be simple, a list or a hash. Its treatment will depend on what your data skeleton specifies for that parameter.

=head2 extra_defaults

Another shortcut: returns a hash of name => default value which is appended to the usual set of defaults, if you just want to add a couple rather than specifying a whole new set.

=cut

sub skeleton {
	my $self = shift;
	my $construction = {
		CREATE => 1,
		CASE => 0,
		GLOBAL => { 
			DEFAULT  => "<undef>",
			ARGCOUNT => ARGCOUNT_ONE,
		},
	};
	my %definitions;
	my %defaults = $self->default_values;
	$definitions{$_} = { ARGCOUNT => ARGCOUNT_LIST } for $self->list_parameters;
	$definitions{$_} = { ARGCOUNT => ARGCOUNT_HASH } for $self->hash_parameters;
	$definitions{$_}->{DEFAULT} = $defaults{$_} for keys %defaults;
	return ($construction, %definitions);
}

sub list_parameters {
	my $self = shift;
	my @param = $self->extra_list_parameters;
	push @param, qw(include_file use_package package class template_dir template_subdir module_dir module_subdir);
	return @param;
}

sub hash_parameters {
	my $self = shift;
	return $self->extra_hash_parameters;
}

sub default_values {
	my $self = shift;
	my %and_from_subclass = $self->extra_defaults;
	my %defaults = (
		db_type => 'SQLite',
		smtp_server => 'localhost',
		db_autocommit => 1,
		db_taint => 0,
		db_raiseerror => 0,
		db_showerrorstatement => 1,
		db_dsn => undef,
		db_host => undef,
		db_name => undef,
		db_servername => undef,
		db_port => undef,
		debug_level => 0,
		%and_from_subclass
	);
}

sub extra_list_parameters {
	return ();
}

sub extra_hash_parameters {
	return ();
}

sub extra_defaults {
	return ();
}

=head1 INTERFACE

If you decide to replace this module with one of your own, all you have to do is provide these methods:

=head2 new()

  $config = Class::DBI::Factory::Config->new('/path/to/file');

Should optionally take a file path parameter and pass it to file(): otherwise, just creates an empty configuration object ready for use but not yet populated.

=head2 file()

  $config->file('/path/to/file', '/path/to/otherfile');
  
Reads configuration files from the supplied addresses, and stores the addresses in case of a later refresh() or rebuild().

=head2 refresh()

  $config->refresh();
  $config->refresh('/path/to/file');

Checks the modification date for each of the configuration files that have been read, and any that have been modified are read again. 

By default it will revisit the whole set of read configuration files, but if you supply a list of files, refresh() will confine itself to looking at the intersection of your list and the list of files already read. Use $config->file to read a new file, in other words: refresh only works on files that have already been read at least once.

Note that you can't eliminate a variable this way (all you can do is make it untrue), and you can't remove an entry from a list or hash parameter: in that case you need to start again from scratch by calling redo().

=head2 rebuild()

This will drop all configuration information and start again by re-reading all the configuration files. Any other changes your application has made, eg by setting values directly, will be lost.

=cut

sub new {
	my ($class, $param) = @_;
	my $appconfig = AppConfig->new( $class->skeleton );
	$appconfig->file( delete($param->{file}) ) if ($param->{file});
	$appconfig->set( %$param ) if %$param;
	my $self = bless {
		_ac => $appconfig,
		_file_read => {},
		_files => [],
	}, $class;
	return $self;
}

sub file {
	my ($self, @files) = @_;
	my $time = scalar time;
	for (@files) {
		push @{ $self->{_files} } , $_;
		$self->{_file_read}->{$_} = scalar time;
		$self->{_ac}->file($_) || next;
	}
}

sub refresh {
	my $self = shift;
	my @files = @_ || $self->files;
	for (@files) {
		next unless -e $_;
		next unless -f $_;
		my @stat = stat($_);
		next unless $stat[9] > $self->{_file_read}->{$_};
		warn "!!! re-parsing $_\n";
		$self->file($_);
	}
}

sub rebuild {
	my $self = shift;
	delete $self->{_ac};
	$self->{_ac} = AppConfig->new( $self->skeleton );
	$self->{_file_read}->{$_} = 0 for keys %{ $self->{_file_read} };
	$self->refresh;
}

sub files {
    return @{ shift->{_files} };
}

=head2 get()

  $config->get('smtp_server');
  
Gets the named value.

=head2 set()

  $config->set(smtp_server => 'localhost');
  
Sets the named value.

=head2 all()

returns a simple list of all the variable names held.

=cut

sub get {
	return shift->{_ac}->get(@_);
}

sub set {
	return shift->{_ac}->set(@_);
}

sub all {
	return shift->{_ac}->varlist;
}

=head2 template_path()

Returns a reference to an array of directories in which to look for TT templates.

These can be defined in two ways: directly, with a 'template_dir' parameter, or in two stages, with a 'template_root' and one or more 'template_subdir' parameters.

Sequence is important, since the first encountered instance of a template will be used. The order of definition is preserved (so site file > package file > global file), except that all template_dir values are given priority over all template_subdir values: the former would normally be defined by a standard package, the latter by local site configuration.

=cut

sub template_path {
    my $self = shift;
    my $tdirs = $self->get('template_dir');
    my $troot = $self->get('template_root');
    my $tsubdirs = $self->get('template_subdir');
    
    my @path = @$tdirs;
    push @path, map { "$troot/$_" } reverse @$tsubdirs if $troot;
    return \@path;
}

=head2 packages()

A shorthand for $config->get('use_package'): returns a list. Note that this is the set of packages that are *supposed* to be loaded. Call using($name) to find out whether a particular package actually loaded properly.

=head2 package_loaded()

Returns true if the named package was successfully loaded at startup.

=head2 classes()

A shorthand for $config->get('class'): returns a list.

=cut

sub packages {
	return shift->get('use_package');
}

sub package_loaded {
    my ($self, $package) = @_;
    my %packages = map { $_ => 1 } @{ $self->get('package') };
    return $packages{$package};
}

sub classes {
	return shift->get('class');
}

sub AUTOLOAD {
	my $self = shift;
	my $method_name = $AUTOLOAD;
	$method_name =~ s/.*://;
    return if $method_name eq 'DESTROY';
    return unless $self->{_ac};
	return $self->{_ac}->$method_name(@_);
}

=head1 SEE ALSO

L<AppConfig> L<Class::DBI> L<Class::DBI::Factory> L<Class::DBI::Factory::Handler> L<Class::DBI::Factory::List>

=head1 AUTHOR

William Ross, wross@cpan.org

=head1 COPYRIGHT

Copyright 2001-4 William Ross, spanner ltd.

This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut

1;
