package Class::DBI::Factory::Handler;
use strict;

use Apache::Constants qw(:response);
use Apache::Request ();
use Apache::Cookie ();

use IO::File;
use Carp ();
use Class::DBI::Factory::Exception qw(:try);
use Data::Dumper;

use vars qw( $VERSION );

$VERSION = '0.8';
$|++;

=head1 NAME

Class::DBI::Factory::Handler - a handler base class for Class::DBI::Factory applications

=head1 SYNOPSIS
    
in Apache configuration somewhere:

  <Location "/handler/path">
    SetHandler perl-script
    PerlHandler Handler::Subclass
  </Location>
  
and:

  Package Handler::Subclass;
  use base qw( Class::DBI::Factory::Handler );
  
  sub build_page {
    my $self = shift;
    my $person = $self->factory->retrieve('person', $self->cookie('person'));
    $self->print('hello ' . $person->name);
    $self->print(', sir') if $person->magnificence > 6;
  }

But see also the Class::DBI::Factory docs about configuration files and environment variables.

=head1 INTRODUCTION

Class::DBI::Factory::Handler (CDFH) is an off-the-peg mod_perl handler designed to function as part of a Class::DBI::Factory application. It can be used as it is, but is much more likely to be subclassed and has been written with that in mind.

It's just a convenience, really, and consists largely of utility methods that deal with cookies, headers, input, output, etc. It is meant to free authors from the dreary bits of input handling and database integration, and let them concentrate on writing application logic.

Note that if you want to subclass the handler module - and you do, you do - then mod_perl must be compiled with support for method handlers.

Authors are expected to subclass build_page(), at least, but you can use the standard version if you like. It creates a very basic bundle of useful objects and passes it to a selected template toolkit template. 

