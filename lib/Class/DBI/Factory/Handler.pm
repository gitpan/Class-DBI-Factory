package Class::DBI::Factory::Handler;
use strict;

use Apache::Constants qw(:response);
use Apache::Request ();
use Apache::Cookie ();

use IO::File;
use Carp ();

use vars qw( $VERSION );

$VERSION = '0.741';
$|++;

=head1 NAME

Class::DBI::Factory::Handler - a handler template for Class::DBI::Factory applications

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

NB. This module's original purpose was to facilitate moves between CGI and mod_perl, but I let all that go because the factory system reached a size that wasn't very CGI-friendly. It's a little slimmer now (but not, you know, slim), and if anyone is interested, it would be easy to reinstate the CGI functionality. These days it's just a template for handlers.

=cut

sub new {
    my ($class, $r) = @_;
    my $self = bless {
		output_parameters => {},
		cookies_out => [],
	}, $class;
	$self->{request} = Apache::Request->instance($r) if $r;
	return $self;
}

sub handler ($$) {
	my ($self, $r) = @_;
	$self = $self->new($r) unless ref $self;
	return $self->build_page;
}

=head1 PAGE CONSTRUCTION

The short version: you want to subclass build_page() and within it somewhere call:

    $self->print(whatever you like);

or if you're using the template toolkit, just:

    $self->process('your template', {
       your => data 
    });

The details will be taken care of, and there are various useful methods described below that should take a lot of the drudgery out.

=head2 print()

  $self->print('welcome to my world');

prints whatever you send it. In the old days this used to do the right thing about printing under mod_perl and cgi, but now it just makes sure that an appropriate header has been sent and then calls $self->request->print( @_ ).

=head2 process()

  $self->process( $template_path, $output_hashref );

Hands over to the factory's C<process> method.

=head2 build_page()

In order that the modules work out of the box, there is a rudimentary build_page method included. It parses the input to look for type and id parameters, decides whether one, many or no objects are to be displayed, and passes the necessary bundle of stuff to the factory's Template object. If you have a 'template_dir' line in your configuration file, and files exist in that directory called 'one.html', 'many.html' and 'front.html', then it should Just Work. Examples should have been included with this installation.

=cut

sub build_page {
	my $self = shift;
	my $moniker = $self->param('type');
	my $id = $self->param('id');

	my $template;
	my $suffix = $self->config->get('template_suffix') || 'html';
	my $output = { 
		factory => $self->factory,
		config => $self->config,
		url => $self->url,
		qs => $self->qs,
	};
	
	if ($id) {
		$output->{thing} = $self->factory->retrieve($moniker, $id);
		$template = "one.$suffix";
	} elsif ($moniker) {
		$output->{pager} = $self->factory->pager($moniker, $self->param('page'));
		@{ $output->{contents} } = $output->{pager}->retrieve_all();
		$output->{type} = $moniker;
		$template = "many.$suffix";
	} else {
		$template = "front.$suffix";
	}
	
	$self->process( $template, $output );
	return OK;
}

sub print {
	my $self = shift;
	$self->send_header;
	$self->request->print(@_);
}

sub process {
	my ($self, $template, $output) = @_;
	$self->send_header;
    $self->factory->process($template, $output, $self->request);
}

=head2 report()

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

=head2 error()

  my $errors = $handler->error;
  $handler->error('No such user.');

Any supplied values are assumed to be error messages. Suggests that debug display the messages (which it will, if debug_level is 1 or more) and returns the accumulated set as an arrayref.

=cut

sub error {
	my $self = shift;
    push @{ $self->{_errors} }, @_;
	$self->debug(1, @_);
    return $self->{_errors};
}

=head2 debug()

hands over to factory->debug, which will print messages to STDERR if debug_level is set to a sufficiently high value in the configuration of this site.

=cut

sub debug {
    shift->factory->debug(@_);
}

=head1 USEFUL MACHINERY

=head2 factory()

$handler->factory->retrieve_all('artist');

returns the local factory object, or creates one if none exists yet.

=head2 factory_class()

returns the full name of the class that should be used to instantiate the factory. Defaults to Class:DBI::Factory, of course: if you subclass the factory class, you must mention the name of the subclass here.

=cut

