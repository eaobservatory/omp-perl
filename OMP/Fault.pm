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

use Time::Piece;
use Time::Seconds;

our $VERSION = (qw$Revision$)[1];

# Overloading
use overload '""' => "stringify";


# Lookup tables for fault categories, systems and types
use constant TYPEOTHER => -1;
use constant SYSTEMOTHER => -1;
use constant HUMAN => 0;
use constant OPEN => 0;
use constant CLOSED => 1;
use constant WORKS_FOR_ME => 2;
use constant NOT_A_FAULT => 3;
use constant WON_T_BE_FIXED => 4;
use constant DUPLICATE => 5;
use constant WILL_BE_FIXED => 6;
use constant SUN_SOLARIS => 1000;
use constant ALPHA_OSF => 1001;
use constant PC_WINDOWS => 1002;
use constant VAX_VMS => 1003;
use constant PC_LINUX => 1004;
use constant HARDWARE => 1005;
use constant SOFTWARE => 1006;
use constant NETWORK => 1007;
use constant PRINTER => 1008;
use constant ANTENNA => 1009;
use constant INSTRUMENT => 1010;
use constant COMPUTER => 1011;
use constant CAROUSEL => 1012;
use constant MECHANICAL => 1013;
use constant ELECTRONIC => 1014;
use constant CRYOGENIC => 1015;
use constant TELESCOPE => 1016;
use constant ANCILLARIES => 1017;
use constant DOME => 1018;
use constant FEEDBACK_WEB => 1019;
use constant DBSERVER => 1020;
use constant OBSERVINGTOOL => 1021;
use constant QUERYTOOL => 1022;
use constant SEQUENCER_QUEUE => 1023;
use constant TRANSLATOR => 1024;
use constant MONITOR_CONSOLE => 1025;
use constant GUI => 1026;
use constant EXCEPTION => 1027;
use constant SCHEDULING => 1028;
use constant BUG => 1029;
use constant FEATURE_REQUEST => 1030;
use constant JCMT_OT => 1031;
use constant UKIRT_OT => 1032;
use constant OMP_FEEDBACK_SYSTEM => 1033;
use constant ORAC_DR => 1034;
use constant MISCELLANEOUS => 1035;
use constant INSTRUMENT_CGS4 => 1036;
use constant INSTRUMENT_UFTI => 1037;
use constant INSTRUMENT_UIST => 1038;
use constant INSTRUMENT_MICHELLE => 1039;
use constant INSTRUMENT_WFCAM => 1040;
use constant INSTRUMENT_WFS => 1041;
use constant INSTRUMENT_VISITOR => 1042;
use constant INSTRUMENT_OTHER_UNKNOWN => 1043;
use constant BACK_END_DAS => 1044;
use constant BACK_END_ACSIS => 1045;
use constant BACK_END_CBE => 1046;
use constant BACK_END_IFD => 1047;
use constant FRONT_END_RXA => 1048;
use constant FRONT_END_RXB => 1049;
use constant FRONT_END_RXW => 1050;
use constant FRONT_END_HARP => 2001;
use constant SCUBA => 1051;
use constant SCUBA2 => 1065;
use constant WATER_VAPOR_RAD => 1052;
use constant IFS => 1053;
use constant FRONT_END_RXH3 => 1054;
use constant SURFACE => 1055;
use constant OT => 1056;
use constant OT_LIBRARIES => 1057;
use constant OBSERVING_DATABASE => 1058;
use constant JCMT_DR => 1059;
use constant SPECX => 1060;
use constant AIPSPLUSPLUS => 1061;
use constant SURF => 1062;
use constant STARLINK => 1063;
use constant WORF => 1064;