(TT is not loaded until CDFH::process() is called, so you're not paying for it unless you use it.)

=head1 CONFIGURATION

See the Class::DBI::Factory documentation for information about how to configure a CDF appplication. it goes on at some length. The handler just asks the factory for configuration information, and all you really have to do is make sure that each short-lived handler object gets the right long-lived factory object.

NB. This module's original purpose was to facilitate moves between CGI and mod_perl, but I let all that go because the factory system reached a size that wasn't very CGI-friendly. It's a little slimmer now (but not, you know, slim), and if anyone is interested, it would be easy to reinstate the CGI functionality. These days it's just a base class for mod_perl handlers.

=cut

sub new {
    my ($class, $r) = @_;
    my $self = bless {
		output_parameters => {},
		cookies_out => [],
	}, $class;
	$self->{_request} = Apache::Request->instance($r) if $r;
	return $self;
}

sub handler ($$) {
	my ($self, $r) = @_;
	$self = $self->new($r) unless ref $self;
	return $self->build_page;
}

=head1 PAGE CONSTRUCTION

The Handler includes some simple methods for directing output to the request handler with or without template processing, and a fairly well-developed skeleton for processing requests and working with cdbi objects. It is all designed to be easy to subclass and extend or replace.

=head2 BASIC OUTPUT

=head3 print( )

Prints whatever it is given by way of the request handler's print method. Override if you want to, for example, print directly to STDOUT.

Triggers send_header before printing.

=cut

sub print {
	my $self = shift;
	$self->send_header;
	$self->request->print(@_);
}

=head3 process( )

Accepts a (fully specified) template address and output hashref and passes them to the factory's process() method. The resulting html will be printed out via the request handler due to some magic in the template toolkit. If you are overriding process(), you will probably need to include a call to print().

=cut

sub process {
	my ($self, $template, $output) = @_;
	$self->debug(3, "processing template: $template");
	$self->send_header;
    $self->factory->process($template, $output, $self->request);
}

=head3 report()

  my $messages = $handler->report;
  $handler->report('Mission accomplished.');

Any supplied values are assumed to be messages for the user, and pushed onto an array for later. A reference to the array is then returned.

=cut

sub report {
	my $self = shift;
	$self->debug(2, @_);
    push @{ $self->{_report} }, @_;
    return $self->{_report};
}

=head3 message()

A simple get+set method commonly used in case of exception to pass through the main error message or some other page heading. Can be used in conjunction with report() and/or error() to liven up your day.

=cut

sub message {
	my $self = shift;
    $self->{_message} = $_[0] if @_;
    return $self->{_message};
}

=head3 error()

  my $errors = $handler->error;
  $handler->error('No such user.');

Any supplied values are assumed to be error messages. Suggests that debug display the messages (which it will, if debug_level is 1 or more) and returns the accumulated set as an arrayref.

=cut

sub error {
	my $self = shift;
	my @errors = @_;
	$self->{_errors} ||= [];
	$self->debug(1, 'error messages: ' . join('. ', @errors));
    push @{ $self->{_errors} }, @_;
    return $self->{_errors};
}

=head3 debug()

hands over to factory->debug, which will print messages to STDERR if debug_level is set to a sufficiently high value in the configuration of this site.

=cut

sub debug {
    shift->factory->debug(@_);
}

=head2 PAGE CONSTRUCTION

This is built around the idea of a task sequence: each subclass defines (or inherits) a sequence of events that the request will pass through before the page is returned. Each event in the sequence can throw an exception to halt processing and probably divert to some other view, such as a login screen. The exception types correspond to Apache return codes: OK, REDIRECT and SERVER_ERROR.

This base class includes a simple but sufficient task sequence along with create, update and delete methods that can be invoked in response to input.

=head2 build_page()

This is the main control method: it looks up the task sequence, performs each task in turn and catches any exceptions that result.

There are several ways to make use of this. You can use it exactly as it is, to get basic but comprehensive i/o. You can selectively override some of the steps - see below, you can change the list of tasks by overriding task_sequence(), or you can override build_page() to replace the whole mechanism with something more to your taste.

=cut

sub build_page {
	my $self = shift;
	
	$self->debug(1, "\n\n\n____________REQUEST: " . $self->full_url);
    $self->debug(3, "task sequence: " . join(', ', $self->task_sequence));
    my $return_code;
	
    try {
        $self->$_() for $self->task_sequence;
    }   
    catch Exception::OK with {
        my $x = shift;
        $self->debug(1, 'caught OK exception: ' . $x->text);
        $self->view( $x->view );
        $self->error( @{ $x->errors });
        $self->message( $x->text );
        $self->return_output;
    }
    catch Exception::NOT_FOUND with {
        my $x = shift;
        $self->debug(1, 'caught NOT_FOUND exception: ' . $x->text);
        my $view = $x->view || 'notfound';
        $self->return_code( $x->return_code );
        $self->return_error( $view, $x);
    }
    catch Exception::AUTH_REQUIRED with {
        my $x = shift;
        $self->debug(1, 'caught AUTH_REQUIRED exception: ' . $x->text);
        my $view = $x->view || ($self->session ? 'denied' : 'login');
        $self->return_code( $x->return_code );
        $self->return_error( $view, $x );
    }
    catch Exception::SERVER_ERROR with {
        my $x = shift;
        $self->debug(1, 'caught SERVER_ERROR exception: ' . $x->text);
        $x->log_error;
        $x->notify_admin;
        my $view = $x->view || 'error';
        $self->return_code( $x->return_code );
        $self->return_error( $view, $x );
    }
    catch Exception::REDIRECT with {
        my $x = shift;
        $self->debug(1, 'caught REDIRECT exception: ' . $x->text);
        $self->return_code( REDIRECT );
        $self->redirect( $x->redirect_to );
    }
    otherwise {
        my $x = shift;
        $self->debug(1, 'caught unknown exception: ' . $x->text);
        $self->return_code( SERVER_ERROR );
        $self->return_error( 'error', $x );
    };
}

=head2 task_sequence() 

The default sequence defined here is:

  check_permission 
  read_input
  do_op
  return_output

And each step is described below.

=cut

sub task_sequence {
    return qw( check_permission read_input do_op return_output );
}

=head3 check_permission() 

This is just a placeholder, and always returns true. It is very likely that your data classes will include a session class, and that you will want to check that  suitable session tokens have been presented, but I'm not going to impose a particular way of doing that (because CDF doesn't like to make assumptions about the presence of particular data classes).

=cut

sub check_permission { 1 };

=head3 read_input() 

Placed here as a convenience in case subclasses want to read from or adjust the input set. One common tweak is to read path_info. Any changes you make here should be by way of C<set_param>: if you call type or id directly, for example, later steps may override your changes.

NB. Most key values are retrieved from the input set by the corresponding method (eg calling ->type) will look at the 'type' or 'moniker' parameters if it finds no other value to return.

=cut

