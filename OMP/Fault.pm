package OMP::Fault;

=head1 NAME

OMP::Fault - A software bug or system fault object

=head1 SYNOPSIS

  use OMP::Fault;

  $fault = new OMP::Fault( %details  );
  $fault->respond( OMP::Fault::Response->new(author => $user,
                                             text => $text) );

  $fault->close_fault();


=head1 DESCRIPTION

This class deals with software bug or fault system objects.  Faults
can be responded to and summarized. Most useful when used in
conjunction with the fault database (see C<OMP::FaultDB>).

=cut

use 5.006;
use warnings;
use strict;
use Carp;

our $VERSION = (qw$Revision$)[1];

# Overloading
use overload '""' => "stringify";


# Lookup tables for fault categories, systems and types
use constant TYPEOTHER => -1;
use constant SYSTEMOTHER => -1;
use constant HUMAN => 0;
use constant OPEN => 0;
use constant CLOSED => 1;

my %DATA = (
	     "CSG" => {
		       SYSTEM => {
				  "Sun/Solaris" => 1,
				  "Alpha/OSF"   => 2,
				  "PC/Windows"  => 3,
				  "VAX/VMS"     => 4,
				  "PC/Linux"    => 5,
				  "Other/Unkown"=> SYSTEMOTHER,
				 },
		       TYPE => {
				Other    => TYPEOTHER,
				Human    => HUMAN,
				Hardware => 1,
				Software => 2,
				Network  => 3,
				Printer  => 4,
			       },
		      },
	     "JCMT" => {
			SYSTEM => {
				   Antenna => 1,
				   Instrument => 2,
				   Computer => 3,
				   Carousel => 4,
				   "Other/Unknown" => SYSTEMOTHER,
				  },
			TYPE => {
				 Mechanical => 1,
				 Electronic => 2,
				 Software => 3,
				 Cryogenic => 4,
				 Other => TYPEOTHER,
				 Human => HUMAN,
				},

		       },
	     "UKIRT" => {
			 SYSTEM => {
				    Telescope => 1,
				    Instrument => 2,
				    Computer => 3,
				    Dome => 4,
				    Ancillaries => 5,
				    "Other/Unknown" => SYSTEMOTHER,
				   },
			 TYPE => {
				  Mechanical => 1,
				  Electronic => 2,
				  Software => 3,
				  Cryogenic => 4,
				  Other => TYPEOTHER,
				  Human => HUMAN,
				 },
			},
	     "OMP"   => {
			 SYSTEM => {
				    Feedback => 1,
				    DBServer => 2,
				    ObservingTool => 3,
				    QueryTool => 4,
				    Sequencer => 5,
				    "Other/Unknown" => SYSTEMOTHER,
				   },
			 TYPE => {
				  GUI => 1,
				  Exception => 2,
				  Scheduling => 3,
				  Other => TYPEOTHER,
				  Human => HUMAN,
				 },
			},
	    );

# Urgency
my %URGENCY = (
	       Urgent => 0,
	       Normal => 1,
	       Info   => 2,
	      );

# Status
my %STATUS = (
	      Open => OPEN,
	      Closed => CLOSED,
	     );

# Now invert %DATA and %URGENCY
my %INVERSE_URGENCY;
for (keys %URGENCY) {
  $INVERSE_URGENCY{ $URGENCY{$_} } = $_;
}

my %INVERSE_STATUS;
for (keys %STATUS) {
  $INVERSE_STATUS{ $STATUS{$_} } = $_;
}

# Loop over categories
my %INVERSE;
for my $cat ( keys %DATA) {

  # Crate new hash for categories
  $INVERSE{$cat} = {};

  # Loop over systems and types
  for my $sys ( keys %{ $DATA{$cat} } ) {

    # Create new hash for systems and types
    $INVERSE{$cat}{$sys} = {};

    for my $strings ( keys %{ $DATA{$cat}{$sys} } ) {
      $INVERSE{$cat}{$sys}{ $DATA{$cat}{$sys}{$strings} } = $strings;
    }

  }

}