# Safety - severity.
use constant SAFETY_CLARAFICATION_SEVERITY => 3000;
use constant {
  EQUIP_DAMAGE => SAFETY_CLARAFICATION_SEVERITY + 1,
  MINOR_INJURY => SAFETY_CLARAFICATION_SEVERITY + 2,
  MAJOR_INJURY => SAFETY_CLARAFICATION_SEVERITY + 3,
  INJURY_DEATH => SAFETY_CLARAFICATION_SEVERITY + 4,
  ENV_ISSUE    => SAFETY_CLARAFICATION_SEVERITY + 5,
  ENV_INCIDENT => SAFETY_CLARAFICATION_SEVERITY + 6,
};

# Safety - type.
use constant SAFETY_CLARAFICATION_TYPE => 3010;
use constant {
  SAFETY_CONCERN => SAFETY_CLARAFICATION_TYPE + 1,
  NEAR_MISS      => SAFETY_CLARAFICATION_TYPE + 2,
  INCIDENT       => SAFETY_CLARAFICATION_TYPE + 3,
  ENVIRONMENT    => SAFETY_CLARAFICATION_TYPE + 4,
};

# Safety - action/status.
use constant NO_ACTION => 3020;
use constant {
  IMMEDIATE_ACTION          => NO_ACTION + 1,
  FOLLOW_UP                 => NO_ACTION + 2,
  REFER_TO_SAFETY_COMMITTEE => NO_ACTION + 3,
};

#  Places.
use constant IN_TRANSIT => 4000;
use constant {
  JAC    => IN_TRANSIT + 1,
  HP     => IN_TRANSIT + 2,
  JCMT   => IN_TRANSIT + 3,
  UKIRT  => IN_TRANSIT + 4,
};

# Facility - system.
use constant TOILET => 5000;
use constant {
  OFFICE       => TOILET + 1,
  LIBRARY      => TOILET + 2,
  COMP_ROOM    => TOILET + 3,
  MEETING_ROOM => TOILET + 4,
  LAB          => TOILET + 5,
  WORKSHOP     => TOILET + 6,
  VEHICLE_BAY  => TOILET + 7,
  CAR_PARK     => TOILET + 8,
};

# Facility - type.
use constant INSECT => 5020;
use constant {
  LEAK            => INSECT + 1,
  PLUMBING        => INSECT + 2,
  AC_DEHUMIDIFIER => INSECT + 3,
  ALARM_SYS       => INSECT + 4,
  ELECTTICAL      => INSECT + 5,
};

# Mailing list
my %MAILLIST = (
                  'CSG'   => 'csg_faults@jach.hawaii.edu'   ,
                  'JCMT'  => 'jcmt_faults@jach.hawaii.edu'  ,
                  'UKIRT' => 'ukirt_faults@jach.hawaii.edu' ,
                  'OMP'   => 'omp_faults@jach.hawaii.edu'   ,
                  'DR'    => 'dr_faults@jach.hawaii.edu'    ,
                  'SAFETY'   => 'safety_faults@jach.hawaii.edu'   ,
                  'FACILITY' => 'facility_faults@jach.hawaii.edu' ,
               );