sub read_input { 
	my $self = shift;
	$self->adjust_input;

	unless ($self->param('id') || $self->param('type') || $self->param('moniker')) {
    	$self->debug(3, "no id or type parameters. scanning input for class monikers.");
        my @monikers = grep { $self->param($_) } @{ $self->factory->classes };
        my $moniker = $monikers[0];
        $self->set_param(type => $moniker);
        $self->set_param(id => $self->param($moniker)) unless $self->param($moniker) eq 'all';
		$self->delete_param($moniker);
	}

	unless ($self->param('id') || $self->param('type') || $self->param('moniker')) {
    	$self->debug(3, "no id or type parameters. checking path info.");
        my ($general, $specific) = $self->read_path_info;
        if ($general eq 'op' && $specific) {
            $self->set_param('op', $specific);
        } elsif ($self->factory->has_class($general)) {
            $self->set_param('type', $general);
            $self->set_param('id', $specific) unless $general eq 'all';
        } elsif ($general) {
            $self->set_param('view', $general);
        }
    }
}

sub adjust_input { return }

=head3 view( view_name )

Looks for a 'view' parameter in input and calls C<permitted_view> to compare it against the configured list of permitted views. 

Can be supplied with a value. Defined but non-true values will be accepted and retained, so to clear the view setting, just call C<view(0)>.

Either way, if a view value is present, this method throws a NOT_FOUND exception unless it is allowed.

=cut

sub view {
	my $self = shift;
    $self->set_param(view => $_[0]) if @_;
    return unless $self->param('view');
  	throw Exception::NOT_FOUND(-text => "No '" . $self->param('view') . "' view found") unless $self->thing || $self->permitted_view(scalar( $self->param('view') ));
    return scalar( $self->param('view') );
}

=head3 permitted_view( view_name )

Checks the supplied view name against the list of permitted views (ie the 'permitted_view' configuration parameter). Returns true if it is found there.

=cut

sub permitted_view {
	my ($self, $view) = @_;
    my @views = $self->config->get('permitted_view');
    my %permission = map {$_ => 1} @views;
    return $permission{$view};
}

=head3 type( moniker )

Looks for a moniker or type parameter in input and checks it against the factory's list of monikers. Can also be supplied with a moniker.

Throws a NOT_FOUND exception if the type parameter is supplied but does not correspond to a known data class.

NB. the type, id, op and view parameters are held as request parameters: they are not copied over into the handler's internal hashref. That way we can be sure that all references to the input data return the same results.

=cut

sub type {
	my $self = shift;
	$self->debug(4, 'CDFH->type(' . join(',',@_) . ')');
    $self->set_param(type => $_[0]) if @_;
  	throw Exception::NOT_FOUND(-text => "No '" . $self->param('type') . "' data class found") if $self->param('type') and not $self->factory->has_class(scalar( $self->param('type') ));
    return scalar( $self->param('type') );
}

=head3 id( int )

Looks for an 'id' parameter in input. Can be supplied with a value instead.

=cut

sub id {
	my $self = shift;
	$self->debug(4, 'CDFH->id(' . join(',',@_) . ')');
    $self->set_param(id => $_[0]) if @_;
    return scalar( $self->param('id') );
}

=head3 thing( data_object )

If both type (aka moniker) and id parameters are supplied, this method will retrieve and return the corresponding object (provided, of course, that the type matches a valid data class and the id an existing object of that class). 

You can also supply an existing object.

Returns immediately if the necessary parameters are not supplied. Throws a NOT_FOUND exception if the parameters are supplied but the object cannot be retrieved.

=cut

sub thing {
	my $self = shift;
	$self->debug(4, 'CDFH->thing(' . join(',',@_) . ')');
	return $self->{thing} = $_[0] if @_;
	return $self->{thing} if defined $self->{thing};
	
	return unless $self->type && $self->id;
    return $self->{thing} = $self->ghost if $self->type && $self->id && $self->id eq 'new';
    
    my $thing = $self->factory->retrieve( $self->type, $self->id );
   	throw Exception::NOT_FOUND(-text => "There is no object of type " . $self->type . " with id " . $self->id) unless $thing;
    return $self->{thing} = $thing;
}

=head3 ghost( )

Builds a ghost object (see L<Class::DBI::Factory::Ghost>) out of the input set, which can be used to populate forms, check input values and perform other tests and confirmations before actually committing the data to the database.

Ghost objects have all the same relationships as objects of the class they shadow. So you can call $ghost->person->title as usual.

Returns undef if no type parameter is found: the ghost has to have a class to shadow.