=head1 METHODS

=head2 Class Methods

These methods can be used to find details of the available fault
categories, systems and types.

=over 4

=item B<faultCategories>

Return the different global fault categories available to this system.
This returns a list of supported categories (eg JCMT and UKIRT). The
subsystems and fault types change depending on global fault category.

  @categories = OMP::Fault->faultCategories();

=cut

sub faultCategories {
  return keys %DATA;
}


=item B<faultSystems>

For a specific fault category (eg JCMT or UKIRT) return a hash
containing the allowed fault systems (as keys) and the constants
required to identify those systems in the database.

  %systems = OMP::Fault->faultSystems( "JCMT" );

Returns empty list if the fault category is not recognized.

=cut

sub faultSystems {
  my $class = shift;
  my $category = uc(shift);

  if (exists $DATA{$category}) {
    return $DATA{$category}{SYSTEM};
  } else {
    return ();
  }
}

=item B<faultTypes>

For a specific fault category (eg JCMT or UKIRT) return a hash
containing the allowed fault types (as keys) and the constants
required to identify those types in the database.

  %types = OMP::Fault->faultTypes( "JCMT" );

Returns empty list if the fault category is not recognized.

=cut

sub faultTypes {
  my $class = shift;
  my $category = uc(shift);

  if (exists $DATA{$category}) {
    return $DATA{$category}{TYPE};
  } else {
    return ();
  }
}

=item B<faultUrgency>

Return a hash containing the different types of urgency that can
be associated with fixing a particular fault.

  %urgency = OMP::Fault->faultUrgency();

=cut

sub faultUrgency {
  my $class = shift;
  return %URGENCY;
}

=item B<faultStatus>

Return a hash containing the different statuses that can be associated
with a fault.

  %status = OMP::Fault->faultStatus();

=cut

sub faultStatus {
  my $class = shift;
  return %STATUS;
}

=back

=head2 Public Methods

=over 4

=item B<new>

Fault constructor. A fault must be created with the following information:

  category  - fault category: UKIRT, JCMT, CSG or OMP [string]
  subject     - short summary of the fault            [string]
  faultdate - date the fault occurred                 [date]
  timelost  - time lost to the fault (hours)        [float]
  system    - fault category                        [integer]
  type      - fault type                            [integer]
  urgency   - how urgent is the fault?              [integer]
  entity    - specific thing (eg instrument or computer name) [string]
  status    - is the fault OPEN or CLOSED [integer]
  fault     - a fault "response" object

The fault message (which includes the submitting user) must be
supplied as a C<OMP::Fault::Response> object.

The values for type, urgency, system and status can be obtained by
using the C<faultTypes>, C<faultUrgency>, C<faultSystems> and
C<faultStatus> methods. These values should be supplied as a hash:

  my $fault = new OMP::Fault( %details );

Optional keys are: "timelost" (assumes 0hrs), "faultdate" (assumes
unknown), "urgency" (assumes not urgent - "normal"), "entity" (assumes
not relevant), "system" (assumes "other/unknown") and "type" (assumes
"other"). This means that the required information is "category" and
the fault message itself (in the form of a response object).

The fault ID can not be constructed automatically by this object
since the fault ID must be unique and can not be determined without
seeing which other faults have been filed.