my %DATA = (
             "CSG" => {
                       SYSTEM => {
                                  "Sun/Solaris" => SUN_SOLARIS,
                                  "Alpha/OSF"   => ALPHA_OSF,
                                  "PC/Windows"  => PC_WINDOWS,
                                  "VAX/VMS"     => VAX_VMS,
                                  "PC/Linux"    => PC_LINUX,
                                  "Other/Unknown"=> SYSTEMOTHER,
                                 },
                       TYPE => {
                                Other    => TYPEOTHER,
                                Human    => HUMAN,
                                Hardware => HARDWARE,
                                Software => SOFTWARE,
                                Network  => NETWORK,
                                Printer  => PRINTER,
                               },
                      },
             "JCMT" => {
                        SYSTEM => {
                                   Telescope => TELESCOPE,
                                   "Back End - DAS" => BACK_END_DAS,
                                   "Back End - ACSIS" => BACK_END_ACSIS,
                                   "Back End - CBE" => BACK_END_CBE,
                                   "Back End - IFD" => BACK_END_IFD,
                                   "Front End - HARP" => FRONT_END_HARP,
                                   "Front End - RxA" => FRONT_END_RXA,
                                   "Front End - RxB" => FRONT_END_RXB,
                                   "Front End - RxW" => FRONT_END_RXW,
                                   "Front End - RxH3" => FRONT_END_RXH3,
                                   Surface => SURFACE,
                                   SCUBA   => SCUBA,
                                   'SCUBA-2' => SCUBA2,
                                   IFS => IFS,
                                   "Water Vapor Rad." => WATER_VAPOR_RAD,
                                   "Visitor Instruments" => INSTRUMENT_VISITOR,
                                   Instrument => INSTRUMENT_OTHER_UNKNOWN,
                                   Computer => COMPUTER,
                                   Carousel => CAROUSEL,
                                   "Other/Unknown" => SYSTEMOTHER,
                                  },
                        TYPE => {
                                 Mechanical => MECHANICAL,
                                 Electronic => ELECTRONIC,
                                 Software => SOFTWARE,
                                 Cryogenic => CRYOGENIC,
                                 "Other/Unknown" => TYPEOTHER,
                                 Human => HUMAN,
                                },
                       },
             "UKIRT" => {
                         SYSTEM => {
                                    Telescope => TELESCOPE,
                                    "Computer" => COMPUTER,
                                    OT => OT,
                                    "OT Libraries" => OT_LIBRARIES,
                                    "ORAC-DR" => ORAC_DR,
                                    "Query Tool" => QUERYTOOL,
                                    "Sequence Console" => SEQUENCER_QUEUE,
                                    Translator => TRANSLATOR,
                                    "Observing Database" => DBSERVER,
                                    "Web feedback system" => OMP_FEEDBACK_SYSTEM,
                                    Dome => DOME,
                                    Ancillaries => ANCILLARIES,
                                    "Instrument - CGS4" => INSTRUMENT_CGS4,
                                    "Instrument - UFTI" => INSTRUMENT_UFTI,
                                    "Instrument - UIST" => INSTRUMENT_UIST,
                                    "Instrument - MICHELLE" => INSTRUMENT_MICHELLE,
                                    "Instrument - WFCAM" => INSTRUMENT_WFCAM,
                                    "Instrument - WFS" => INSTRUMENT_WFS,
                                    "Instrument - Visitor" => INSTRUMENT_VISITOR,
                                    "Instrument - Other/Unknown" => INSTRUMENT_OTHER_UNKNOWN,
                                    "Other/Unknown" => SYSTEMOTHER,
                                   },
                         TYPE => {
                                  Mechanical => MECHANICAL,
                                  Electronic => ELECTRONIC,
                                  "Software" => SOFTWARE,
                                  Network => NETWORK,
                                  Cryogenic => CRYOGENIC,
                                  "Other/Unknown" => TYPEOTHER,
                                  Human => HUMAN,
                                 },
                        },
             "OMP"   => {
                         SYSTEM => {
                                    "Feedback/Web" => FEEDBACK_WEB,
                                    DBServer => DBSERVER,
                                    ObservingTool => OBSERVINGTOOL,
                                    QueryTool => QUERYTOOL,
                                    "Sequencer/Queue" => SEQUENCER_QUEUE,
                                    Translator => TRANSLATOR,
                                    "Monitor/Console" => MONITOR_CONSOLE,
                                    "Other/Unknown" => SYSTEMOTHER,
                                   },
                         TYPE => {
                                  GUI => GUI,
                                  Exception => EXCEPTION,
                                  Scheduling => SCHEDULING,
                                  Bug => BUG,
                                  "Feature Request"=> FEATURE_REQUEST,
                                  Other => TYPEOTHER,
                                  Human => HUMAN,
                                 },
                        },
            "DR"     => {
                         SYSTEM => {
                                    "JCMT-DR" => JCMT_DR,
                                    SPECX => SPECX,
                                    "AIPS++" => AIPSPLUSPLUS,
                                    SURF => SURF,
                                    STARLINK => STARLINK,
                                    "ORAC-DR" => ORAC_DR,
                                    OTHER => SYSTEMOTHER,
                                   },
                         TYPE => {
                                  Bug => BUG,
                                  "Feature Request" => FEATURE_REQUEST,
                                  Human => HUMAN,
                                  Other => TYPEOTHER,
                                 },
                        },
            'SAFETY' => {
                          'SEVERITY' => {
                                          'Severe injury or death' => INJURY_DEATH,
                                          'Major injury' => MAJOR_INJURY,
                                          'Minor injury' => MINOR_INJURY,
                                          'Equipment damage' => EQUIP_DAMAGE,
                                          'Clarification' => SAFETY_CLARAFICATION_SEVERITY,
                                          'Environmental issue' => ENV_ISSUE,
                                          'Environmental incident' => ENV_INCIDENT,
                                        },
                           'TYPE' => {
                                        'Incident' => INCIDENT,
                                        'Near miss' => NEAR_MISS,
                                        'Safety concern' => SAFETY_CONCERN,
                                        'Safety clarification' => SAFETY_CLARAFICATION_TYPE,
                                        'Environment' => ENVIRONMENT,
                                      },
                        },
            'FACILITY' => {
                            'SYSTEM' => {
                                          'Toilet'        => TOILET       ,
                                          'Office'        => OFFICE       ,
                                          'Library'       => LIBRARY      ,
                                          'Computer Room' => COMP_ROOM    ,
                                          'Meeting Room'  => MEETING_ROOM ,
                                          'Laboratory'    => LAB          ,
                                          'Workshop'      => WORKSHOP     ,
                                          'Vehicle Bay'   => VEHICLE_BAY  ,
                                          'Car Park'      => CAR_PARK     ,
                                          'Other'         => SYSTEMOTHER  ,
                                        },
                            'TYPE' => {
                                        'Insect'              => INSECT          ,
                                        'Leak'                => LEAK            ,
                                        'Plumbing'            => PLUMBING        ,
                                        'A/C or dehumidifier' => AC_DEHUMIDIFIER ,
                                        'Alarm system'        => ALARM_SYS       ,
                                        'Electrical'          => ELECTTICAL      ,
                                        'Network'             => NETWORK         ,
                                        'Computer'            => COMPUTER        ,
                                        'Other'               => TYPEOTHER       ,
                                      },
                          },
            );