=cut

sub ghost {
	my $self = shift;
	return unless $self->type;

    $self->debug(3, 'CDFH is making a ghost');

    my $initial_values = { 
        map { $_ => $self->factory->reify( $self->param($_), $_, $self->type ) }
        grep { $self->param($_) }
        $self->factory->columns($self->type, 'All')
    };
    $initial_values->{id} = 'new';
    $initial_values->{type} = $self->type;
    $initial_values->{person} = $self->session->person;
    $initial_values->{date} = $self->factory->now;

 	return $self->factory->ghost_object($self->type, $initial_values);
}

=head3 op() 

Get or set that, by default, returns the 'op' input parameter.
 
=cut

sub op {
	my $self = shift;
    $self->set_param(op => $_[0]) if @_;
    return $self->param('op');
}

=head3 do_op() 

This is a dispatcher: if an 'op' parameter has been supplied, it will check that against the list of permitted operations and then call the class method of the same name.

A query string of the form:
 
 ?type=cd&id=4&op=delete
 
will result in a call to something like Class::DBI::Factory::Handler->delete(), if delete is a permitted operation, which will presumably result in the deletion of the My::CD object with id 4.

=cut

sub do_op {
	my $self = shift;
	my $op = $self->op;
	return unless $op;
	my $permitted = $self->permitted_ops;
    $self->debug(2, 'Checking permission to ' . $op);
    my $op_call = $permitted->{$op};
   	throw Exception::DECLINED(-text => "operation '$op' is not known") unless $op_call;
    $self->$op_call();
}

=head3 permitted_ops() 

This should return a dispatch table in the form of a hashref in which the keys are operation names and the values the associated method names (I<not> subrefs). Note that they are handler methods, not object methods.

=cut

sub permitted_ops {
    return {
        store => 'store_object',
        delete => 'delete_object',
    };
}

=head3 return_output() 

This one deals with the final handover to the template processor, calling C<assemble_output> to supply the values provided to templates and C<template> to get the template file address.

This base class uses the Template Toolkit: override C<return_output> to use some other templating mechanism.

=cut

sub return_output {
	my $self = shift;
	$self->process( $self->container_template, $self->assemble_output );
}

sub return_error {
	my ($self, $error, $x) = @_;
    $self->debug(3, "*** return_error: $error");
    my $output = $self->minimal_output;
    my $template = $self->config->get('error_page');
    $output->{error} = $error;
    $output->{report} = $x;
	$self->process( $template, $output );
}

=head3 assemble_output() 

The variables which will be available to templates are assembled here.

=cut

sub assemble_output {
	my $self = shift;
	my $extra = $self->extra_output;
	my $output = { 
		handler => $self,
		factory => $self->factory,
		config => $self->config,
		session => $self->session || undef,
		page_template => $self->page_template_path || undef,
		thing => $self->thing || undef,
		type => $self->type || undef,
		list => $self->list || undef,
		url => $self->url || undef,
		qs => $self->qs || undef,
		path_info => $self->path_info || undef,
		deleted_object => $self->deleted_object || undef,
		input => { $self->all_fat_param } || undef,
        site_id => $self->factory->id || undef,
        errors => $self->error || undef,
        message => $self->message || undef,
        %$extra,
    };
    return $output;
}

sub minimal_output {
	my $self = shift;
	my $output = { 
		handler => $self,
		factory => $self->factory,
		config => $self->config,
		input => { $self->all_param } || undef,
    };
    return $output;

}

=head3 extra_output()

This is called by assemble_output, and the hashref it returns is appended to the set of values passed to templates. By default it returns {}: its purpose here is to allow subclasses to add to the set of template variables rather than having to redo it from scratch.

=cut

sub extra_output {
	return {};
}

=head3 pager( ignore_id )

If a type parameter has been supplied, and corresponds to a valid data class, this method will return a pager object attached to that class. If there's a page parameter, that will be passed on too.

Normally this method will return undef if an id parameter is also supplied, assuming that an object rather than a pager is required. Supply a true value as the first parameter and this reluctance will be overridden.

=cut

sub pager {
	my ($self, $insist) = @_;
	return if $self->id && ! $insist;
	return unless $self->type;
    $self->{pager} = $self->factory->pager($self->type, $self->param('page'));
    @{ $self->{contents} } = $self->{pager}->retrieve_all();
    return $self->{pager};
}

=head3 list( list_object )