=cut

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;

  # Read the arguments
  my %args = @_;

  # Special case - change "fault" to "responses" so that
  # it matches the methods. This allows use to use something
  # that sounds more obvious for an initial fault than a response
  if (exists $args{fault}) {
    $args{responses} = $args{fault};
    delete $args{fault};
  }

  # Create the object with default state
  my $fault = bless {
		     FaultID => undef,
		     Type => TYPEOTHER,
		     System => SYSTEMOTHER,
		     TimeLost => 0,
		     FaultDate => undef,
		     Urgency => $URGENCY{Normal},
		     Entity => undef,
		     Category => undef,
		     Responses => [],
		     Status => OPEN,
		     Subject => undef,
		    }, $class;

  # Go through the input args invoking relevant methods
  for my $key (keys %args) {
    my $method = lc($key);
    if ($fault->can($method)) {
      $fault->$method( $args{$key});
    }
  }


  # Cause some trouble if there is no category
  croak "Must supply a fault category (eg UKIRT or JCMT)"
    unless defined $fault->category;

  # Really need to check that someone has supplied
  # a fault body
  croak "Must supply an initial fault body"
    unless scalar(@{ $fault->responses });

  return $fault;
}

=back

=head2 Accessor Methods

=over 4

=item B<id>

Retrieve of store the fault ID. The fault ID can only be determined
from using the context of an associated fault database (since it
depends on previous faults).

  $id = $fault->id();
  $fault->id( $id  );

In general the fault ID is the same as that used in C<perlbug>. That
is C<YYYYMMDD.NNN> where the numbers before the decimal point are the
date the fault is filed (obtained either from the fault date or, if
not supplied since it is not known, from the date of the first
response (ie the filing)) and that after the decimal point is a 3
digit number referring to the number of faults filed on that date.

=cut

sub id {
  my $self = shift;
  if (@_) { $self->{FaultID} = shift; }
  return $self->{FaultID};
}

=item B<faultid>

Synonym for C<id>

=cut

sub faultid {
  my $self = shift;
  return $self->id(@_);
}

=item B<type>

Fault type (supplied as an integer - see C<faultTypes>).

  $type = $fault->type();
  $fault->type( $type  );

=cut

sub type {
  my $self = shift;
  if (@_) { $self->{Type} = shift; }
  return $self->{Type};
}

=item B<system>

Fault system (supplied as an integer - see C<faultSystems>).

  $sys = $fault->system();
  $fault->system( $sys  );

=cut

sub system {
  my $self = shift;
  if (@_) { $self->{System} = shift; }
  return $self->{System};
}

=item B<typeText>

Return the textual description of the current fault type.
A fault can not be modified using this method.

  $type = $fault->typeText();

=cut

sub typeText {
  my $self = shift;
  return $INVERSE{$self->category}{TYPE}{$self->type};
}

=item B<systemText>

Return the textual description of the current fault system.
A fault can not be modified using this method.

  $system = $fault->systemText();

=cut

sub systemText {
  my $self = shift;
  return $INVERSE{$self->category}{SYSTEM}{$self->system};
}

=item B<statusText>

Return the textual description of the current fault status.
A fault can not be modified using this method.

  $status = $fault->statusText();

=cut

sub statusText {
  my $self = shift;
  return $INVERSE_STATUS{$self->status};
}

=item B<urgencyText>

=cut

sub urgencyText {
  my $self = shift;
  return $INVERSE_URGENCY{$self->urgency};
}

=item B<isUrgent>

True if the fault is urgent.

  $isurgent = $fault->isUrgent();

=cut

sub isUrgent {
  my $self = shift;
  my $urgcode = $self->urgency;
  return ( $urgcode == $URGENCY{Urgent} ? 1 : 0);
}


=item B<isOpen>

Is the fault open (1) or closed (0)?

=cut

sub isOpen {
  my $self = shift;
  my $status = $self->status;
  return ( $status == OPEN ? 1 : 0 );
}

=item B<subject>

Short description of the fault that can be easily displayed
in summary tables and in email responses.

  $subj = $fault->subject();
  $fault->subject( $subj  );

=cut

sub subject {
  my $self = shift;
  if (@_) { $self->{Subject} = shift; }
  return $self->{Subject};
}

=item B<status>

Fault status (supplied as an integer - see C<faultStatus>).
Indicates whether the fault is "open" or "closed".

  $status = $fault->status();
  $fault->status( $status  );

