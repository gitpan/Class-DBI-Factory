package My::Handler;
use strict;
use base qw( Class::DBI::Factory::Handler );
use Data::Dumper;

use vars qw( $VERSION );
$VERSION = '0.01';

sub build_page {
	my $self = shift;
    $self->read_input;
    $self->op;
    $self->display;
}

sub read_input {
	my $self = shift;
    $self->{$_} = $self->param($_) for qw(id type op);
    unless ($self->{type} || $self->{id}) {
        my @monikers = grep { $self->param($_) } @{ $self->factory->classes };
        my $moniker = $monikers[0];
        $self->{type} = $moniker;
        $self->{id} = $self->param($moniker) unless $self->param($moniker) eq 'all';
		$self->delete_param($moniker);
    }
}

sub op {
    my $self = shift;
    my $op = $self->ops( $self->param('op') ) || $self->default_op;
    return $self->$op() if $op;
}

sub ops {
    my $self = shift;
    my $ops = {
        edit => 'edit_prep',
        store => 'update_object',
        delete => 'delete_object',
    };
    return $ops->{$_[0]};
}

sub default_op { 'prep' }

sub prep {
    my $self = shift;
	if ($self->thing) {
		$self->{template} = "one";
	} elsif ($self->type) {
		$self->{template} = "many";
	} else {
		$self->{template} = "front";
	}
}

sub edit_prep {
    my $self = shift;
    return $self->prep unless $self->thing || $self->id eq 'new';
    $self->{template} = 'edit';
}

sub update_object {
    my $self = shift;
    return $self->prep unless $self->type && ($self->thing || $self->id eq 'new');

    my @columns = ($self->thing) ? $self->thing->columns('All') : $self->factory->columns($self->type);
    my %input = map { $_ => $self->param($_) } grep { $self->has_param($_) && $_ ne 'id' } @columns;
    
    if ($self->thing) {
        $self->thing->set( %input );
        $self->thing->update;
    } else {
        $self->thing( $self->factory->create($self->type, \%input) );
    }
    
    $self->{template} = 'one';
}

sub delete_object {
    my $self = shift;
    return $self->prep unless $self->thing;
    $self->thing->delete;
    delete $self->{id};
    $self->{template} = 'many';
}

sub display {
    my $self = shift;
    $self->{template} ||= 'front';
	my $output = $self->assemble_output;
	my $template = $self->{template} . '.' . ($self->config->get('template_suffix') || 'html');
 	$self->process($template, $output, $self->request);
}

sub assemble_output {
    my $self = shift;
    return {
        factory => $self->factory,
        config => $self->factory->config,
        pager => $self->pager,
        type => $self->type,
        id => $self->id,
        thing => $self->thing,
    };
}

sub thing {
    my $self = shift;
    return $self->{thing} if $self->{thing};
    return $self->{thing} = $_[0] if $_[0];
    return unless $self->id && $self->type;
	return $self->{thing} = $self->factory->retrieve($self->type, $self->id);
}

sub pager {
    my $self = shift;
    return $self->{pager} if $self->{pager};
    return $self->{pager} = $_[0] if $_[0];
    return unless $self->type;
    $self->{pager} = $self->factory->pager($self->type, $self->param('step'), $self->param('page'));
    $self->{pager}->retrieve_all;
    return $self->{pager};
}

sub type {
    return shift->{type};
}

sub id {
    return shift->{id};
}

1;