If a type parameter has been supplied, this will return an object of Class::DBI::Factory::List attached to the corresponding data class. 

Any other parameters that match columns of the data class will also be passed through, along with any of the list-control flags (sortby, sortorder, startat and step).

As with pager, if there is an id parameter then the list will only be built if you pass a true value to the method.

=cut

sub list {
	my ($self, $insist) = @_;
	return if $self->id && ! $insist;
	return unless $self->type;
    my %list_criteria = map { $_ => scalar( $self->param($_) ) } grep { $self->param($_) } $self->factory->columns($self->type, 'All');
    $list_criteria{$_} = $self->param($_) for grep { $self->param($_) } qw( sortby sortorder startat step );
    return $self->{list} = $self->factory->list( $self->type, %list_criteria );
}

=head3 session( )

This is just a placeholder, and doesn't do or return anything. It is included in the default set, on the assumption that the first thing you do will be to supply a session-handling mechanism: all you have to do is override this session() method.

I'm not going to include anything specific here, becase CDF doesn't like to make any assumptions about the existence of particular data classes.

=cut

sub session { undef }

=head3 container_template( )

Returns the full path of the main template that will be used to build the page that is to be displayed. This may actually be the template that displays the object or list you want to return, but it is more commonly a generic container template that controls layout and configuration.

This value is passed to the Template Toolkit along with the bundle of value returned by C<assemble_output>.

=cut

sub container_template {
	my $self = shift;
    return $self->{_container_template} = $_[0] if @_;
    return $self->{_container_template} if $self->{_container_template};
    return $self->{_container_template} = $self->default_container;
}

sub default_container {
	my $self = shift;
    return $self->config->get('default_container');
}

=head3 page_template( )

Returns the i<name> of the secondary template that will be used to display the list or object that you are returning. This is passed as a page_template variable to the primary template identified by container_template(), where the generic container will use it to pull in the specific template that is required.

By I<name>, incidentally, I mean the filename without its suffix. A directory path will be supplied by template_prefix and a file suffix by template_suffix, if appropriate. This apparent overcomplication allows handlers to choose between html and xml, for example. Note that you will also want to set (or override) C<mime_type> in that case. 

=cut

sub page_template {
	my $self = shift;
	return $self->{template} = $_[0] if @_;
	return $self->{template} if $self->{template};
	if ($self->thing) {
        return $self->{template} = 'one';
    } elsif ($self->type) {
        return $self->{template} = 'many';
     } elsif ($self->view) {
        return $self->{template} = $self->view;
   } else {
        return $self->{template} = $self->default_view;
    }
}

sub default_view {
	my $self = shift;
    return $self->config->get('default_view') || 'welcome';
}

sub page_template_path {
	my $self = shift;
	my $template = $self->page_template;        # may change prefix or suffix
    return $self->template_prefix . $template . $self->template_suffix;
}

=head3 template_prefix( )

A simple get-and-set placeholder: subclasses can either dictate the prefix per-request or override the method to direct the template processor to one or other subset of templates by returning a subdirectory address in the usual template form (ie no opening /). A trailing / will be added if necessary.

=head3 template_category( )

An older synonym of template_prefix.

=head3 default_template_prefix( )

Returns a file suffix, if appropriate. The default value is taken from the configuration parameter 'template_prefix'.

=cut

sub template_prefix { 
    my $self = shift;
    $self->{_template_dir} = $_[0] if @_;
    $self->{_template_dir} ||= $self->default_template_prefix;
    $self->{_template_dir} .= "/" if $self->{_template_dir} && $self->{_template_dir} !~ /\/$/;
    $self->debug(3, 'returning template prefix ' . $self->{_template_dir});
    return $self->{_template_dir};
}

sub template_category { return shift->template_prefix(@_); }
sub default_template_prefix { shift->config->get('template_prefix') }

=head3 template_suffix( )

Simple get and set: accepts and holds a value, or failing that gets one from default_template_suffix. Prepends a . if necessary.

=head3 default_template_suffix( )

Returns a file suffix, if appropriate. The default value is taken from the configuration parameter 'template_suffix'.

=cut

sub template_suffix {
	my $self = shift;
	return $self->{suffix} = $_[0] if @_;
	return $self->{suffix} if $self->{suffix} ;
    my $suffix = $self->default_template_suffix;
    $suffix = ".$suffix" if $suffix && $suffix !~ /^\./;
    return $self->{suffix} = $suffix;
}
sub default_template_suffix { shift->config->get('template_suffix') || 'html' }

