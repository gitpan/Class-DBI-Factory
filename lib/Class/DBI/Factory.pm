package Class::DBI::Factory;
use strict;

use Class::DBI::Factory::Exception qw(:try);
use Ima::DBI;
use Email::Send;
use Data::Dumper;

use vars qw( $VERSION $AUTOLOAD $_factories );

$VERSION = '0.81';
$_factories = {};

=head1 NAME

Class::DBI::Factory - a factory interface to a set of Class::DBI classes

=head1 SYNOPSIS

    my $factory = Class::DBI::Factory->new( '/path/to/config.file');
    
    my $factory = Class::DBI::Factory->instance($site_id, '/path/to/config.file');
    
    $ENV{_SITE_ID} = 'foo';
    $ENV{_CONFIG_DIR} = '/home/bar/conf/';
    my $factory = Class::DBI::Factory->instance();
    
    then
    
    my $cd = $factory->retrieve('cd', 2);
    my $track = $factory->random('track');
    my $artists = $factory->search_like('artist', title => 'Velvet%');
    my $new_album = $factory->create('album', { 
        artist => $artist,
        title => 'string',
        ...
    });
    
    my @columns = $factory->columns('cd', 'All');
    my @input = grep { $factory->find_column('cd', $_) } $query->param;
    
    my $list = $factory->list('cd',
        genre => $genre,
        year => 1975,
        start_at => 0,
        per_page => 20,
        sort_by => 'title',
        sort_order => 'asc',
    );
    
    my $cd_pager = $factory->pager('cd');
    
    my $iterator = $factory->retrieve('artist', 2)->albums;
    my $tracks = $factory->list_from( $iterator );

=head1 INTRODUCTION

A Class::DBI::Factory object provides a single point of access to a set of Class::DBI classes. You can use it as a quick and tidy way to access class methods or as a full framework for a mod_perl-based web application.

For anyone unfamiliar with the pattern, a Factory* is basically just a versatile constructor: its role is to build and return objects of a variety of classes in response to a variety of requests. This pattern is commonly used as a way of hiding complex or evolving sets of classes behind a single consistent interface, and if your Class::DBI applications are anything like as sprawling as mine, that will immediately sound like a good idea.

I<* Strictly speaking this is probably an Abstract Factory, since a lot of Class::DBI classes are themselves factory-like, but I'm not going to pretend I really know what the difference is.>

In a Class::DBI context this approach has four immediate benefits:

=over
 
=item *
It defines and holds together a set of Class::DBI data classes
 
=item *
It provides an easy interface to cdbi class methods

=item *
It offers an easy central repository for expensive objects

=item *
It makes data class re-use much easier in a persistent environment

=back

The Factory is most likely to be employed as the hub of a Class::DBI-based web application, supplying objects, information and services to handlers, templates and back-end processes as required, so it includes a few key services that make Class::DBI much easier to use under mod_perl (see L</"PERSISTENCE"> below), and comes with three helpful base classes designed with that role in mind:

=head2 Class::DBI::Factory::List

is a general-purpose list handler that can transparently execute and paginate queries with select, order and limit clauses. If it works with anything but mysql at the moment then that's an accident, but I fondly imagine that it will become as platform-independent as Class::DBI, at least.

=head2 Class::DBI::Factory::Config

uses AppConfig to provide moderately complex configuration services with minimal effort. There is provision for a package-based pseudo-plugin architecture.

=head2 Class::DBI::Factory::Handler

provides a ready-made mod_perl handler. If you're happy to use the Template Toolkit then you should find it works in a limited way out of the box: a very small amount of subclassing is required to work with other templating systems.

You should be able to use any templating engine and any database, and to move freely among platforms, but I must confess that I have only ever used CDF with the Template Toolkit, mysql and SQLite. There may well be incompatibilities that I'm unaware of.

All of these modules are written with the expectation that they will be subclassed rather than used directly (see L</"SUBCLASSING">, below), so there is a proliferation of little methods and a B<lot> of method pod.

=head1 PERSISTENCE

In a persistent environment like mod_perl, you wouldn't want to build a bulky, expensive factory object for every request. CDF factories are designed to remain in memory, furnishing short-lived request handlers and data objects with whatever objects and lists they need. 

The instance mechanism allows for several factories to coexist. Under mod_perl it would be normal to have a persistent factory for each each instance of your application (usually that would mean for each site). All you have to do is call CDF->instance() instead of CDF->new().

  CDF->instance($site_id);
  
will always return the right factory object for each C<$site_id>, constructing it if necessary. The C<$site_id> can also be supplied as an environment variable, given to the constructor or just left to the constructor to work out. If no id can be found, then C<instance> will revert to a singleton constructor and return the same factory to every request.

This persistence between requests makes the factory an excellent place to store expensive objects, especially if they must be built separately for each of your sites. As standard each factory object is ready to create and hold a single database handle and a single Template object, both of which are constructed with parameters from the factory's configuration files and made available to handlers and data classes.

With a small tweak to your data classes, this will also allow you to run several instances of the same application side by side, each instance using a different database and configuration files, and sharing templates or not as you dictate. All you have to do is override C<db_Main> with a method that retrieves the factory's database handle instead of the class handle. See L</"YOUR DATA CLASSES"> below for details.

Note that this object-sharing does not extend between Apache children, or any other processes. In the typical setup there is actually one factory object per site B<per process>.