=cut

sub status {
  my $self = shift;
  if (@_) { $self->{Status} = shift; }
  return $self->{Status};
}

=item B<timelost>

Time lost to the fault in hours.

  $tl = $fault->timelost();
  $fault->timelost( $tl  );

=cut

sub timelost {
  my $self = shift;
  if (@_) { $self->{TimeLost} = shift; }
  return $self->{TimeLost};
}

=item B<faultdate>

Date the fault occurred. This may be different from the date
it was filed. Not required (default is that the date it was
filed is good enough). Must be a C<Time::Piece> object
(or undef).

  $date = $fault->faultdate();
  $fault->faultdate( $date  );

=cut

sub faultdate {
  my $self = shift;
  if (@_) { 
    my $date = shift;
    croak "Date must be supplied as Time::Piece object"
      if (defined $date && ! UNIVERSAL::isa( $date, "Time::Piece" ));
    $self->{FaultDate} = $date;
  }
  return $self->{FaultDate};
}

=item B<urgency>

Urgency associated with the fault. Options are "urgent", "normal"
and "info" (the latter is used for informational faults that
require no response). See C<faultUrgencies> for the associated
integer codes that must be supplied.

  $urgency = $fault->urgency();
  $fault->urgency( $urgency  );

Still need to decide whether to use integers or strings.

=cut

sub urgency {
  my $self = shift;
  if (@_) { $self->{Urgency} = shift; }
  return $self->{Urgency};
}

=item B<entity>

Context sensitive information that should be associated with the
fault. In general this is an instrument name or a computer
name. Can be left empty.

  $thing = $fault->entity();
  $fault->entity( $thing  );

=cut

sub entity {
  my $self = shift;
  if (@_) { $self->{Entity} = shift; }
  return $self->{Entity};
}

=item B<category>

The main fault category that defines the entire system. This
defines what the type and system translations are. Examples
are "UKIRT", "JCMT" or "OMP".

  $category = $fault->category();
  $fault->category( $cat  );

Must be provided.

=cut

sub category{
  my $self = shift;
  if (@_) { $self->{Category} = uc(shift); }
  return $self->{Category};
}

=item B<responses>

The responses associated with the fault. There will always be at least
one response (the initial fault). Returned as an array of
C<OMP::Fault::Response> objects. The order corresponds to the sequence
in which the fault responses were filed.

If arguments are supplied it is assumed that they should
be pushed on to the response array.

  $fault->responses( @responses );

If the first argument is a reference to an array it is assumed
that all the existing responses are to be replaced.

  $fault->responses( \@responses );

All arguments are checked to make sure that they are
C<OMP::Fault::Response> objects (even if contained within an
array ref).

If an explicit C<undef> is sent as first argument all responses
are cleared.

In a scalar context returns a reference to an array (a copy of the
actual array). In list context returns the response objects as a list.

  @responses = $fault->responses();
  $responses = $fault->responses;

When new responses are stored the first response object has its
isfault flag set to "true" and all other responses have their isfault
flags set to "false".

See also C<respond> method.

=cut

sub responses {
  my $self = shift;
  if (@_) { 

    # If we have an array ref we are replacing
    my $replace = 0;
    my @input;
    if ( ref($_[0]) eq "ARRAY") {
      # We are replacing current entries
      $replace = 1;
      @input = @{ $_[0] };
    } elsif ( ! defined $_[0] ) {
      # Replace with empty
      $replace = 1;
    } else {
      @input = @_;
    }

    # Check they are the right class
    for (@input) {
      croak "Responses must be in class OMP::Fault::Response"
	unless UNIVERSAL::isa( $_, "OMP::Fault::Response");
    }

    # Now store or overwrite
    if ($replace) {
      $self->{Responses} = \@input;
    } else {
      push(@{$self->{Responses}}, @input);
    }

    # Now modify the isfault flags
    my $i = 0;
    for (@{ $self->{Responses} }) {
      my $isfault = ($i == 0 ? 1 : 0);
      $_->isfault( $isfault );
      $i++;
    }

  }

  # See if we are in void context
  my $want = wantarray;
  return unless defined $want;

  # Else return list or reference
  if (wantarray) {
    return @{ $self->{Responses} };
  } else {
    my @copy = @{ $self->{Responses} };
    return \@copy;
  }
}