=head1 BASIC OPERATIONS

This small set of methods provides for the most obvious operations performed on cdbi objects: create, update and delete. Most of the actual work is delegated to factory methods.

A real application will also include non-object related operations like logging in and out, registering and making changes to sets or classes all at once.

=head2 store_object()

Uses the input set to create or update an object.

The resulting object is stored in $self->thing.

=head2 delete_object()

calls delete() on the foreground object, but first creates a ghost copy and stores it in deleted_object(). The ghost should have all the values and relationships of the original.

=cut

sub store_object {
	my $self = shift;
	return unless $self->thing;

    # if this is a new object then thing() will return a ghost that just needs to be solidified with make().

	return $self->thing->make if $self->thing->is_ghost;

    # otherwise we apply input values to an existing object then update it.

	my %input = $self->all_param;
	my %parameters = map { $_ => $self->param($_) } grep { $self->thing->find_column( $_ ) } keys %input;
	delete $parameters{$_} for $self->thing->columns( 'Primary' );

	$self->debug(1, "updating columns: " . join(', ', keys %parameters));
    $self->thing->$_($parameters{$_}) for keys %parameters;
    $self->thing->update;
}

sub delete_object {
	my $self = shift;
    if ($self->thing) {
        $self->deleted_object( $self->factory->ghost_from($self->thing) );
        $self->thing->delete;
        $self->thing(undef);
    }

}

sub deleted_object {
	my $self = shift;
    return $self->{deleted_object} = $_[0] if @_;
    return $self->{deleted_object};
}

=head1 USEFUL MACHINERY

=head2 factory()

$handler->factory->retrieve_all('artist');

returns the local factory object, or creates one if none exists yet.

=cut

sub factory {
	my $self = shift;
	return $self->factory_class->instance();
}

=head2 factory_class()

returns the full name of the class that should be used to instantiate the factory. Defaults to Class:DBI::Factory, of course: if you subclass the factory class, you must mention the name of the subclass here.

=cut

sub factory_class { "Class::DBI::Factory" }
sub factory { return shift->factory_class->instance; }

=head2 request()

Returns the Apache::Request object that started it all.

=head2 config()

Returns the configuration object which is controlling the local factory. This method is included here to let you override configuration mechanisms in subclass, but unless you have per-handler configuration changes, it is probably more sensible to make that sort of change in the factory than here. 

=head2 tt()

Returns the template object which is being used by the local factory. This method is here to make it easy to override delivery mechanisms in subclass, but this method costs nothing unless used, so if you're using some other templating engine that TT2, you will probably find it more straightforward to replace the process() method.

=cut

sub request { shift->{_request}; }
sub config { shift->factory->config(@_); }
sub tt { shift->factory->tt(@_); }

=head1 CONTEXT

=head2 url()

Returns the url of this request, properly escaped so that it can be included in an html tag or query string.

=head2 qs()

Returns the query string part of the address for this request, properly escaped so that it can be included in an html tag or query string.

=head2 full_url()

Returns the full address of this request (ie url?qs)

=cut

sub url {
	my $self = shift;
	return $self->request->uri;
}

sub full_url {
	my $self = shift;
	return $self->url . "?" . $self->qs;
}

sub qs {
	my $self = shift;
	return $self->request->query_string; 
}

=head2 path_info()

Returns the path information that is appended to the address of this handler. if your handler address is /foo and a request is sent to:

/foo/bar/kettle/black

then the path_info will be /bar/kettle/black. Note that the opening / will cause the first variable in a split(/\/) to be undef.

=cut

sub path_info {
	my $self = shift;
	return $self->request->path_info();
}

=head2 read_path_info()

Returns a cleaned-up list of values in the path-info string, in the order they appear there. 

It is assumed that values will be separated by a forward slash and that any file-type suffix can be ignored. This allows search-engine (and human) friendly urls.

=head2 path_suffix()

Returns the file-type suffix that was appended to the path info, if any. It's a useful place to put information about the format in which we should be returning data.

=cut

sub read_path_info {
	my $self = shift;
	my $pi = $self->path_info;
    $pi =~ s/\.\w{2,4}$//i;
    my ($initialslash, @input) = split('/', $pi);
    return @input;
}

sub path_suffix {
	my $self = shift;
	my $pi = $self->path_info;
    return $1 if $pi =~ s/\.(\w{2,4})$//i;
    return;
}

