package OMP::Project;

=head1 NAME

OMP::Project - Information relating to a single project

=head1 SYNOPSIS

  $proj = new OMP::Project( projectid => $projectid );

  $proj->pi("somebody\@somewhere.edu");

  %summary = $proj->summary;
  $xmlsummary = $proj->summary;


=head1 DESCRIPTION

This class manipulates information associated with a single OMP
project.

It is not responsible for storing or retrieving that information from
a project database even though the information stored in that project
database exactly matches that in the class (the database is a
persistent store but the object does not implement that persistence).

=cut

use 5.006;
use strict;
use warnings;
use Carp;
our $VERSION = (qw$Revision$)[1];

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

Object constructor. Takes a hash as argument, the keys of which can
be used to prepopulate the object. The key names must match the
names of the accessor methods (modulo case). If they do not match
they are ignored (for now).

  $proj = new OMP::Project( %args );

Arguments are optional (although at some point a project ID would be
helpful).

=cut

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;

  my $proj = bless {}, $class;

  # Deal with arguments
  if (@_) {
    my %args = @_;

    # rather than populate hash directly use the accessor methods
    # allow for upper cased variants of keys
    for my $key (keys %args) {
      my $method = lc($key);
      if ($proj->can($method)) {
	$proj->$method( $args{$key} );
      }
    }

  }
  return $proj;
}

=back

=head2 Accessor Methods

=over 4

=item B<allocated>

=cut

sub allocated {
  my $self = shift;
  if (@_) { $self->{Allocated} = shift; }
  return $self->{Allocated};
}

=item B<coi>

=cut

sub coi {
  my $self = shift;
  if (@_) { $self->{CoI} = shift; }
  return $self->{CoI};
}

=item B<coiemail>

=cut

sub coiemail {
  my $self = shift;
  if (@_) { $self->{CoIEmail} = shift; }
  return $self->{CoIEmail};
}

=item B<projectid>

=cut

sub country {
  my $self = shift;
  if (@_) { $self->{Country} = shift; }
  return $self->{Country};
}

=item B<password>

=cut

sub password {
  my $self = shift;
  if (@_) { $self->{Password} = shift; }
  return $self->{Password};
}

=item B<pending>

=cut

sub pending {
  my $self = shift;
  if (@_) { $self->{Pending} = shift; }
  return $self->{Pending};
}

=item B<pi>

=cut

sub pi {
  my $self = shift;
  if (@_) { $self->{PI} = shift; }
  return $self->{PI};
}

=item B<piemail>

=cut

sub piemail {
  my $self = shift;
  if (@_) { $self->{PIEmail} = shift; }
  return $self->{PIEmail};
}

=item B<projectid>

=cut

sub projectid {
  my $self = shift;
  if (@_) { $self->{ProjectID} = shift; }
  return $self->{ProjectID};
}

=item B<remaining>

=cut

sub remaining {
  my $self = shift;
  if (@_) { $self->{Remaining} = shift; }
  return $self->{Remaining};
}

=item B<semester>

=cut

sub semester {
  my $self = shift;
  if (@_) { $self->{Semester} = shift; }
  return $self->{Semester};
}

=item B<tagpriority>

=cut

sub tagpriority {
  my $self = shift;
  if (@_) { $self->{TagPriority} = shift; }
  return $self->{TagPriority};
}


=back

=head2 General Methods

=over 4

=item B<summary>

Returns a summary of the project. In list context returns
keys and values of a hash:

  %summary = $proj->summary;

In scalar context returns an XML string describing the
project.

  $xml = $proj->summary;

where the keys match the element names and the project ID
is an ID attribute of the root element:

  <OMPProjectSummary projectid="M01BU53">
    <pi>...</pi>
    <tagpriority>23</tagpriority>
    ...
  </OMPProjectSummary>

=cut

sub summary {
  my $self = shift;

  # retrieve the information from the object
  my %summary;
  for my $key (qw/allocated coi coiemail country password pending
	       pi piemail projectid remaining semester tagpriority/) {
    $summary{$key} = $self->$key;
  }

  if (wantarray) {
    return %summary;
  } else {
    # XML
    my $projectid = $summary{projectid};
    my $xml = "<OMPProjectSummary";
    $xml .= " id=\"$projectid\"" if defined $projectid;
    $xml .= ">\n";

    for my $key (sort keys %summary) {
      next if $key eq 'projectid';
      my $value = $summary{$key};
      if (defined $value) {
	$xml .= "<$key>$value</$key>";
      } else {
	$xml .= "<$key/>";
      }
      $xml .= "\n";
    }
    $xml .= "</OMPProjectSummary>\n";

  }

}


=back

=head1 COPYRIGHT

Copyright (C) 2001 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut

1;
