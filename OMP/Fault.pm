package OMP::Fault;

=head1 NAME

OMP::Fault - A software bug or system fault object

=head1 SYNOPSIS

  use OMP::Fault;

  $fault = new OMP::Fault( %details  );
  $fault->respond( OMP::Fault::Response->new($user, $text, $date) );



=head1 DESCRIPTION

This class deals with software bug or fault system objects.  Faults
can be responded to and summarized. Most useful when used in
conjunction with the fault database (see C<OMP::FaultDB>).

=cut

use 5.006;
use warnings;
use strict;
use Carp;

# Lookup tables for fault categories, systems and types
use constant TYPEOTHER => -1;
use constant SYSTEMOTHER => -1;
use constant HUMAN => 0;

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
				    Sequencer => 5
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

sub faultSystems {
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

Returns empty list if the fault category is not recognized.

=cut

sub faultUrgency {
  my $class = shift;
  return %URGENCY;
}

=back

=head2 Public Methods

=over 4

=item B<new>

Fault constructor. A fault must be created with the following information:

  category  - fault category: UKIRT, JCMT, CSG or OMP [string]
  faultdate - date the fault occurred               [date]
  timelost  - time lost to the fault (hours)        [float]
  system    - fault category                        [integer]
  type      - fault type                            [integer]
  urgency   - how urgent is the fault?              [integer]
  thing     - specific thing (eg instrument or computer name) [string]
  fault     - a fault "response" object

The fault message (which includes the submitting user) must be
supplied as a C<OMP::Fault::Response> object.

The values for type, urgency and system can be obtained by using
the C<faultTypes>, C<faultUrgency> and C<faultSystems> method. These
values should  be supplied as a hash:

  my $fault = new OMP::Fault( %details );

Optional keys are: "timelost" (assumes 0hrs), "faultdate" (assumes
unknown), "urgency" (assumes not urgent - "normal"), "thing" (assumes
not relevant), "system" (assumes "other/unknown") and "type" (assumes
"other"). This means that the required information is "category" and
the fault message itself.

The fault ID can not be constructed automatically by this object
since the fault ID must be unique and can not be determined without
seeing which other faults have been filed.

=cut

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;

  # Read the arguments
  my %args = @_;

  my $fault = bless {
		     FaultID => undef,
		     Type => TYPEOTHER,
		     System => SYSTEMOTHER,
		     TimeLost => 0,
		     FaultDate => undef,
		     Urgency => $URGENCY{Normal},
		     Thing => undef,
		     Category => undef,
		     Responses => [],
		    } $class;

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
    unless scalar(@{ $fault->respones });

  return $fault;
}

=back

=head2 Internal Methods

=over 4

=item B<blah>

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