=item B<author>

Returns the name of the person who initially filed the
fault.

  $author = $fault->author();

This information is retrieved from the first response object.

=cut

sub author {
  my $self = shift;
  my $firstresp = $self->responses->[0];
  return $firstresp->author;
}

=item B<date>

Date associated with the initial filing of the fault. If the time of
the fault has not been specified (ie C<faultdate> is undefined) the
time the fault response was filed will be used instead.

  $date = $fault->date;

=cut

sub date {
  my $self = shift;

  # Look at the fault date
  my $faultdate = $self->faultdate;
  return $faultdate if $faultdate;

  # Else look at the first response
  my $firstresp = $self->responses->[0];
  return $firstresp->date;
}

=back

=head2 General Methods

=over 4

=item B<close_fault>

Change the status of the fault to "CLOSED".

=cut

sub close_fault {
  my $self = shift;
  $self->status( CLOSED );
}

=item B<respond>

Add a fault response.

  $fault->respond( $response );

A convenience wrapper around the C<responses> method.
(effectively a synonym).

=cut

sub respond {
  my $self = shift;
  my $response = shift;
  $self->responses( $response );
}

=item B<stringify>

Convert the fault object into plain text for quick display.
[currently HTML responses will look strange].

This is configured as the default stringifcation overload
and returns strings in the JAC fault style.

=cut

sub stringify {
  my $self = shift;

  # Get the responses
  my @responses = $self->responses;

  # If there is not even one response return empty string
  return '' unless @responses;

  # Get the main descriptive information for the top
  my $author = $responses[0]->author;
  my $date = $responses[0]->date;
  my $firstresponse = $responses[0]->text;
  my $tlost = $self->timelost;
  my $urgcode  = $self->urgency;
  my $category = $self->category;
  my $faultdate = $self->faultdate;
  my $entity = $self->entity;

  # Get the time and date as separate things
  my $time = $date->strftime("%H:%M");
  my $day  = $date->strftime("%Y-%m-%d");

  # Actual time of fault as string
  my $actfaultdate;
  if (defined $actfaultdate) {
    $actfaultdate = $faultdate->strftime("%H:%M") . "UT";
  } else {
    $actfaultdate = "UNKNOWN";
  }

  # Convert system, type and status codes to a string.
  my $system = $self->systemText;
  my $type = $self->typeText;
  my $status = $self->statusText;

  # Only want to say something about urgency if it is urgent
  my $urgency = '';
  if ($urgcode == $URGENCY{Urgent}) {
    $urgency = "                     ***** Fault is URGENT ****\n";
  }

  # Guess email address
  my $email = lc($category) . "_faults";

  # Entity has a special meaning if the system is Instrument
  # or we have CSG. Ignore that for now

  # Now build up the message
  my $output = 
"--------------------------------------------------------------------------------\n".
"    Report by     :  $author\n".
"                                         date: $day\n".
"    System is     :  $system\n".
"                                         time: $time\n".
"    Fault type is :  $type\n".
"                                         loss: $tlost\n".
"    Status        :  $status\n".
"\n".
"    Notice will be sent to: $email\n".
"\n".
"$urgency".
"~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n".
"                                Actual time of failure: $actfaultdate\n".
"\n".
"$firstresponse\n\n";

  # Now loop over remaining responses and add them in
  for (@responses[1..$#responses]) {
    $output .= "$_\n";
  }

  return $output;
}

=back

=head1 SEE ALSO

C<OMP::Fault::Response>, C<OMP::FaultDB>.

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
