package Class::DBI::Factory::Howto
use vars qw( $VERSION );
$VERSION = '0.01';
1;

=head1 NAME

Class::DBI::Factory::Howto - a guide and recipe list for CDF

=head1 INTRODUCTION

This has been rudely stripped from the pod in L<Class::DBI::Factory> and is therefore rather choppy. It will get more useful soon.

=head1 Using Class::DBI::Factory

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

The Factory is most likely to be employed as the hub of a Class::DBI-based web application, supplying objects, information and services to handlers, templates and back-end processes as required, so it includes a few key services that make Class::DBI much easier to use under mod_perl (see L</"PERSISTENCE"> below), and comes with a few helper classes designed with that role in mind:

=head2 Class::DBI::Factory::List

is a general-purpose list handler that can transparently execute and paginate queries with select, order and limit clauses. If it works with anything but mysql at the moment then that's an accident, but I fondly imagine that it will become as platform-independent as Class::DBI, at least.

=head2 Class::DBI::Factory::Config

uses AppConfig to provide moderately complex configuration services with minimal effort. There is provision for a package-based pseudo-plugin architecture.

=head2 Class::DBI::Factory::Exception

provides an exception-handling framework based on Apache return codes. See CDF::Handler::build_page for the main example of this in use.

=head2 Class::DBI::Factory::Ghost

ghost objects act like CDBI objects, or at least enough to be useful on a template. They're based on the characteristics of a cdbi class or object, and normally used as a prototype before object creation or as an echo of a deleted object for reporting purposes.

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

This gratuitous diagram may help to show how all this fits together in the case of a single application being used by several separate sites:

+------------------+  +--------------------+ +-------------------+                                  
|                  |  |  +--------------+  | |  once per server  |                                  
|   http           |  |  |   Config     |  | |                   |                                  
|   request        |  |  |   object     |  | |                   |                                  
|     |            |  |  +--------------+  | |                   |                                  
|     |            |  |          |         | | +-------------+   |                                  
|     v            |  |          |         | | |  app logic  |   |                               
| +-------------+  |  |  +--------------+  | | |  and data   |   |                                  
| | mod_perl    |  |  |  |   Factory    |--+-+-|  classes    |   |                                  
| | content     |<-+--+--|   object     |  | | +-------------+   |                                  
| | handler(s)  |  |  |  +--------------+  | +-------+-----------+                                  
| +-------------+  |  |          |         +---------+-----------+                                  
|     |            |  |          |                   |           |                                  
|     |            |  |  +--------------+      +-------------+   |                                  
|     v            |  |  |   database   |      |  your       |   |                                  
|   http           |  |  |   handle     |------|  database   |   |                                  
|   response       |  |  +--------------+      +-------------+   |                                  
|                  |  |                                          |                                  
|                  |  |                                          |                                  
| once per request |  |  once per site                           |                                  
+------------------+  +------------------------------------------+ 

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


