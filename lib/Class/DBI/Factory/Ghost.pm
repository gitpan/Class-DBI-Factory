package Class::DBI::Factory::Ghost;
use strict;
use vars qw( $VERSION $AUTOLOAD );
$VERSION = '0.03';

=head1 NAME

Class::DBI::Factory::Ghost - a minimal data-container used as a precursor for Class::DBI objects when populating forms or otherwise preparing to create a new object from existing data.

=head1 SYNOPSIS

my $thing = Class::DBI::Factory::Ghost->new({
    id => 'new',
    type => $moniker,
    person => $self->session->person,
    parent => $self->param('parent'),
});

$thing->title($input->param('title'));

$thing->solidify if (...);

=head1 INTRODUCTION

The ghost is a loose data-container that can be passed to templates or other processes in place of a full Class::DBI object. Its main purpose is to allow the same forms to be used for both creation and editing of objects, but it can be useful in other settings where you might want to make method calls without knowing whether the object had been stored in the database or not.

It is constructed and queried in largely the same way as a Class::DBI object, except that only the most basic parts of the interface are supported, and it depends on the availability of a L<Class::DBI::Factory> object (or an object of a subclass thereof, such as Delivery) to provide the necessary information about classes and columns.

More elaborate Class::DBI constructions, such as set_sql prototypes and has_* methods will not work: only the simple get-and-set functionality is duplicated here, and obviously anything which relies on cdbi's internal variables will not work.

=head2 new()

Constructs and returns a ghost object. Accepts a hashref of column => value pairs which must include a 'type' or 'moniker' value that corresponds to one of your data classes. Supplied values for other columns can be but don't have to be objects: they will be deflated in the usual way.

  my $temp = Class::DBI::Factory::Ghost->new({
      type => 'cd',
      person => $session->person,
  });  

=cut

sub new {
    my ($class, $data) = @_;
    $data->{id} = 'new';
    return unless $data->{type} && $class->factory->has_class($data->{type});
    return bless $data, $class;
}

=head2 is_ghost()

Returns true, naturally. This isn't of much use unless you put a corresponding C<is_ghost> method in your Class::DBI base class and have it return false.

=cut

sub is_ghost { 1 }

=head2 type()

This is a key value that determines the class a particular object is ghosting, and therefore the columns and relationships it should enter into. It must be set at construction time, so this method just returns the value stored then.

=cut

sub type {
    return shift->{type};
}

=head2 factory()

As usual, calls CDF->instance to get the locally active factory object, whatever locally means in this case.

=head2 factory_class()

Override this method in subclass to use a factory class other than CDF (a subclass of it, presumably). Should return a fully qualified Module::Name.

=cut

sub factory_class { "Class::DBI::Factory" }
sub factory { return shift->factory_class->instance; }

=head2 AUTOLOAD()

Very simple: nothing clever here at all. This provides as a get-and-set method for each of the columns defined by the class that this object is ghosting (ie it uses the type parameter to check method names). Nothing else.

=cut

sub AUTOLOAD {
	my $self = shift;
	my $method_name = $AUTOLOAD;
	$method_name =~ s/.*://;
    return if $method_name eq 'DESTROY';
    return unless $self->find_column($method_name);
    return $self->{$method_name} = shift if @_;
    return $self->{$method_name};
}

=head2 find_column()

Exactly as with a normal Class::DBI class, except that it's a remote enquiry mediated by the factory. 

=cut

sub find_column {
	my $self = shift;
    return $self->factory->find_column($self->type, shift);
}

=head2 just_data()

Returns only that part of the underlying hashref which is needed to create the real version of this object, ie having removed type, id and any extraneous values that have been set but are not columns of the eventual object.

=cut

sub just_data {
	my $self = shift;
    my %data = map { $_ => $self->{$_} } grep { $self->find_column($_) } keys %$self;
    delete $data{id};
    return \%data;
}

=head2 make()

Attempts to produce a real object of the class specified by the type parameter supplied during construction, using the column values of the ghost object.

The created object is returned, but the ghost object remains the same, so it is possible to create several new cdbi objects from one ghost.

  for(@addresses) {
    $ghost->address($_);
    $ghost->make;
  }

But $ghost will no longer be a ghost, even so. C<make> returns nothing if the creation fails, and the $ghost object remains as it was.

=head2 find_or_make()

Behaves exactly as C<make>, except that it calls C<find_or_create> instead of  C<create>: if an object of the relevant class exists containing exactly the values currently stored in this object, that object will be returned instead and no new object created.

=cut

sub make {
	my $self = shift;
	return $self->factory->create($self->type, $self->just_data);
}

sub find_or_make {
	my $self = shift;
    return $self->factory->foc($self->type, $self->just_data);
}

=head1 REQUIRES

=over

=item L<Class::DBI::Factory>

=back

=head1 SEE ALSO

L<Class::DBI> L<Class::DBI::Factory>

=head1 AUTHOR

William Ross, wross@cpan.org

=head1 COPYRIGHT

Copyright 2001-4 William Ross, spanner ltd.

This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut

1;