my %LOCATION = (
                  'UKIRT' => UKIRT,
                  'JCMT' => JCMT,
                  'HP' => HP,
                  'JAC' => JAC,
                  'In transit' => IN_TRANSIT
                );

# Miscellaneous options for each category
my %OPTIONS = (
               CSG => {
                       CAN_LOSE_TIME => 0,
                       CAN_ASSOC_PROJECTS => 0,
                       IS_TELESCOPE => 0,
                      },
               JCMT => {
                        CAN_LOSE_TIME => 1,
                        CAN_ASSOC_PROJECTS => 1,
                        IS_TELESCOPE => 1,
                       },
               OMP => {
                       CAN_LOSE_TIME => 0,
                       CAN_ASSOC_PROJECTS => 0,
                       IS_TELESCOPE => 0,
                      },
               UKIRT => {
                         CAN_LOSE_TIME => 1,
                         CAN_ASSOC_PROJECTS => 1,
                         IS_TELESCOPE => 1,
                        },
               DR => {
                      CAN_LOSE_TIME => 0,
                      CAN_ASSOC_PROJECTS => 0,
                      IS_TELESCOPE => 0,
                     },
               'SAFETY' => {
                              CAN_LOSE_TIME => 0,
                              CAN_ASSOC_PROJECTS => 0,
                              IS_TELESCOPE => 0,
                            }
              );