=head1 MINIMAL EXAMPLE

As a starting point it is quite possible to use Class::DBI::Factory just as it comes. If you have the template toolkit installed, then this bit of configuration is all that's required to make your cd collection browseable:

in your (virtual)host definition:
  
  PerlSetEnv _SITE_TITLE my.site.com
  PerlSetEnv _CONFIG_DIR /path/to/files/
  
  <Location "/demo">
    SetHandler    perl-script
    PerlHandler   Class::DBI::Factory::Handler
  </Location>
  
And in /path/to/files/cdf.conf
  
  db_type = mysql
  db_name = something
  db_username = someone
  db_password = something
  db_host = localhost
  db_port = 3306
  
  template_path = /path/to/dir
  module_path = /path/to/dir
  template_suffix = 'html'
  
  class = My::CD
  class = My::Artist
  class = My::Album
  class = My::Genre

Though you would also need three templates in the directory you have put in template_path: one.html, many.html and front.html.

There's a sample application included with this distribution. It isn't big or clever, but it shows the basic principles at work and you might even want to use it as a starting point. It uses SQLite and TT, and should be very easy to set up provided you have a mod_perl-enabled Apache around. It's in C<./demo> and comes with a dim but enthusiastic installer and some B<very> basic documentation.

=head1 SUBCLASSING

In serious use, Class::DBI::Factory and all its helper modules will be subclassed and extended. The methods you will want to look at first are probably:

  CDF::Handler::build_page()
  CDF::Handler::factory_class()
  
  CDF::pre_require()
  CDF::post_require()
  CDF::extra_methods()
  CDF::pager_class()
  CDF::list_class()
  
  CDF::Config::skeleton()
  CDF::Config::list_parameters()
  CDF::Config::hash_parameters()
  CDF::Config::default_values()

All of which have been separated out and surrounded with ancillary methods in order to facilitate selective replacement of components. See the method descriptions below, and in the helper modules, for more detail.

=head1 YOUR DATA CLASSES

You will, before very long, want to make the factory available to your data classes, which in turn gives them access to your templating engine, configuration settings and factory utilities.

In a non-persistent application, where you don't have to worry about namespaces too much, you can just store the factory object in a class variable or temp column. The simplest way is to create a get&set method in your subclass of Class::DBI, then override the C<CDF::post_require()> method with something like this:

  sub post_require {
    my ($moniker, $class) = @_;
    $class->factory($self);
  }

However, this isn't really recommended because it won't work in a persistent environment: holding the factory as class data means it is shared between all running instances of the application (within the same process). If you want to publish two sites from different databases, and with different templates, then you need to hold a separate factory object for each site.

CDF's persistence mechanism provides a simple solution. All you need to add to your data classes is this:

  sub factory { return Class::DBI::Factory->instance; }	
  sub db_Main { return shift->factory->dbh(@_) }

(Except that the factory method is more likely to call Your::Subclass::Of::CDF)

and optionally:

  sub config { return shift->factory->config(@_) }
  sub tt { return shift->factory->tt(@_) }

The C<db_Main> method is essential: it overrides the standard L<Class::DBI>/L<Ima::DBI> handle storage mechanism with a factory one that doesn't assume that a class will always want to access the same database table. 

=head1 CONFIGURATION

Each factory object is directed by a set of configuration files. They are read in the following order, and any which are not specified or do not exist are just ignored:

=over

=item 1. 
global configuration file (server-wide and applied to all sites)

=item 2. 
local site package-selection file

=item 3. 
package configuration files (server-wide but invoked selectively by sites)

=item 4. 
local site configuration file

=item 5. 
any files specified by include_file directives

=back

The addresses of those files are normally supplied by host-specific environment variables, which are defined by C<PerlSetEnv> directives in the (virtual)host definition. You can override that mechanism by subclassing any of these methods:

=head2 site_id()

Used by the C<instance> method to identify the site and return the corresponding factory object. By default, just returns C<$ENV{_SITE_TITLE}>.

=head2 config_dir()

Should return the full path to the directory containing configuration files for this instance of the application. By default, returns C<$ENV{_CONFIG_DIR}>.

It is hoped that at least two conventionally-named files exist within that directory. You can override the package_file_name and config_file_name methods to dictate what those filenames should be.

=head2 package_file_name()

Returns the name of the package file that we should look for in C<config_dir>.

=head2 config_file_name()

Returns the name of the configuration file that we should look for in C<config_dir>.

=head2 site_config_file() site_package_file() global_config_file()

...each return the path to the relevant configuration file, if the file exists and is readable. The global config file is not assumed to be in C<config_dir>: we will use C<$ENV{_CDF_CONFIG}>.

Any of these methods can return undef if that file is not needed.

=cut

sub site_id { $ENV{'_SITE_TITLE'} }
sub config_dir { $ENV{'_CONFIG_DIR'} }
sub package_file_name { 'packages.conf' }
sub config_file_name { 'cdf.conf' }

sub global_config_file { 
    return _if_file_exists($ENV{'_CDF_CONFIG'});
}

sub site_package_file { 
    my $self = shift;
    my $file = $self->config_dir . '/' . $self->package_file_name;
    return _if_file_exists($file);
}

sub site_config_file { 
    my $self = shift;
    my $file = $self->config_dir . '/' . $self->config_file_name;
    return _if_file_exists($file);
}