=head2 referer()

returns the full referring address. Misspelling preserved for the sake of tradition.

=cut 

sub referer {
	return shift->headers_in('Referer');
}

=head2 headers_in()

If a name is supplied, returns the value of that input header. Otherwise returns the set. Nothing clever here: just calls Apache::Request->headers_in().

=cut 

sub headers_in {
	my $self = shift;
	return $self->request->headers_in->get($_[0]) if @_;
	return $self->request->headers_in;
}

=head2 param()

  $session_id = $handler->param('session');

If a name is supplied, returns the value of that input parameter. Acts like CGI.pm in list v scalar.

Note that param() cannot be used to set values: see set_param() for that. Separating them makes it easier to limit the actions available to template authors.

=head2 fat_param()

Like param(), except that wherever it can turn a parameter value into an object, it does.

=head2 has_param()

  $verbose = $handler->has_param('verbose');

Returns true if there is a defined input parameter of the name supplied (ie true for zero, not for undef).

=head2 all_param()

  %parameters = $handler->all_param;

Returns a hash of (name => value) pairs. If there are several input values for a particular parameter, then value with be an arrayref. Otherwise, just a string.

=head2 all_fat_param()

Like all_param(), except that wherever it can turn a parameter value into an object, it does.

=head2 set_param()

  $handler->set_param( 
     time => scalar time,
  ) unless $self->param('time');

Sets the named parameter to the supplied value. If no value is supplied, the parameter will be cleared but not unset (ie it will exist but not be defined).

=head2 delete_param()

  $handler->delete_param('password');

Thoroughly unsets the named parameter.

=head2 delete_all_param()

Erases all input by calling delete_param() for all input parameters.

=cut 

sub param {
	my ($self, $p) = @_;
	return $self->request->param($p);
}

sub fat_param {
	my ($self, $parameter) = @_;
	if (wantarray) {
	    my @input = $self->param($parameter);
	    return map { $self->factory->reify( $_, $parameter ) } @input;
	} else {
	    return $self->factory->reify( scalar($self->param($parameter)), $parameter );
	}
}

sub has_param {
	my $self = shift;
	return 1 if @_ && defined $self->request->param($_[0]);
	return 1 if !@_ && $self->request->param;
	return 0;
}

sub all_param {
	my $self = shift;
	my %param;
	for (keys %{ $self->request->parms } ){
	    my @input = $self->param($_);
	    $param{$_} = (scalar @input > 1) ? \@input : $input[0];
	}
	return %param;
}

sub all_fat_param {
	my $self = shift;
	my %param = $self->all_param;
	my %fat_param;
	foreach my $p (keys %param) {
	    my @values = (ref $param{$p} eq 'ARRAY') ? @{ $param{$p} } : ($param{$p});
	    my @objects = map { $self->factory->reify($_, $p) } @values;
	    $fat_param{$p} = (scalar @objects > 1) ? \@objects : $objects[0];
	}
    return %fat_param;
}

sub set_param {
	my $self = shift;
	$self->debug(4, 'set_param(' . join(',',@_));
	return $self->request->param(@_);
}

sub delete_param {
	my $self = shift;
	$self->debug(4, 'delete_param(' . join(',',@_));
	my $tab = $self->request->parms;
	$tab->unset($_) for @_;
}

sub delete_all_param {
	my $self = shift;
	$self->delete_param(keys %{ $self->request->parms });
}

=head2 uploads()

  my @upload_fields = $handler->uploads();

Returns a list of upload field names, each of which can be passed to:

=head2 upload( field_name )

  my $filehandle = $handler->upload('imagefile');

Returns a filehandle connected to the relevant upload.

=cut 

sub uploads {
	my $self = shift;
	my @uploads = $self->request->upload;
	return @uploads;
}

sub upload {
	my $self = shift;
	return $self->request->upload(@_);
}

=head2 cookies()

  my $cookies = $handler->cookies();

Returns the full set of cookies as a hashref.

=head2 cookie( cookie_name )

  my $userid = $handler->cookie('my_site_id');

Returns the value of the specified cookie.

=cut 

sub cookies {
	my $self = shift;
	return $self->{_cookies} if $self->{_cookies};
	return $self->{_cookies} = Apache::Cookie->fetch;
}

sub cookie {
	my ($self, $cookiename) = @_;
	my $cookies = $self->cookies;
	return $cookies->{$cookiename}->value if $cookies->{$cookiename};
}