# Urgency
my %URGENCY = (
               Urgent => 0,
               Normal => 1,
               Info   => 2,
              );

my %CONDITION = (
                 Chronic => 0,
                 Normal  => 1,
                );

my %STATUS_OPEN = (
                   Open                   => OPEN,
                   "Open - Will be fixed" => WILL_BE_FIXED,
                  );

my %STATUS_CLOSED = (
                     Closed           => CLOSED,
                     "Works for me"   => WORKS_FOR_ME,
                     "Not a fault"    => NOT_A_FAULT,
                     "Won't be fixed" => WON_T_BE_FIXED,
                     Duplicate        => DUPLICATE,
                    );

my %SAFETY_STATUS_OPEN = (
                            'Immediate action required' => IMMEDIATE_ACTION,
                            'Follow up required' => FOLLOW_UP,
                            'Refer to safety commitee' => REFER_TO_SAFETY_COMMITTEE,
                          );

my %SAFETY_STATUS_CLOSED = (
                              'No futher action' => NO_ACTION,
                              'Closed' => $STATUS_CLOSED{'Closed'}
                            );

my %STATUS = ( %STATUS_OPEN, %STATUS_CLOSED );

my %SAFETY_STATUS = ( %SAFETY_STATUS_OPEN, %SAFETY_STATUS_CLOSED );

# Now invert %DATA, %URGENCY, and %CONDITION
my %INVERSE_URGENCY;
for (keys %URGENCY) {
  $INVERSE_URGENCY{ $URGENCY{$_} } = $_;
}

my %INVERSE_CONDITION;
for (keys %CONDITION) {
  $INVERSE_CONDITION{ $CONDITION{$_} } = $_;
}

my %INVERSE_STATUS;
for (keys %STATUS) {
  $INVERSE_STATUS{ $STATUS{$_} } = $_;
}

for (keys %SAFETY_STATUS ) {
  $INVERSE_STATUS{ $SAFETY_STATUS{$_} } = $_;
}

my %INVERSE_PLACE;
$INVERSE_PLACE{ $LOCATION{ $_ } } = $_
  for keys %LOCATION;


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
    return $DATA{$category}{ $category ne 'SAFETY' ? 'SYSTEM' : 'SEVERITY' };
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

=item B<faultCondition>

Return a hash containing the different types of condition that can
be associated with a particular fault.

  %condition = OMP::Fault->faultCondition();

=cut