sub _if_file_exists {
    my $f = shift;
    $f =~ s/\/+/\//g;
    return $f if -e $f && -f _ && -r _;
    return;
}

=head1 CONSTRUCTION

In which a factory is built according to the instructions in the one or more configuration files defined above.

=head2 new()

This is the main constructor. It calls C<build_config> to assemble all the configuration information, creates an empty Factory object and then calls C<load_classes> to start populating it. It can be supplied with the addresses of configuration files: if none are given, it will use the mechanisms described above to locate them.

  my $factory = Class::DBI::Factory->new( 
    $global_config_file, 
    $site_package_file, 
    $site_config_file 
  );

=head2 instance()

Returns the factory corresponding to the supplied site id. If no id is supplied then C<site_id> is called, which by default will look for C<$ENV{'_SITE_TITLE'}>. If that doesn't work, we will attempt to use Apache's C<$ENV{SITE_NAME}>.

If no factory exists for the relevant tag, one will be constructed and stored. Any parameters passed to the instance method after the initial site identifier will be passed on to C<new> if it is called (but parameters other than the site tag will not have any effect if the tag successfully identifies a factory and no construction is required).

If no site id is available from any source then a singleton factory object will be returned to all requests.

  my $factory = Class::DBI::Factory->instance(); 
    # will use environment variables for site id and configuration file
    
  my $factory = Class::DBI::Factory->instance( $site_id );

  my $factory = Class::DBI::Factory->instance(
    $global_config_file, 
    $site_package_file, 
    $site_config_file 
  );

=cut

sub instance {
    my $class = shift;
	my $tag = shift || $class->site_id || $ENV{SITE_NAME} || '__singleton';
	$class->debug(4, "CDF->instance($tag);");
	return $_factories->{$tag}->refresh_config() if $_factories->{$tag};
	
	$class->debug(1, "Creating new CDF instance for '$tag'");
    $_factories->{$tag} = $class->new(@_);
    $_factories->{$tag}->{_site} = $tag;
    return $_factories->{$tag};
}

sub new {
	my $class = shift;
	my $config = $class->build_config( @_ );
	my $self = bless {
		_config => $config,
		_timestamp => scalar time,
		_log => [],
		_packages => [],
		_classes => [],
		_sorted_classes => [],
		_title => {},
		_plural => {},
		_description => {},
		_precedes => {},
	}, $class;
	return $self;
}

=head2 build_config()

This is part of the constructor, but separated out to facilitate subclassing. It loads the configuration class and reads all the configuration files it can find into a single configuration object, which it returns to the constructor. It will try to use any parameters as file addresses, or call C<site_config_file> and C<global_config_file> if none are found. 

Any configuration file can also specify more files to be read, either by an include_file = line or a package = line (provided that a package_dir has also been specified at some point). See the included sample application for an annotated configuration file. Currently this only iterates once: included files may not themselves include other files.

  my $config = Class::DBI::Factory->build_config(
    $global_config_file, 
    $site_package_file, 
    $site_config_file 
  );

Note that there is no real difference between the three configuration files, except the fact that they are read in a particular order.

=head2 refresh_config()

Re-reads any configuration files that have been modified since they were read. This is accomplished just by calling C<$config-E<gt>refresh()>, so bear it in mind if you are doing anything clever with the configuration class.

If a refresh_interval parameter has been defined anywhere in the configuration files, this method will check first that the necessary amount of time has passed, and then that none of the configuration files have been updated in that period. Any that have will be read again. The order of reading is preserved.

The refresh_interval is just an economy: it saves us having to check the file dates on every call to C<instance>. Anything longer than the likely span of a single request will do.

=head2 config_class()

Should return the Full::Class::Name that will be used to handle factory configuration. Defaults to L<Class::DBI::Factory::Config>. You will almost certainly want to override build_config if you change this.

=cut

sub config_class { "Class::DBI::Factory::Config" }

sub build_config {
	my ($class, $global_config_file, $site_package_file, $site_config_file) = @_;
    $class->_require_class( $class->config_class );
	
	my $config = $class->config_class->new;
	$global_config_file ||= $class->global_config_file;
	$config->file($global_config_file) if $global_config_file;

	$site_package_file ||= $class->site_package_file;
	$config->file($site_package_file) if $site_package_file;
	$config->file( $config->package_dir . "/${_}.info") for @{ $config->packages };

	$site_config_file ||= $class->site_config_file;
	$config->file($site_config_file) if $site_config_file;
	$config->file( $_ ) for @{ $config->include_file };

	return $config;
}

sub refresh_config {
	my $self = shift;
	my $now = scalar time;
	my $then = $self->timestamp;
	my $interval = $self->config->get('refresh_interval') || 60;
	return $self unless $now > $then + $interval;
	$self->config->refresh();
	$self->timestamp($now);
	return $self;
}

=head2 config()

Returns the configuration object which the factory is using, with which any settings can be retrieved or set.

If you're using L<Class::DBI::Factory::Config>, then the config object is just a thinly-wrapped L<AppConfig> object.

=head2 id()

Returns the site tag by which this factory would be retrieved. This ought to be the same as C<site_id>, which looks in the host configuration, unless something has gone horribly wrong.

=cut

sub config {
	my ($self, $parameter) = @_;
	return $self->{_config} unless $parameter;
	return $self->{_config}->get($parameter);
}

sub id { shift->{_site} }

=head2 using()