=head1 HEADERS OUT

=head2 send_header()

  $handler->send_header();
  $handler->send_header('image/gif');

Sends out an http header along with any associated cookies or other optional header fields, then sets a flag to prevent any more headers being sent. If no mime-type is supplied, it will use the default returned by default_mime_type(). print() and process() both call send_header() before output, so you may not need to use this method directly at all.

=head2 no_cache()

Returns false by default. If this method is subclassed such that it returns true, then the header sent will include the pragma:no-cache and expiry fields that are used to prevent browser caching.

=head2 mime_type( $type )

A simple method that can be used to get or set the mime-type for this response, or subclassed to make some other decision altogether. Defaults to:

=head2 header_sent( $type )

Get or set method that returns true if headers have already been sent. This will cause set_cookie and redirect to bail out if they are called too late, as well as preventing duplicate headers from being sent.

=head2 default_mime_type()

Returns the mime type that will be used if no other is specified. The default default is text/html: override in subclass if that doesn't suit.

=cut

sub send_header {
	my $self = shift;
	return if $self->{_header_sent};
	$self->request->content_type($self->mime_type);
    $self->request->status($self->return_code);
	$self->request->no_cache(1) if $self->no_cache;	
	$_->bake for @{ $self->{cookies_out} };
	$self->request->send_http_header;
    $self->header_sent(1);
}

sub no_cache { 0 };
sub default_mime_type { 'text/html' }

sub return_code {
	my $self = shift;
    return $self->{_return_code} = $_[0] if @_;
    return $self->{_return_code} || OK;
}

sub header_sent {
	my $self = shift;
    return $self->{_header_sent} = $_[0] if @_;
    return $self->{_header_sent};
}

sub mime_type {
	my $self = shift;
    return $self->{_mime_type} = $_[0] if @_;
    return $self->{_mime_type} if $self->{_mime_type};
    return $self->{_mime_type} = $self->default_mime_type;
}

=head2 set_cookie( hashref )

$handler->set_cookie({
    -name => 'id',
    -value => $id,
    -path => '/',
    -expires => '+100y',
});

Adds one or more cookies to the set that will be returned with this page (or picture or whatever it is). Note that the cookie is not actually returned until send_header() or redirect() is called, and that a cookie set after send_header() is called will have no effect except to produce a warning in the log.

=cut

sub set_cookie {
	my $self = shift;
    if ($self->header_sent) {
        $self->debug(1, 'set_cookie: headers already sent');
        return;
    }
	push @{ $self->{cookies_out} }, map { Apache::Cookie->new($self->request, %{ $_ }) } @_;
	return 1;
}

=head2 redirect( full_url )

$handler->redirect('http://www.spanner.org/cdf/')

Causes apache to return a '302 moved' response redirecting the browser to the specified address. Ignored if headers have already been sent.

Any cookies that have been defined are sent with the redirection, in accordance with doctrine and to facilitate login mechanisms, but I am not wholly convinced that all browsers will stash a cookie sent with a 302.

=cut

sub redirect {
	my $self = shift;
    if ($self->header_sent) {
        $self->debug(1, 'redirect: headers already sent');
        return;
    }
	my $url = shift || $self->{redirect} || $self->factory->config('url');
    $self->debug(3, "*** redirect: bouncing to $url");
	$self->request->err_headers_out->add('Set-Cookie' => $_) for @{ $self->{cookies_out} };
	$self->request->err_headers_out->add( Location => $url );
	return REDIRECT;
}

=head2 redirect_to_view( view_name )

$handler->redirect_to_view('login')

This is normally called from an exception handler: the task sequence is stopped and we jump straight to C<return_output> with the view parameter set to whatever value was supplied.

=cut

sub redirect_to_view {
	my ($self, $view) = @_;
    $self->debug(3, "*** redirect_to_view: bouncing to view $view");
    $self->template_prefix( $self->config->get('view_template_directory') || 'views' );
    $self->view( $view );
    return $self->return_output;
}

=head1 SEE ALSO

L<Class::DBI> L<Class::DBI::Factory> L<Class::DBI::Factory::Config> L<Class::DBI::Factory::List> L<Class::DBI::Factory::Exception>

=head1 AUTHOR

William Ross, wross@cpan.org

=head1 COPYRIGHT

Copyright 2001-4 William Ross, spanner ltd.

This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut

1;