sub factory_class { 'Class::DBI::Factory' }

sub factory {
	my $self = shift;
	return $self->{_factory} ||= $self->factory_class->instance();
}

=head2 session()

This is just a get and set method that's here to mark the spot. You will, I trust, replace it with something much more sophisticated.

=cut

sub session {
	my $self = shift;
	return $self->{_session} = $_[0] if @_;
	return $self->{_session};
}

=head2 request()

Returns the Apache::Request object which started it all.

=head2 config()

Returns the configuration object which is controlling the local factory. This method is included here to let you override configuration mechanisms in subclass, but unless you have per-handler configuration changes, it is probably more sensible to make that sort of change in the factory than here. 

=head2 tt()

Returns the template object which is being used by the local factory. This method is here to make it easy to override delivery mechanisms in subclass, but this method costs nothing unless used, so if you're using some other templating engine that TT2, you will probably find it more straightforward to replace the process() method.

=cut

sub request { shift->{request}; }
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
	return $self->{request}->uri();
}

sub full_url {
	my $self = shift;
	return $self->url . "?" . $self->qs;
}

sub qs {
	my $self = shift;
	return $self->{request}->query_string; 
}

=head2 path_info()

Returns the path information that is appended to the address of this handler. if your handler address is /foo and a request is sent to:

/foo/bar/kettle/black

then the path_info will be /bar/kettle/black. Note that the opening / will cause the first variable in a split(/\/) to be undef.

=cut

sub path_info {
	my $self = shift;
	return $self->{request}->path_info();
}

=head2 referer()

returns the full referring address. Typo preserved for the sake of tradition.

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
	return shift->request->param(@_);
}

sub delete_param {
	my $self = shift;
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

=head2 upload()

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

=head2 cookie()

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

=head2 default_mime_type()

Returns the mime type that will be used if no other is specified. The default is text/html.

=cut

sub send_header {
	my ($self, $type) = @_;
	return if $self->{_header_sent};
	$type ||= $self->default_mime_type;
	$self->request->content_type($type);
	$self->request->no_cache(1) if $self->no_cache;	
	$_->bake for @{ $self->{cookies_out} };
	$self->request->send_http_header;
	return $self->{_header_sent} = 1;
}

sub no_cache { 0 };
sub default_mime_type { 'text/html' }

=head2 redirect()

$handler->redirect('http://www.spanner.org/')

Causes apache to return a '302 moved' response redirecting the browser to the specified address. Ignored if headers have already been sent.

Any cookies that have been defined are sent with the redirection, in accordance with doctrine and to facilitate login mechanisms, but I am not wholly convinced that all browsers will stash a cookie sent with a 302.

=cut

sub redirect {
	my $self = shift;
	return warn('redirect: headers already sent') if $self->{_header_sent};
	my $url = shift || $self->{redirect} || $self->factory->config('url');
	$self->request->err_headers_out->add('Set-Cookie' => $_) for @{ $self->{set_cookies} };
	$self->request->err_headers_out->add( Location => $url );
	return REDIRECT;
}

=head2 set_cookie()

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
	return warn('set_cookie: headers already sent') if $self->{_header_sent};
	push @{ $self->{cookies_out} }, map { Apache::Cookie->new($self->request, %{ $_ }) } @_;
	return 1;
}

=head2 fail()

$handler->fail("warning: documentation too verbose");

The standard abandon-page routine. Most fatal errors result in a call to fail() with at least one error message. The default method is very basic - just a warning in the log by way of factory->_carp, and a 500 error for the user. I'm assuming that each application will have its own ideas about how to display a more useful message.

Note that the return value from this is usually passed back to Apache, so if you return SERVER_ERROR then a standard error message will be displayed and processing will stop. Return OK if you want your own output to be displayed.

=cut

sub fail {
	my $self = shift;
	my @errors = @_;
	warn @errors;
	return SERVER_ERROR;
	exit;
}

=head1 SEE ALSO

L<Class::DBI> L<Class::DBI::Factory> L<Class::DBI::Factory::Config> L<Class::DBI::Factory::List>

=head1 AUTHOR

William Ross, wross@cpan.org

=head1 COPYRIGHT

Copyright 2001-4 William Ross, spanner ltd.

This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut

1;