Returns true if the named package has been successfully loaded. 

  [% 'latest bloggings' IF factory.using('blogpackagename') %]

=cut

sub using {
    return shift->config->package_loaded(@_);
}

=head2 load_classes()

Each class that has been specified in a configuration file somewhere (the list is retrieved by calling C<class_names>, if you felt like changing it) is C<require>d here, in the usual eval-and-check way, and its moniker stored as a retrieval key. This is mostly accomplished by way of calls to the following methods:

=head2 pre_require()

This method is called before the loading begins. It can act on the configuration data to affect the list of classes called, or it can just make whatever other preparations you require. The default does nothing. 

=head2 load_class()

This method handles the details of incorporating each individual class into the application. It requires the module, checks that the require has worked, and among other things makes calls to C<assimilate_class> and one of C<post_require> and C<failed_require>:

=head2 assimilate_class()

This method is called to store information about the class in the factory object. The default version here assumes that each class will have at least some of the following methods:

  * moniker: a tag by which to refer to the class, eg 'cd'
  * class_title: a proper name by which the class can be described, eg 'CD'
  * class_plural: plural form of the title
  * class_description: a blurb about the class
  * class_precedes: see precedence, below

only the moniker is compulsory, and the standard cdbi moniker provides a fallback for that, so you can safely ignore all this unless it seems useful.

=head2 post_require

This is another placeholder: it's called after each class is loaded, and supplied with the moniker and class name. The most likely use for this method is to make the factory, template, configuration or other system component available as a class variable, but remember that will break under mod_perl if you want more than one instance of the application.

By default post_require does nothing. The return value is not checked.
	
=cut

sub load_classes {
	my ($self, $reload) = @_;
	return if $self->{_loaded} && ! $reload;
	$self->debug(3, "loading data classes");
	$self->pre_require();
	$self->load_class($_) for @{ $self->class_names };
	$self->{_loaded} = 1;
	return $self;
}

sub load_class {
	my ($self, $class) = @_;
	return unless $class;
	$self->debug(5, "loading class '$class'");
	$self->_require_class($class);
	my $moniker = $self->assimilate_class($class);
	$self->post_require($moniker, $class);
}

sub _require_class {
	my ($self, $class) = @_;
	eval "require $class";
    throw Exception::SERVER_ERROR(-text => "failed to load class '$class': $@") if $@;
}

sub assimilate_class {
	my ($self, $class) = @_;
	return unless $class;
	my $moniker = $class->moniker;
	push @{ $self->{_classes} }, $moniker;
	$self->{_class_name}->{$moniker} = $class;
	$self->{_title}->{$moniker} = $class->class_title;
	$self->{_plural}->{$moniker} = $class->class_plural;
	$self->{_description}->{$moniker} = $class->class_description;
	return $moniker;
}

sub pre_require { return }
sub post_require { return }

=head1 CLASS RELATIONS

The second function of the factory is to pass instructions to its collected classes and pass their responses back to the caller. This is handled in a fairly intuitive and simple way: a command of the form

  My::Class->foo($bar);

can be written

  $factory->foo($moniker, $bar);

Provided foo is in the permitted set of methods passed through to data classes, and $moniker maps onto a class that we know, it should just work. The business of passing commands along is handled by a fairly simple AUTOLOAD sub which uses a dispatch table to screen commands and translate them into their real form. 

The dispatch table is built by way of calls to two separate subs which define the set of permitted operations as a hash of (factory_method => class_method):

=head2 permitted_methods()

This method defines a core set of method calls that the factory will accept and pass on to data classes: the Class::DBI API, basically, along with the extensions provided by Class::DBI::mysql and a few synonyms to cover old changes (has_column == find_column, for example) or simplify template code. Subclass this method to replace the factory API with one of your own.

=head2 extra_methods()

This is a hook to allow subclasses to extend (or selectively override) the set of permitted method calls with a minimum of bother. It is common for a local subclass of Class::DBI to add a few custom operations to the normal cdbi set: a C<retrieve_latest> here, a C<retrieve_by_serial_code> there. To expose those functions through the factory, you just need to put them in the hashref returned by C<extra_methods>. It's also a nice chance to omit the verbal clutter used to avoid clashes with column names:

  sub extra_methods {
    return {
      latest => retrieve_latest,
      by_serial => retrieve_by_serial_code,
      by_title => retrieve_by_title,
    }
  }

The keys of this hash become visible as factory methods, and the corresponding values are used to pass the call on to the data class. In this case, 

  $factory->latest('cd', foo, bar);

would be passed on as 

  My::CD->latest(foo, bar);

Which will of course fail if no C<latest> method has been defined (or no My::CD package has been loaded).

=cut

sub AUTOLOAD {
	my $self = shift;
	my $moniker = shift;
	$self->load_classes;
	my $method_name = $AUTOLOAD;
	$method_name =~ s/.*://;
    return if $method_name eq 'DESTROY';

	my $class = $self->class_name($moniker);
	$self->debug(1, "bad AUTOLOAD call: no class from moniker '$moniker'") unless $class;
  	return unless $class;
	
	my $method = $self->permitted_methods($method_name);
  	throw Exception::SERVER_ERROR(
  	    -text => "Class::DBI::Factory::AUTOLOAD is trying to call a '$method_name' method that is not recognised",
    ) unless $method;
	
	$self->debug(4, "AUTOLOAD: $class->$method(" . join(', ', @_) . ");");
	return wantarray ? $class->$method(@_) : scalar( $class->$method(@_) );
}