sub faultCondition {
  my $class = shift;
  return %CONDITION;
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

=item B<faultStatusOpen>

Return a hash containing the statuses that can represent an open fault.

  %status = OMP::Fault->faultStatusOpen();

=cut

sub faultStatusOpen {
  my $class = shift;
  return %STATUS_OPEN;
}


=item B<faultStatusClosed>

Return a hash containing the statuses that can represent a closed fault.

  %status = OMP::Fault->faultStatusClosed();

=cut

sub faultStatusClosed {
  my $class = shift;
  return %STATUS_CLOSED;
}

sub faultStatus_Safety {
  my $class = shift;
  return %SAFETY_STATUS;
}

sub faultStatusOpen_Safety {

  my $class = shift;
  return %SAFETY_STATUS_OPEN;
}

sub faultStatusClosed_Safety {

  my $class = shift;
  return %SAFETY_STATUS_CLOSED;
}

sub faultLocation_Safety {

  my $class = shift;
  return %LOCATION;
}

=item B<faultCanAssocProjects>

Given a fault category, this badly named method will return true if faults for that
category can be associated with projects.

  $canAssoc = OMP::Fault->faultCanAssocProjects( $category );

=cut

sub faultCanAssocProjects {
  my $class = shift;
  my $category = uc(shift);

  if (exists $OPTIONS{$category}{CAN_ASSOC_PROJECTS}) {
    return $OPTIONS{$category}{CAN_ASSOC_PROJECTS};
  } else {
    return 0;
  }
}

=cut

=item B<faultCanLoseTime>

Given a fault category, this method will return true if a time lost can value can be specified
for a fault in that category.

  $canLoseTime = OMP::Fault->faultCanLoseTime( $category );

=cut

sub faultCanLoseTime {
  my $class = shift;
  my $category = uc(shift);

  if (exists $OPTIONS{$category}{CAN_LOSE_TIME}) {
    return $OPTIONS{$category}{CAN_LOSE_TIME};
  } else {
    return 0;
  }
}

=item B<faultIsTelescope>

Given a fault category, this method will return true if the category is associated with a telescope.

=cut

sub faultIsTelescope {
  my $class = shift;
  my $category = uc(shift);

  if (exists $OPTIONS{$category}{IS_TELESCOPE}) {
    return $OPTIONS{$category}{CAN_LOSE_TIME};
  } else {
    return 0;
  }
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

The fault message (which includes the submitting user id) must be
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
                     Severity => undef,
                     Location => undef,
                     FaultDate => undef,
                     Urgency => $URGENCY{Normal},
                     Condition => $CONDITION{Normal},
                     Entity => undef,
                     Category => undef,
                     Responses => [],
                     Projects => [],
                     Status => OPEN,
                     Subject => undef,
                    }, $class;


  # Go through the input args invoking relevant methods
  for my $key (sort map { lc } keys %args) {
    my $method = $key;

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

The fault ID is converted to a string and padded with a trailing zero
if warranted (since the fault id 20020105.01 will not have the right amount of padding.

=cut

sub id {
  my $self = shift;
  if (@_) { $self->{FaultID} = sprintf("%12.3f", shift); }
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

BEGIN {

  sub system {
    my $self = shift;
    $self->{Severity} = $self->{System} = shift if @_;
    return $self->{System};
  }

  *severity = \&system;
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

  return $INVERSE{$self->category}{SYSTEM}{$self->system}
    if $self->isNotSafety;

  return $self->severityText;
}

sub severityText {

  my $self = shift;
  return $INVERSE{$self->category}{'SEVERITY'}{$self->severity};
}

sub location {

  my $self = shift;

  if (@_) { $self->{'Location'} = shift; }
  return $self->{'Location'};
}

sub locationText {

  my $self = shift;
  return $INVERSE_PLACE{ $self->location };
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

=item B<conditionText>

=cut

sub conditionText {
  my $self = shift;
  return $INVERSE_CONDITION{$self->condition};
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


=item B<isChronic>

True if the fault is chronic

  $ischronic = $fault->isChronic();

=cut

sub isChronic {
  my $self = shift;
  my $concode = $self->condition;
  return ( $concode == $CONDITION{Chronic} ? 1 : 0);
}

=item B<isOpen>

Is the fault open or closed?

=cut

sub isOpen {
  my $self = shift;
  my $status = $self->status;
  return ( $status == OPEN or $status == WILL_BE_FIXED
           or $status == FOLLOW_UP
           or $status == IMMEDIATE_ACTION
           or $status == REFER_TO_SAFETY_COMMITTEE
            ? 1
            : 0
          );
}

=item B<isNew>

Is the fault new (36 hours old or less)?

=cut

sub isNew {
  my $self = shift;
  my $status = $self->status;
  my $date = $self->date;
  my $t = localtime;

  $t -= 129600; # 36 hours ago
  return ( $date >= $t ? 1 : 0 );
}

sub isNotSafety {

  my ( $self ) = @_;

  return 'safety' ne lc $self->category;
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
  if (@_) {
    my $tl = shift;
    # Dont need more than 2 decimal places
    $self->{TimeLost} = sprintf("%.2f", $tl); }
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

=item B<filedate>

Date the fault was initially filed. Returned as a C<Time::Piece> object.

  $date = $fault->filedate();

Can not be set (it is derived from the first response).

=cut

sub filedate {
  my $self = shift;

  # Look at the first response
  my $firstresp = $self->responses->[0];

  throw OMP::Error::FatalError("No fault body! Should not happen.")
    unless $firstresp;

  return $firstresp->date;
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

=item B<condition>

Condition associated with the fault. Options are "chronic" and "normal".
See C<faultConditions> for the associated integer codes that must
be supplied.

  $condition = $fault->condition();
  $fault->condition( $condition  );

=cut

sub condition {
  my $self = shift;
  if (@_) { $self->{Condition} = shift; }
  return $self->{Condition};
}

=item B<projects>

Array of projects associated with this fault.

 $fault->projects(@projects);
 $fault->projects(\@projects);
 $projref  = $fault->projects();
 @projects = $fault->projects();

The project IDs themselves are I<not> verified to ensure that
they refer to real projects. Can be empty.

=cut

sub projects {
  my $self = shift;
  if (@_) {
    my @new = ( ref($_[0]) eq 'ARRAY' ? @{$_[0]} : @_);
    @{$self->{Projects}} = @new;
  }
  if (wantarray()) {
    return @{ $self->{Projects}};
  } else {
    return $self->{Projects};
  }
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
one response (the initial fault). Returned as a list of
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

Returns the C<OMP::User> object of the  person who initially filed the
fault.

  $author = $fault->author();

This information is retrieved from the first response object.

Returns immediately if called in void context.

=cut

sub author {
  my $self = shift;
  return unless defined wantarray;
  my $firstresp = $self->responses->[0];
  throw OMP::Error::FatalError("No fault body! Should not happen.")
    unless $firstresp;

  return $firstresp->author;
}

=item B<date>

Date associated with the initial filing of the fault. If the time of
the fault has not been specified (ie C<faultdate> is undefined) the
time the fault response was filed will be used instead.

  $date = $fault->date;

Throws an C<OMP::Error::FatalError> if no response is attached.

In void context returns nothing.

=cut

sub date {
  my $self = shift;

  return unless defined wantarray;

  # Look at the fault date
  my $faultdate = $self->faultdate;
  return $faultdate if $faultdate;

  # Else return the file date
  return $self->filedate;
}

=back

=head2 General Methods

=over 4

=item B<mail_list>

Mailing list associated with the fault category. This value is
fixed by the class and can not be modified.

  $list = $fault->mail_list;

=cut

sub mail_list {
  my $self = shift;
  my $cat = $self->category;
  return $MAILLIST{$cat};
}

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
  if (defined $faultdate) {
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
  $urgency = "                     ***** Fault is URGENT ****\n"
    if $self->isUrgent;

  # Get email address
  my $email = $self->mail_list;
  $email = "UNKNOWN" unless $email;

  # Entity has a special meaning if the system is Instrument
  # or we have CSG. Ignore that for now

  # Now build up the message
  my $output =
"--------------------------------------------------------------------------------\n".
"    Report by     :  $author\n".
"                                         date: $day\n".

( $self->isNotSafety
  ? '    System'
  : '    Severity'
) .  " is     :  $system\n" .

"                                         time: $time\n".
"    Fault type is :  $type\n".

( $self->isNotSafety
  ? ''
  : sprintf "    Location is   :  %s\n" , $self->location
) .

"                                         loss: $tlost hrs\n".
"    Status        :  $status\n".
"\n".
"    Notice will be sent to: $email\n".
"\n".
"$urgency".
"~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n".
"                                Actual time of failure: $actfaultdate\n".
"\n";

  $output .= OMP::General->html_to_plain("$firstresponse")."\n\n";

  # Now loop over remaining responses and add them in
  for (@responses[1..$#responses]) {
    my $plain = OMP::General->html_to_plain( "$_" );
    $output .= "$plain\n";
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

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program (see SLA_CONDITIONS); if not, write to the
Free Software Foundation, Inc., 59 Temple Place, Suite 330,
Boston, MA  02111-1307  USA


=cut

1;