sub permitted_methods {
	my ($self, $call) = @_;
	return unless $call;
	my $extras = $self->extra_methods();
	return $extras->{$call} if $extras->{$call};
	
	my $standard_ops = {
		create => 'create',
		retrieve => 'retrieve',
		find_or_create => 'find_or_create',
		foc => 'find_or_create',
		all => 'retrieve_all',
		retrieve_all => 'retrieve_all',
		search => 'search',
		search_like => 'search_like',
		like => 'search_like',
		where => 'search',
		retrieve_where => 'search',
		count_all => 'count_all',
		count => 'count_all',
		max => 'maximum_value_of',
		min => 'minimum_value_of',
		has_column => 'find_column',
		find_column => 'find_column',
		columns => 'columns',
		table => 'table',
		primary => 'primary',
		create_table => 'create_table',
		set_up_table => 'set_up_table',
		retrieve_random => 'retrieve_random',
		random => 'retrieve_random',
		column_type => 'column_type',
		enum_vals => 'enum_vals',
	};
	return $standard_ops->{$call};
}

sub extra_methods { return {} }

=head2 use_classes()

You can pass a list of Full::Class::Names directly to this method and skip the whole configuration bother. This has to be done first, before any other factory method is called. It can be combined with configuration data, but it's a recent and experimental addition, so strangeness is likely.

=head2 classes()

returns an array reference containing the list of monikers. This is populated by the C<load_classes> method and includes only those classes which were successfully loaded.

=head2 class_names()

returns an array reference containing the list of full class names: this is taken straight from the configuration file and may include classes that have failed to load, since it is from this list that we try to C<require> the classes.

=head2 class_name()

Returns the full class name for a given moniker.

=head2 has_class()

Returns true if the supplied value is a valid moniker.

=cut

sub use_classes {
    my ($self, @classes) = @_;
    $self->config->classes(@classes);
    $self->load_classes;
}

sub classes {
	my $self = shift;
	$self->load_classes;
	return $self->{_classes};
}

sub class_names {
	return shift->config->classes;
}

sub class_name {
	my ($self, $moniker) = @_;
	$self->load_classes;
	return $self->{_class_name}->{$moniker};
}

sub has_class {
	my ($self, $moniker) = @_;
	$self->load_classes;
	return 1 if exists $self->{_class_name}->{$moniker};
}

=head2 ghost_class()

Override to use a ghost class other than Class::DBI::Factory::Ghost (eg if you have subclassed it).

=cut

sub ghost_class { 'Class::DBI::Factory::Ghost' }

=head2 ghost_object( moniker, columns_hashref )

Creates and returns an object of the ghost class, which is just a data-holder used to populate forms.

=cut

sub ghost_object {
    my ($self, $type, $columns) = @_;
    my ($package, $filename, $line) = caller;
    $self->debug(3, 'ghost_object(' . join(',',@_) . ") at $package line $line");
    $self->_require_class( $self->ghost_class );
    $columns->{type} = $type;
    return $self->ghost_class->new($columns);
}

=head2 ghost_from( data_object )

Returns a ghost object based on the class and properties of the supplied real object. Useful to keep a record of an object about to be deleted, for example.

=cut

sub ghost_from {
    my ($self, $thing) = @_;
    return $self->ghost_object($thing->type, { 
        map { $_ => $thing->$_() } $thing->columns('All')
    });
    
}

=head2 title() plural() description()

each return the corresponding value defined in the data class, as in:

  Which of these [% factory.plural('track') %] 
  has not been covered by a boy band?

=cut

sub title {
	my ($self, $moniker) = @_;
	return $self->{_title}->{$moniker} if $moniker;
	return $self->{_title};
}

sub plural {
	my ($self, $moniker) = @_;
	return $self->{_plural}->{$moniker} if $moniker;
	return $self->{_plural};
}

sub description {
	my ($self, $moniker) = @_;
	return $self->{_description}->{$moniker} if $moniker;
	return $self->{_description};
}


=head1 GOODS AND SERVICES

The rest of the factory's functions are designed to provide support to L<Class::DBI> applications. The factory is an efficient place to store widely used components like database handles and template engines, pagers, searches and lists, and to keep useful tools like C<escape> and C<unescape>, so that's what we do:

=head2 set_db()

Can be used to set database connection values if for some reason you don't want them in a config file. Expects to receive a hashref of parameters. The tests for CDF use this approach, if you want a look.

  $factory->set_db({
    db_type => '...',         # defaults to 'SQLite'
    db_host => '...',         # in which case no other parameters
    db_port => '...',         # are needed except a path/to/file
    db_name => '...',         # in db_name
    db_username => '...',
    db_password => '...',
  });
 
Defaults can be supplied by C<Class::DBI::Config::default_values>, which is called early in the configuration process.

=head2 dsn()

Returns the $data_string that CDF is using to create handles for this factory. Some modules - like L<Class::DBI::Loader> - want to be given a dsn rather than a database handle: sending them $factory->dsn should just work.

If a db_dsn parameter is supplied, it is accepted intact. Otherwise we will look for db_type, db_name, db_host, db_server and db_port parameters to try and build a suitable data source string. You will probably also want to db_username and db_password settings unless you're using SQLite.

=head2 dbh()

Returns the database handle which is used by this factory. 

Each factory normally has one handle, created according to its configuration instructions and then made available to all its data classes. The main point of this is to get around the one class -> one table assumptions of Class::DBI: each factory can provide a different database connection to the data using different data.

For this to be useful you must also override db_Main in your Class::DBI subclass, eg:

  sub db_Main { return shift->factory->dbh(@_); }

Should do it, except that you will probably have subclassed CDF, and should use the name of your subclass instead.

You can safely ignore all this unless your data clases need access to configuration information, template handler, unrelated other data classes or some other factory mechanism.

=cut

sub set_db {
	my ($self, $parameters) = @_;
	$self->config->set($_, $parameters->{$_}) for grep { exists $parameters->{$_} } qw(db_type db_name db_username db_password db_port db_host db_dsn);
}

sub dsn {
	my $self = shift;
	my $dsn = $self->config->get('db_dsn');
	unless ($dsn) {
	    $dsn = "dbi:" . $self->config->get('db_type') . ":";
	    $dsn .= "dbname=" . $self->config->get('db_name') if $self->config->get('db_name') && $self->config->get('db_name') ne '<undef>';
    	$dsn .= ";server=" . $self->config->get('db_servername') if $self->config->get('db_servername') && $self->config->get('db_servername') ne '<undef>';
    	$dsn .= ";host=" . $self->config->get('db_host') if $self->config->get('db_host') && $self->config->get('db_host') ne '<undef>';
    	$dsn .= ";port=" . $self->config->get('db_port') if $self->config->get('db_port') && $self->config->get('db_port') ne '<undef>';
    }
    return $dsn;
}

sub dbh {
    return &{ shift->_dbc };
}

=head2 _dbc()

taps into the terrible innards of Ima::DBI to retrieve a closure that returns a database handle of the right kind for use here, but instead of being incorprated as a method, the closure is stored in the factory object's hashref.

(All C<dbh> now does is to put a C<%{ }> round a call to $self->{_dbc}.)

This depends on close tracking of internal features of Ima::DBI and Class::DBI, since there is no easy way to make use of the handle-creation defaults from the outside. It will no doubt have to change with each update to cdbi.

=cut 

sub _dbc {
	my $self = shift;
	return $self->{_dbc} if $self->{_dbc};
	my $dsn = $self->dsn;
	my $attributes = {
        AutoCommit => $self->config->get('db_autocommit'),
        Taint => $self->config->get('db_taint'),
        RaiseError => $self->config->get('db_raiseerror'),
        ShowErrorStatement => $self->config->get('db_showerrorstatement'),
        RootClass => "DBIx::ContextualFetch",
        FetchHashKeyName => 'NAME_lc',
        ChopBlanks => 1,
        PrintError => 0,
    };
	my @config = (
		$dsn,
		$self->config->get('db_username'), 
		$self->config->get('db_password'), 
		$attributes,
	);
	$self->{_dbc} = Ima::DBI->_mk_db_closure(@config);
	return $self->{_dbc};
	
}

=head2 tt()

Like the database handle, each factory object can hold and make available a single Template object. This is almost always called by handlers during the return of a page, but you sometimes find that the data classes themselves need to make use of a template, eg. to publish a page or send an email. If you don't intend to use the Template Toolkit, you can override or just ignore this method: the Toolkit is not loaded unless the method is called.

Template paths can be supplied in two ways: as simple template_dir parameters, or by supplying a single template_root and several template_subdir parameters. The two can be combined: See L<Class::DBI::Factory::Config> for details.

=cut

sub tt {
	my $self = shift;
	return $self->{_tt} if $self->{_tt};

	$self->debug(3, 'loading Template Toolkit');
    $self->_require_class( 'Template' );

	my $recursion = $self->config->get('allow_template_recursion') || '0';
    my $path = $self->config->template_path || [];
	$self->debug(3, "recursion is '$recursion'\ntemplate path is '" . join(', ', @$path) . "'");

	my $tt = Template->new({ 
		INCLUDE_PATH => $path, 
		RECURSION => $recursion,
	});
	
  	throw Exception::SERVER_ERROR(-text => "Template initialisation error: $Template::Error") unless $tt;
	return $self->{_tt} = $tt;
}

=head2 process()

  $self->process( $template_path, $output_hashref, $outcome_scalar_ref );

Uses the local Template object to display the output data you provide in the template you specify and store the resulting text in the scalar (or request object) you supply (or to STDOUT if you don't). If you're using a templating system other than TT, this should be the only method you need to override.

Note that C<process> returns Apache's OK on success and SERVER_ERROR on failure, and OK is zero. It means you can close a method handler with C<return $self->process(...)> but can't say C<$self->process(...) || $self->fail>.

This is separated out here so that all data classes and handlers can use the same method for template-parsing. It should be easy to replace it with some other templating system, or amend it with whatever strange template hacks you like to apply before returning pages.

=cut

sub process {
	my ($self, $template, $data, $outcome) = @_;
	$self->debug(3, "processing template '$template'.");
	return 0 if $self->tt->process($template, $data, $outcome);
  	throw Exception::SERVER_ERROR(-text => $self->tt->error);
    return 1;
}

=head2 pager()

returns a pager object for the class you specify. Like all these methods, it defers loading the pager class until you call for it.

  my $pager = $factory->pager('artist');

=head2 pager_class()

Should return the Full::Class::Name that will be used to create pagers. Defaults to L<Class::DBI::Pager>.

=cut

sub pager {
	my ($self, $moniker, $perpage, $page) = @_;
	$perpage ||= 10;
	$page ||= 1;
	return $self->class_name($moniker)->pager($perpage, $page); 
}

=head2 list()

returns a list object with the parameters you specify. These can include column values as well as display parameters:

  my $list = $factory->list('cd',
    year => 1969,
    artist => $artist_object,
    sort_by => 'title',
    sort_order => 'asc',
    step => 20,
  );

The default list module (L<Class::DBI::Factory::List>) will build a query from the criteria you specify, turn it into an iterator and provide hooks that make it easy to display and paginate lists.

=head2 list_from()

For situations where the C<list> method doesn't quite provide the right access, you can also create a list object from any iterator by calling:

  my $list = $factory->list_from($iterator);

Which will provide display and pagination support without requiring you to jump through so many hoops.

=head2 list_class()

Should return the Full::Class::Name that will be used to handle paginated lists. Defaults to L<Class::DBI::Factory::List>.

=cut

sub list_class { "Class::DBI::Factory::List" }

sub list {
	my ($self, $moniker, %criteria) = @_;
    $self->_require_class( $self->list_class );
 	my %inflated_criteria = map { $_ => $self->reify( $criteria{$_}, $_ ) } keys %criteria;
 	$inflated_criteria{moniker} ||= $moniker;
	return $self->list_class->new(\%inflated_criteria);
}

sub list_from {
	my ($self, $iterator, $source, $param) = @_;
  	throw Exception::GLITCH(-text => "Class::DBI::Factory->list_from: no iterator supplied. Cannot build list.") unless $iterator;
    $self->_require_class( $self->list_class );
	return $self->list_class->from( $iterator, $source, $param );
}

=head2 reify()

C<reify> and C<type_map> are probably redundant these days, but they do no harm and so remain here for now.

Reify is a sort of filter, most commonly used to sift through input data and inflate any objects it finds there. When supplied with a pair of moniker => content:

=over

=item * 
if the content is already an object, it comes straight back

=item * 
if the moniker is valid, you get an inflated object back

=item * 
otherwise you just get the content back as it is

=back

It is less useful now than it used to be: with the abstraction of C<inflate> and C<deflate> methods and the odd bit of overloading, it seems that Class::DBI minds a lot less whether it gets objects or ids.

=head2 type_map()

This is another lookup method: you can use it to map column names onto monikers if for some reason you haven't just made them the same thing. The usual reason for this is that a class has two separate relations to a foreign class. Consider:

  My::Artist->has_a( best_cd => 'My::CD' );
  My::Artist->has_a( worst_cd => 'My::CD' );

You can't call both columns 'cd', so the factory needs to be told that a 'best_cd' column is actually a reference to an object of type 'cd'.

By default the only mapping is that 'parent' is assumed to be a relationship within the same class.

=cut

sub reify {
	my ($self, $content, $column, $this_moniker) = @_;
	return $content unless $column;
	return $content if ref $content;
	my $moniker = $self->type_map($column, $this_moniker) || $column;
	return $content unless $self->has_class( $moniker );
	return $self->retrieve( $moniker, $content );
}

sub type_map {
	my ($self, $tag, $parent_moniker) = @_;
    return $parent_moniker if $tag eq 'parent';
    return $tag;
}

=head1 ADMINISTRIVIA

=head2 log()

Whatever you send to C<log> is pushed onto the log...

=head2 report()

...ready to be read back out again when you call C<report>. In scalar it returns the latest item, in list the whole lot in ascending date order.

=cut

sub log {
	my ($self, @messages) = @_;
	push @{ $self->{_log} }, @messages;
	$self->debug(1, @messages);
}

sub report {
	my $self = shift;
	return wantarray ? @{ $self->{_log} } : $self->{_log}->[-1];
}

=head2 debug()

Set debug_level to a value greater than zero and the inner monologue of the handler (and some other modules, and any that you add) will be directed to STDERR. The first value supplied to debug should be an integer, the rest messages. If the number is less than debug_level, the messages will be printed. 

    $self->factory->debug(2, "session id is $s", " session key is $k");
    $self->factory->debug(-1, "this will always appear in the log");

=head2 debug_level()

Sets and gets the threshold for display of debugging messages. Defaults to the config file value (set by the debug_level parameter). Roughly:

=over

=item B<debug_level = 1>

prints a few important messages: usually ways in which this request or operation differs from the normal run of things
  
=item B<debug_level = 2>

prints markers as well, to record the stages of a request or operation as it is handled. This is a useful trace when trying to locate a failure.
  
=item B<debug_level = 2>

adds more detail, and...
  
=item B<debug_level = 4+>

...prints pretty much everything as it happens.

=back

=cut

sub debug {
    my ($self, $level, @messages) = @_;
    return unless ref $self && @messages;
    my $threshold = $self->debug_level || 0;
    return if $level > $threshold;
    my $tag = "[" . $self->id . "]";
    warn map { "$tag $_\n" } @messages;
    return @messages;
}

sub debug_level {
    my $self = shift;
    return $self->{_debug_level} = $_[0] if @_;
    return $self->{_debug_level} if $self->{_debug_level};
    return $self->{_debug_level} = $self->config->get('debug_level');
}

=head2 email_message( parameter_hashref )

Sends email (using Email::Send). The hashref of parameters must include at least 'to' and 'subject' or we'll bail silently. It can also include either a 'message' parameter containing the text of the message, or a 'template' parameter containing the address of the TT template that should be used to produce the message. The whole parameter hashref will be passed on to the template, so any other variables you want to make available can just be included there.

If both message and template parameters are supplied, we will use the template and hope that it has a [% message %] somewhere. If neither is supplied, the result will be an empty message with the subject and address you supply (which might be all that's required).

Parameter names are all lower-case, but remember to capitalise the From, To and Subject in message templates.

If you're having trouble with this, check your configuration's 'default_mailer' parameter, and compare against the documentation for L<Email::Send>. It has probably defaulted to Sendmail.

=cut

sub email_message {
	my ( $self, $instructions ) = @_;
	
	$self->debug(5, 'sending email message with: ' . Dumper($instructions));
	
	return unless $instructions->{subject} && $instructions->{to};
    $instructions->{from} ||= $self->config->get('mail_from');
	my $mailer = $self->config->get('default_mailer') || 'Sendmail';

	if ($instructions->{template}) {
	    my $ctype = 'text/html; charset="iso-8859-1"' if $instructions->{as_html};
	    my $message;
        $self->process( $instructions->{template}, {
            factory => $self,
            config => $self->config,
            date => $self->now,
    		%$instructions,
        }, \$message );
        send $mailer => $message;

	} else {
        
        send $mailer => <<"__ENDS__";
To: $$instructions{to}
From: $$instructions{from}
Subject: $$instructions{subject}

$$instructions{message}
__ENDS__
    }
}

=head2 email_admin( parameter_hashref )

A shortcut that will send a message to the configured admin address. This is mostly useful for error messages, which can be as simple as:

  $factory->email_admin({
    subject => 'uh oh',
    message => 'Something terrible has happened.',
  };

=cut

sub email_admin {
	my ( $self, $instructions ) = @_;
    $instructions->{to} = $self->config->get('admin_email');
    $self->email_message($instructions);
}

=head2 timestamp()

A get or set method which is normally used to mark the factory with the time its configuration files were last read.

=head2 version()

Returns C<$VERSION>.

=cut

sub timestamp {
	my $self = shift;
	return $self->{_timestamp} = $_[0] if $_[0];
	return $self->{_timestamp};
}

sub version {
	return $VERSION;
}

=head1 DEBUGGING

add_status_menu()

If CDF is loaded under mod_perl and Apache::Status is in your mod_perl configuration, then calling C<Class->add_status_menu> will add a menu item to the main page. The obvious place to call it from is startup.pl.

The report it produces is useful in debugging multiple-site configurations, solving namespace clashes and tracing startup problems, none of which should happen if the module is working properly, but you know.

Remember that the server must be started in single-process mode for the reports to be of much use, and that factories are not created until they're needed (eg. on the first request, not on server startup), so you need to blip each site before you can see its factory in the report.

=cut

sub add_status_menu {
	Apache::Status->menu_item(
		'factories' => "Class::DBI::Factory factories",
		\&status_menu
	) if Apache->module("Apache::Status");
}

sub status_menu {
	my ($r,$q) = @_;
	my @strings = (qq|<h1>CDF factories</h1><p>This is the list of factory-instances currently in memory. Note that a factory is not created until a request requires it, so you need to blip each site before you see the factories here, and that the same goes for each apache child process. This (and other Apache::Session reports) will work best in single-process mode.</p>|);

	for (sort keys %$_factories) {
		my $string = "<h3>site id: $_</h3>";
		my $factory = __PACKAGE__->instance($_);

		$string .= "<b>in memory:</b> " . $factory . "<br>";

		$string .= "<b>configuration files:</b> " . join(', ', $factory->config->files) . "<br>";
		$string .= "<b>database name:</b> " . $factory->config->db_name . "<br>";
		$string .= "<b>database handle:</b> " . $factory->dbh . "<br>";
		$string .= "<b>template object:</b> " . $factory->tt . "<br>";

		$string .= "<b>managed classes:</b> ";
		$string .= join(', ', map { qq|<a href="?$_">$_</a>| } @{ $factory->class_names });
		$string .= "<br>";

		push @strings, $string;
	}
	return \@strings;
}

=head1 BUGS

Are likely. Please use http://rt.cpan.org/ to report them, or write to wross@cpan.org to suggest more sweeping changes and new features. I'm keen to get this right and likely to respond quickly.

=head1 TODO

=over

=item *
Ensure cross-database compatibility (I've only used this with mysql and sqlite). Especially problematic for CDF::List, probably.

=item *
Improve Apache::Status reports. Include optional logs and error reports.

=item *
Write direct tests for the other modules

=back

=head1 REQUIRES

=over

=item L<Class::DBI>

=item L<AppConfig> (unless you replace the configuration mechanism)

=item L<Apache::Request> (if you use CDF::Handler)

=item L<Apache::Cookie> (if you use CDF::Handler);

=item L<DBD::SQLite> (but only for tests and demo)

=back

=head1 SEE ALSO

L<Class::DBI> L<Class::DBI::Factory::List> L<Class::DBI::Factory::Config> L<Class::DBI::Factory::Handler> L<Class::DBI::Factory::Exception>  L<Class::DBI::Factory::Ghost>

=head1 AUTHOR

William Ross, wross@cpan.org

=head1 COPYRIGHT

Copyright 2001-4 William Ross, spanner ltd.

This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut

1;
