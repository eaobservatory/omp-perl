package OMP::Fault;

=head1 NAME

OMP::Fault - A software bug or system fault object

=head1 SYNOPSIS

    use OMP::Fault;

    $fault = OMP::Fault->new(%details);

    $fault->respond(
        OMP::Fault::Response->new(
            author => $user,
            text => $text));

=head1 DESCRIPTION

This class deals with software bug or fault system objects.  Faults
can be responded to and summarized. Most useful when used in
conjunction with the fault database (see C<OMP::DB::Fault>).

=cut

use 5.006;
use warnings;
use strict;
use Carp;

use Time::Piece;
use Time::Seconds;

use OMP::Config;
use OMP::Display;
use OMP::Error qw/:try/;
use OMP::User;

our $VERSION = '2.000';

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
use constant SUSPENDED => 7;
use constant KNOWN_FAULT => 8;
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
use constant REMOTE_OP => 1066;
use constant SMURF => 1067;
use constant HEDWIG => 1068;
use constant JSAPROC => 1069;
use constant JSA_CADC => 1070;

# FRONT_END_HARP is 2001.
use constant {
    FTS2     => FRONT_END_HARP +  1,
    OCS_JOS  => FRONT_END_HARP +  2,
    POINTING => FRONT_END_HARP +  3,
    POL2     => FRONT_END_HARP +  4,
    ROVER    => FRONT_END_HARP +  5,
    SMU_TMU  => FRONT_END_HARP +  6,
    NAMAKANUI=> FRONT_END_HARP +  7,
    WX_STATN => FRONT_END_HARP +  8,
};

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
    EAO    => IN_TRANSIT + 5,
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
    ELECTRICAL      => INSECT + 5,
    RODENT          => INSECT + 6,
};

# Even log - system.
use constant JCMT_EVENTS => 6000;
use constant {
    # Already set elsewhere.
    #ACSIS - Back end ACSIS.
    #COMPUTER
    #FTS2
    #HARP, RXA, RXW - Front end HARP, RX[AW].
    #OCS/JOS - OCS_JOS
    #POINTING
    #POL2
    #ROVER
    #SCUBA-2 - SCUBA2
    #SMU_TMU
    #TELESCOPE
    #WMV (Water Vapor Monitor) - Water vapor rad(iometer)

    # Per Jessica D's email, keep RxH3 & Surface as one type; Software-DR includes
    # more than just ORAC-DR.
    RXH3_SURFACE => JCMT_EVENTS + 1,
    SOFTWARE_DR  => JCMT_EVENTS + 2,
};

# JCMT Event log - type.
# Already set elsewhere.
#HARDWARE
#SOFTWARE

# JCMT Event log - status.
use constant {
    COMMISSIONING => JCMT_EVENTS + 10,
    ONGOING       => JCMT_EVENTS + 11,
    COMPLETE      => JCMT_EVENTS + 12,
};

# Vehicle Incident Reporting (VIR) - System aka Vehicle.
use constant VEHICLE_I_R => 6500;
use constant {
    VEHICLE_01 => VEHICLE_I_R() +  1,
    VEHICLE_02 => VEHICLE_I_R() +  2,
    VEHICLE_03 => VEHICLE_I_R() +  3,
    VEHICLE_04 => VEHICLE_I_R() +  4,
    VEHICLE_05 => VEHICLE_I_R() +  5,
    VEHICLE_06 => VEHICLE_I_R() +  6,
    VEHICLE_07 => VEHICLE_I_R() +  7,
    VEHICLE_08 => VEHICLE_I_R() +  8,
    VEHICLE_09 => VEHICLE_I_R() +  9,
    VEHICLE_10 => VEHICLE_I_R() + 10,
    VEHICLE_11 => VEHICLE_I_R() + 11,
    VEHICLE_12 => VEHICLE_I_R() + 12,
    VEHICLE_13 => VEHICLE_I_R() + 13,
    VEHICLE_14 => VEHICLE_I_R() + 14,
};

# VIR Type.
use constant {
    ENGINE         => VEHICLE_I_R() + 30,
    TIRES          => VEHICLE_I_R() + 31,
    VEHICHLE_LIGHTS => VEHICLE_I_R() + 32,
    VEHICLE_WARNING_LIGHTS  => VEHICLE_I_R() + 33,
    # OTHER is covered by TYPEOTHER() set elsewhere.
};

my %DATA = (
    "CSG" => {
        SYSTEM => {
            "Sun/Solaris" => SUN_SOLARIS,
            "Alpha/OSF" => ALPHA_OSF,
            "PC/Windows" => PC_WINDOWS,
            "VAX/VMS" => VAX_VMS,
            "PC/Linux" => PC_LINUX,
            "Other/Unknown" => SYSTEMOTHER,
        },
        TYPE => {
            Other => TYPEOTHER,
            Human => HUMAN,
            Hardware => HARDWARE,
            Software => SOFTWARE,
            Network => NETWORK,
            Printer => PRINTER,
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
            "Front End - Namakanui" => NAMAKANUI,
            "Front End - RxA" => FRONT_END_RXA,
            "Front End - RxB" => FRONT_END_RXB,
            "Front End - RxW" => FRONT_END_RXW,
            "Front End - RxH3" => FRONT_END_RXH3,
            Surface => SURFACE,
            SCUBA => SCUBA,
            'SCUBA-2' => SCUBA2,
            IFS => IFS,
            "Water Vapor Rad." => WATER_VAPOR_RAD,
            "Weather Station" => WX_STATN,
            "Visitor Instruments" => INSTRUMENT_VISITOR,
            Instrument => INSTRUMENT_OTHER_UNKNOWN,
            Computer => COMPUTER,
            Carousel => CAROUSEL,
            "Other/Unknown" => SYSTEMOTHER,
        },
        SYSTEM_HIDDEN => {
            BACK_END_DAS() => 1,
            BACK_END_CBE() => 1,
            BACK_END_IFD() => 1,
            FRONT_END_RXB() => 1,
            FRONT_END_RXW() => 1,
            SCUBA() => 1,
        },
        TYPE => {
            Mechanical => MECHANICAL,
            Electronic => ELECTRONIC,
            Hardware => HARDWARE,
            Software => SOFTWARE,
            Cryogenic => CRYOGENIC,
            "Other/Unknown" => TYPEOTHER,
            Human => HUMAN,
            Network => NETWORK,
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
            Hardware => HARDWARE,
            "Software" => SOFTWARE,
            Network => NETWORK,
            Cryogenic => CRYOGENIC,
            "Remote Operations" => REMOTE_OP,
            "Other/Unknown" => TYPEOTHER,
            Human => HUMAN,
        },
    },
    "OMP" => {
        SYSTEM => {
            "Feedback/Web" => FEEDBACK_WEB,
            DBServer => DBSERVER,
            ObservingTool => OBSERVINGTOOL,
            QueryTool => QUERYTOOL,
            "Sequencer/Queue" => SEQUENCER_QUEUE,
            Translator => TRANSLATOR,
            "Monitor/Console" => MONITOR_CONSOLE,
            "Hedwig" => HEDWIG,
            "JSA/CADC" => JSA_CADC,
            "Other/Unknown" => SYSTEMOTHER,
        },
        TYPE => {
            GUI => GUI,
            Exception => EXCEPTION,
            Scheduling => SCHEDULING,
            Bug => BUG,
            "Feature Request" => FEATURE_REQUEST,
            Other => TYPEOTHER,
            Human => HUMAN,
        },
    },
    "DR" => {
        SYSTEM => {
            "JCMT-DR" => JCMT_DR,
            SPECX => SPECX,
            "AIPS++" => AIPSPLUSPLUS,
            SURF => SURF,
            STARLINK => STARLINK,
            "ORAC-DR/PICARD" => ORAC_DR,
            SMURF => SMURF,
            OTHER => SYSTEMOTHER,
            "JSA Processing" => JSAPROC,
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
            'JCMT' => JCMT,
            'UKIRT' => UKIRT,
            'HP' => HP,
            'Toilet' => TOILET,
            'Office' => OFFICE,
            'Library' => LIBRARY,
            'Computer Room' => COMP_ROOM,
            'Meeting Room' => MEETING_ROOM,
            'Laboratory' => LAB,
            'Workshop' => WORKSHOP,
            'Vehicle Bay' => VEHICLE_BAY,
            'Car Park' => CAR_PARK,
            'Other' => SYSTEMOTHER,
        },
        'TYPE' => {
            'Insect' => INSECT,
            'Leak' => LEAK,
            'Plumbing' => PLUMBING,
            'A/C or dehumidifier' => AC_DEHUMIDIFIER,
            'Alarm system' => ALARM_SYS,
            'Electrical' => ELECTRICAL,
            'Network' => NETWORK,
            'Computer' => COMPUTER,
            'Rodent' => RODENT,
            'Other' => TYPEOTHER,
        },
    },
    'JCMT_EVENTS' => {
        'SYSTEM' => {
            'ACSIS' => BACK_END_ACSIS,
            'Computer' => COMPUTER,
            'FTS2' => FTS2,
            'HARP' => FRONT_END_HARP,
            'OCS/JOS' => OCS_JOS,
            'Pointing' => POINTING,
            'POL2' => POL2,
            'Rover' => ROVER,
            'Namakanui' => NAMAKANUI,
            'RxA' => FRONT_END_RXA,
            'RxW' => FRONT_END_RXW,
            'RxH3/Surface' => RXH3_SURFACE,
            'SCUBA-2' => SCUBA2,
            'SMU/TMU' => SMU_TMU,
            'Software-DR' => SOFTWARE_DR,
            'Telescope' => TELESCOPE,
            'Water Vapor Monitor' => WATER_VAPOR_RAD,
            'Weather Station' => WX_STATN,
            'Other' => SYSTEMOTHER,
        },
        'TYPE' => {
            'Hardware' => HARDWARE,
            'Software' => SOFTWARE,
        },
    },
    'VEHICLE_INCIDENT' => {
        # 'VEHICLE' is same as 'SYSTEM'.
        'VEHICLE' => {
            '1' => VEHICLE_01(),
            '2' => VEHICLE_02(),
            '3' => VEHICLE_03(),
            '4' => VEHICLE_04(),
            '5' => VEHICLE_05(),
            '6' => VEHICLE_06(),
            '7' => VEHICLE_07(),
            '9' => VEHICLE_09(),
            '10' => VEHICLE_10(),
            '11' => VEHICLE_11(),
            '13' => VEHICLE_13(),
            '14' => VEHICLE_14(),
        },
        'TYPE' => {
            'Engine' => ENGINE(),
            'Tires' => TIRES(),
            'Lights' => VEHICHLE_LIGHTS(),
            'Warning lights' => VEHICLE_WARNING_LIGHTS(),
            'Other' => TYPEOTHER(),
        },
    },
);

my %LOCATION = (
    'UKIRT' => UKIRT,
    'JCMT' => JCMT,
    'HP' => HP,
    'JAC' => JAC,
    'EAO' => EAO,
    'In transit' => IN_TRANSIT
);

my %LOCATION_HIDDEN = (
    JAC() => 1,
);

# Miscellaneous options for each category
my %OPTIONS = (
    CSG => {
    },
    JCMT => {
        CAN_LOSE_TIME => 1,
        CAN_ASSOC_PROJECTS => 1,
        IS_TELESCOPE => 1,
    },
    UKIRT => {
        CAN_LOSE_TIME => 1,
        CAN_ASSOC_PROJECTS => 1,
        IS_TELESCOPE => 1,
    },
    OMP => {
    },
    DR => {
    },
    SAFETY => {
        CATEGORY_NAME => 'Safety',
        CATEGORY_NAME_SUFFIX => 'Reporting',
        HAS_LOCATION => 1,
        SYSTEM_LABEL => 'Severity',
        INITIAL_STATUS => FOLLOW_UP,
    },
    FACILITY => {
        CATEGORY_NAME => 'Facility',
    },
    JCMT_EVENTS => {
        CATEGORY_NAME => 'JCMT Events',
        CATEGORY_NAME_SUFFIX => undef,
        ENTRY_NAME => 'Event',
        HAS_TIME_OCCURRED => 1,
        INITIAL_STATUS => ONGOING,
    },
    VEHICLE_INCIDENT => {
        CATEGORY_NAME => 'Vehicle Incident',
        CATEGORY_NAME_SUFFIX => 'Reporting',
        SYSTEM_LABEL => 'Vehicle',
    },
);

# Urgency
my %URGENCY = (
    Urgent => 0,
    Normal => 1,
    Info => 2,
);

my %CONDITION = (
    Chronic => 0,
    Normal => 1,
);

my %STATUS_OPEN = (
    Open => OPEN,
    'Open - Will be fixed' => WILL_BE_FIXED,
    'Suspended' => SUSPENDED,
);

my %STATUS_CLOSED = (
    Closed => CLOSED,
    "Works for me" => WORKS_FOR_ME,
    "Not a fault" => NOT_A_FAULT,
    "Won't be fixed" => WON_T_BE_FIXED,
    Duplicate => DUPLICATE,
);

my %SAFETY_STATUS_OPEN = (
    'Immediate action required' => IMMEDIATE_ACTION,
    'Follow up required' => FOLLOW_UP,
    'Refer to safety committee' => REFER_TO_SAFETY_COMMITTEE,
);

my %SAFETY_STATUS_CLOSED = (
    'No further action' => NO_ACTION,
    'Closed' => $STATUS_CLOSED{'Closed'}
);

my %STATUS = (%STATUS_OPEN, %STATUS_CLOSED);

my %SAFETY_STATUS = (%SAFETY_STATUS_OPEN, %SAFETY_STATUS_CLOSED);

my %JCMT_EVENTS_STATUS_OPEN = (
    'Commissioning' => COMMISSIONING,
    'Ongoing' => ONGOING,
);

my %JCMT_EVENTS_STATUS_CLOSED = (
    'Complete' => COMPLETE,
);

my %JCMT_EVENTS_STATUS = (
    %JCMT_EVENTS_STATUS_OPEN,
    %JCMT_EVENTS_STATUS_CLOSED);

my %VEHICLE_INCIDENT_STATUS_OPEN = (
    'Open' => OPEN(),
    'Open - Will be fixed' => WILL_BE_FIXED(),
    'Known fault' => KNOWN_FAULT(),
);

my %VEHICLE_INCIDENT_STATUS_CLOSED = (
    'Duplicate' => DUPLICATE(),
    'Closed' => CLOSED(),
    "Won't be fixed" => WON_T_BE_FIXED(),
);

my %VEHICLE_INCIDENT_STATUS = (
    %VEHICLE_INCIDENT_STATUS_OPEN,
    %VEHICLE_INCIDENT_STATUS_CLOSED);

# Now invert %DATA, %URGENCY, and %CONDITION
my %INVERSE_URGENCY;
for (keys %URGENCY) {
    $INVERSE_URGENCY{$URGENCY{$_}} = $_;
}

my %INVERSE_CONDITION;
for (keys %CONDITION) {
    $INVERSE_CONDITION{$CONDITION{$_}} = $_;
}

my %INVERSE_STATUS;
for (keys %STATUS) {
    $INVERSE_STATUS{$STATUS{$_}} = $_;
}

for (keys %SAFETY_STATUS) {
    $INVERSE_STATUS{$SAFETY_STATUS{$_}} = $_;
}

for (keys %JCMT_EVENTS_STATUS) {
    $INVERSE_STATUS{$JCMT_EVENTS_STATUS{$_}} = $_;
}

for (keys %VEHICLE_INCIDENT_STATUS) {
    $INVERSE_STATUS{$VEHICLE_INCIDENT_STATUS{$_}} = $_;
}

my %INVERSE_PLACE;
$INVERSE_PLACE{$LOCATION{$_}} = $_
    for keys %LOCATION;

# Loop over categories
my %INVERSE;
for my $cat (keys %DATA) {
    # Crate new hash for categories
    $INVERSE{$cat} = {};

    # Loop over systems and types
    for my $sys (keys %{$DATA{$cat}}) {
        # Create new hash for systems and types
        $INVERSE{$cat}{$sys} = {};
        for my $strings (keys %{$DATA{$cat}{$sys}}) {
            $INVERSE{$cat}{$sys}{$DATA{$cat}{$sys}{$strings}} = $strings;
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

    %systems = OMP::Fault->faultSystems("JCMT");

Returns empty list if the fault category is not recognized.

=cut

sub faultSystems {
    my $class = shift;
    my $category = uc(shift);
    my %opt = @_;

    return unless exists $DATA{$category};

    my %cat_section = (
        SAFETY => 'SEVERITY',
        VEHICLE_INCIDENT => 'VEHICLE',
    );

    my $section = $cat_section{$category} // 'SYSTEM';

    my $systems = $DATA{$category}{$section};

    return $systems if $opt{'include_hidden'};

    my $hidden = $DATA{$category}{$section . '_HIDDEN'};

    return $systems unless defined $hidden;

    my %non_hidden = ();

    while (my ($name, $code) = each %$systems) {
        $non_hidden{$name} = $code unless $hidden->{$code};
    }

    return \%non_hidden;
}

=item B<faultTypes>

For a specific fault category (eg JCMT or UKIRT) return a hash
containing the allowed fault types (as keys) and the constants
required to identify those types in the database.

    %types = OMP::Fault->faultTypes("JCMT");

Returns empty list if the fault category is not recognized.

=cut

sub faultTypes {
    my $class = shift;
    my $category = uc(shift);

    if (exists $DATA{$category}) {
        return $DATA{$category}{TYPE};
    }
    else {
        return ();
    }
}

=item B<shiftTypes>
For a specific fault category (eg JCMT or UKIRT) return a list of the allowed shift types.

    %shifttypes = OMP::Fault->shiftTypes("JCMT");

Returns empty list if the fault category is not recognized or has no allowed shifts.
=cut

my %JCMTSHIFTTYPES = (
    NIGHT => "NIGHT",
    EO => "EO",
    DAY => "DAY",
    OTHER => "OTHER",
);

my %UKIRTSHIFTTYPES = (
    NIGHT => "NIGHT",
);

sub shiftTypes {
    my $class = shift;
    my $category = uc(shift);

    if ($category eq 'JCMT') {
        return %JCMTSHIFTTYPES;
    }
    elsif ($category eq 'UKIRT') {
        return %UKIRTSHIFTTYPES;
    }
    else {
        return ();
    }
}

=item B<remoteTypes>
For a specific fault category (eg JCMT or UKIRT) return a list of the allowed remote types.

    %remotetypes = OMP::Fault->remoteTypes("JCMT");

Returns empty list if the fault category is not recognized or has no allowed remote types.
=cut

my %JCMTREMOTETYPES = (
    LOCAL => "LOCAL",
    REMOTE => "REMOTE",
    UNKNOWN => "UNKNOWN",
);

sub remoteTypes {
    my $class = shift;
    my $category = uc(shift);

    if ($category eq 'JCMT') {
        return %JCMTREMOTETYPES;
    }
    else {
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

=back

=head2 Class or Instance Methods

The following methods can be used either as class methods
(supplying a category name) or as instance methods (using
the category of the fault object).

=over 4

=item B<faultStatus>

Return a hash containing the different statuses that can be associated
with a fault.

    %status = OMP::Fault->faultStatus();

B<Note:> if called as a class method without specifying a category,
returns a combined set of statuses from all categories.

=cut

sub faultStatus {
    my $self = shift;
    my $category = (ref $self) ? $self->category : (@_ ? uc shift : undef);

    if (defined $category) {
        return %SAFETY_STATUS
            if $category eq 'SAFETY';
        return %JCMT_EVENTS_STATUS
            if $category eq 'JCMT_EVENTS';
        return %VEHICLE_INCIDENT_STATUS
            if $category eq 'VEHICLE_INCIDENT';

        return %STATUS;
    }

    my %combined = (
        %STATUS, %SAFETY_STATUS,
        %JCMT_EVENTS_STATUS, %VEHICLE_INCIDENT_STATUS);

    return %combined;
}

=item B<faultStatusOpen>

Return a hash containing the statuses that can represent an open fault.

    %status = OMP::Fault->faultStatusOpen();

B<Note:> if called as a class method without specifying a category,
returns a combined set of statuses from all categories.

=cut

sub faultStatusOpen {
    my $self = shift;
    my $category = (ref $self) ? $self->category : (@_ ? uc shift : undef);

    if (defined $category) {
        return %SAFETY_STATUS_OPEN
            if $category eq 'SAFETY';
        return %JCMT_EVENTS_STATUS_OPEN
            if $category eq 'JCMT_EVENTS';
        return %VEHICLE_INCIDENT_STATUS_OPEN
            if $category eq 'VEHICLE_INCIDENT';

        return %STATUS_OPEN;
    }

    my %combined = (
        %STATUS_OPEN, %SAFETY_STATUS_OPEN,
        %JCMT_EVENTS_STATUS_OPEN, %VEHICLE_INCIDENT_STATUS_OPEN);

    return %combined;
}

=item B<faultStatusClosed>

Return a hash containing the statuses that can represent a closed fault.

    %status = OMP::Fault->faultStatusClosed();

B<Note:> if called as a class method without specifying a category,
returns a combined set of statuses from all categories.

=cut

sub faultStatusClosed {
    my $self = shift;
    my $category = (ref $self) ? $self->category : (@_ ? uc shift : undef);

    if (defined $category) {
        return %SAFETY_STATUS_CLOSED
            if $category eq 'SAFETY';
        return %JCMT_EVENTS_STATUS_CLOSED
            if $category eq 'JCMT_EVENTS';
        return %VEHICLE_INCIDENT_STATUS_CLOSED
            if $category eq 'VEHICLE_INCIDENT';

        return %STATUS_CLOSED;
    }

    my %combined = (
        %STATUS_CLOSED, %SAFETY_STATUS_CLOSED,
        %JCMT_EVENTS_STATUS_CLOSED, %VEHICLE_INCIDENT_STATUS_CLOSED);

    return %combined;
}

=item B<faultLocation>

Return a hash containing locations which can be specified in faults.

    %location = OMP::Fault->faultLocation($category, %options);

Options:

=over 4

=item include_hidden

Include hidden locations.

=back

B<Note:> if passing options but not specifying a category, the
first (positional) argument should be C<undef>.  The category
selection is not currently used (as there is only one set of
locations) but is retained in the interface to match other methods
and in case different sets of locations are defined in the future.

=cut

sub faultLocation {
    my $self = shift;
    my $category = (ref $self) ? $self->category : shift;
    $category = uc $category if defined $category;
    my %opt = @_;

    return %LOCATION if $opt{'include_hidden'};

    my %non_hidden;

    while (my ($name, $code) = each %LOCATION) {
        $non_hidden{$name} = $code unless $LOCATION_HIDDEN{$code};
    }

    return %non_hidden;
}

=item B<faultCanAssocProjects>

Given a fault category, this badly named method will return true if faults for that
category can be associated with projects.

    $canAssoc = OMP::Fault->faultCanAssocProjects($category);

=cut

sub faultCanAssocProjects {
    my $self = shift;
    my $category = (ref $self) ? $self->category : uc shift;

    if (exists $OPTIONS{$category}{'CAN_ASSOC_PROJECTS'}) {
        return $OPTIONS{$category}{'CAN_ASSOC_PROJECTS'};
    }

    return 0;
}

=item B<faultCanLoseTime>

Given a fault category, this method will return true if a time lost can value can be specified
for a fault in that category.

    $canLoseTime = OMP::Fault->faultCanLoseTime($category);

=cut

sub faultCanLoseTime {
    my $self = shift;
    my $category = (ref $self) ? $self->category : uc shift;

    if (exists $OPTIONS{$category}{'CAN_LOSE_TIME'}) {
        return $OPTIONS{$category}{'CAN_LOSE_TIME'};
    }

    return 0;
}

=item B<faultHasLocation>

Given a fault category, return whether the faults of this category
are associated with a location.

=cut

sub faultHasLocation  {
    my $self = shift;
    my $category = (ref $self) ? $self->category : uc shift;

    if (exists $OPTIONS{$category}{'HAS_LOCATION'}) {
        return $OPTIONS{$category}{'HAS_LOCATION'};
    }

    return 0;
}

=item B<faultHasTimeOccurred>

Given a fault category, return whether the faults of this category
can be associated with a time.

=cut

sub faultHasTimeOccurred {
    my $self = shift;
    my $category = (ref $self) ? $self->category : uc shift;

    # If we have a specific setting, return it.
    if (exists $OPTIONS{$category}{'HAS_TIME_OCCURRED'}) {
        return $OPTIONS{$category}{'HAS_TIME_OCCURRED'};
    }

    # Otherwise assume a time can be specified if time can be lost.
    return OMP::Fault->faultCanLoseTime($category);
}

=item B<faultInitialStatus>

Given a fault category, return a suggested initial status
value.  (Note thus is not currently applied as the default
when constructing an OMP::Fault object, but the value returned
could be used when showing a fault filing form.)

=cut

sub faultInitialStatus  {
    my $self = shift;
    my $category = (ref $self) ? $self->category : uc shift;

    if (exists $OPTIONS{$category}{'INITIAL_STATUS'}) {
        return $OPTIONS{$category}{'INITIAL_STATUS'};
    }

    return OPEN;
}

=item B<faultIsTelescope>

Given a fault category, this method will return true if the category is associated with a telescope.

=cut

sub faultIsTelescope {
    my $self = shift;
    my $category = (ref $self) ? $self->category : uc shift;

    if (exists $OPTIONS{$category}{'IS_TELESCOPE'}) {
        return $OPTIONS{$category}{'IS_TELESCOPE'};
    }

    return 0;
}

=item B<getCategoryName>

Get the name (capitalized for display) of the category.

=cut

sub getCategoryName {
    my $self = shift;
    my $category = (ref $self) ? $self->category : uc shift;
    return $self->_getCategoryName($category, 0);
}

=item B<getCategoryFullName>

Get the full name of the category followed by the suffix, if any,
e.g. "Faults" or "Reporting".

=cut

sub getCategoryFullName {
    my $self = shift;
    my $category = (ref $self) ? $self->category : uc shift;
    return $self->_getCategoryName($category, 1);
}

sub _getCategoryName {
    my $self = shift;
    my $category = shift;
    my $full = shift;

    my $name = (exists $OPTIONS{$category}{'CATEGORY_NAME'})
        ? $OPTIONS{$category}{'CATEGORY_NAME'}
        : $category;

    return $name unless $full;

    my $suffix = (exists $OPTIONS{$category}{'CATEGORY_NAME_SUFFIX'})
        ? $OPTIONS{$category}{'CATEGORY_NAME_SUFFIX'}
        : 'Faults';

    return $name unless defined $suffix;

    return $name . ' ' . $suffix;
}

=item B<getCategoryEntryName>

Get the name of entries in this category, e.g. "Fault"
or "Event".

=cut

sub getCategoryEntryName {
    my $self = shift;
    my $category = (ref $self) ? $self->category : uc shift;

    if (exists $OPTIONS{$category}{'ENTRY_NAME'}) {
        return $OPTIONS{$category}{'ENTRY_NAME'};
    }

    return 'Fault';
}

=item B<getCategoryEntryNameQualified>

Get the name of entries in this category, in lower case, prefixed
with the name of the category e.g. "JCMT fault" or "JCMT event".

=cut

sub getCategoryEntryNameQualified {
    my $self = shift;

    my $catName = $self->getCategoryName(@_);
    my $entryName = lc $self->getCategoryEntryName(@_);

    # If the category name already ends with the entry name,
    # remove it to avoid duplication.
    $catName =~ s/ ${entryName}s?$//i;

    return $catName . ' ' . $entryName;
}

=item B<getCategorySystemLabel>

Get the label for the "system" parameter.

=cut

sub getCategorySystemLabel {
    my $self = shift;
    my $category = (ref $self) ? $self->category : uc shift;

    if (exists $OPTIONS{$category}{'SYSTEM_LABEL'}) {
        return $OPTIONS{$category}{'SYSTEM_LABEL'};
    }

    return 'System';
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
    shifttype - what type of shift was this [string]
    remote    - remote or not [integer]
    fault     - a fault "response" object

The fault message (which includes the submitting user id) must be
supplied as a C<OMP::Fault::Response> object.

The values for type, urgency, system and status can be obtained by
using the C<faultTypes>, C<faultUrgency>, C<faultSystems> and
C<faultStatus> methods. These values should be supplied as a hash:

    my $fault = OMP::Fault->new(%details);

Optional keys are: "timelost" (assumes 0hrs), "faultdate" (assumes
unknown), "urgency" (assumes not urgent - "normal"), "entity" (assumes
not relevant), "system" (assumes "other/unknown") and "type" (assumes
"other"), "shifttype" (assumes "") and "remote" (assumes NULL).  This
means that the required information is "category" and the fault
message itself (in the form of a response object).

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
        Location => undef,
        FaultDate => undef,
        Urgency => $URGENCY{Normal},
        Condition => $CONDITION{Normal},
        Entity => undef,
        Category => undef,
        Responses => [],
        Projects => [],
        Status => OPEN,
        ShiftType => undef,
        Remote => undef,
        Subject => undef,
        Relevance => undef,
    }, $class;

    # Go through the input args invoking relevant methods
    for my $key (sort map {lc} keys %args) {
        my $method = $key;

        if ($fault->can($method)) {
            $fault->$method($args{$key});
        }
    }

    # Cause some trouble if there is no category
    croak "Must supply a fault category (eg UKIRT or JCMT)"
        unless defined $fault->category;

    # Really need to check that someone has supplied
    # a fault body
    croak "Must supply an initial fault body"
        unless scalar(@{$fault->responses});

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
    $fault->id($id);

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
    if (@_) {$self->{FaultID} = sprintf("%12.3f", shift);}
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
    $fault->type($type);

=cut

sub type {
    my $self = shift;
    if (@_) {$self->{Type} = shift;}
    return $self->{Type};
}

=item B<shifttype>

ShiftType (supplied as a string).

    $shifttype = $fault->shifttype();
    $fault->shifttype($shifttype);

=cut

sub shifttype {
    my $self = shift;
    if (@_) {
        my $shifttype = shift;
        if (! defined $shifttype || $shifttype eq '') {
            $shifttype = undef;
        }
        $self->{ShiftType} = $shifttype;
    }
    return $self->{ShiftType};
}


=item B<remote>

Remote (supplied as an integer).

    $remote = $fault->remote();
    $fault->remote($remote);

=cut

sub remote {
    my $self = shift;
    if (@_) {
        my $remote = shift;
        if (! defined $remote || $remote eq '') {
            $remote = undef;
        }
        $self->{Remote} = $remote;
    }
    return $self->{Remote};
}

=item B<system>

Fault system (supplied as an integer - see C<faultSystems>).

    $sys = $fault->system();
    $fault->system($sys);

=cut

sub system {
    my $self = shift;

    if (@_) {
        $self->{System} = shift @_;
    }

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

    my $category = $self->category;

    return $INVERSE{$category}{'SEVERITY'}{$self->system}
        if 'SAFETY' eq $category;

    return $INVERSE{$category}{'VEHICLE'}{$self->system}
        if 'VEHICLE_INCIDENT' eq $category;

    return $INVERSE{$category}{'SYSTEM'}{$self->system};
}

sub location {
    my $self = shift;

    if (@_) {$self->{'Location'} = shift;}

    return $self->{'Location'};
}

sub locationText {
    my $self = shift;
    return $INVERSE_PLACE{$self->location};
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
    return ($urgcode == $URGENCY{Urgent} ? 1 : 0);
}


=item B<isChronic>

True if the fault is chronic

    $ischronic = $fault->isChronic();

=cut

sub isChronic {
    my $self = shift;
    my $concode = $self->condition;
    return ($concode == $CONDITION{Chronic} ? 1 : 0);
}

=item B<isOpen>

Is the fault open or closed?

=cut

sub isOpen {
    my $self = shift;
    my $status = $self->status;

    return scalar grep {
        $status == $_
    } (
        OPEN(),
        WILL_BE_FIXED(),
        FOLLOW_UP(),
        IMMEDIATE_ACTION(),
        REFER_TO_SAFETY_COMMITTEE(),
        COMMISSIONING(),
        ONGOING(),
        KNOWN_FAULT(),
        SUSPENDED(),
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

    $t -= 129600;  # 36 hours ago
    return ($date >= $t ? 1 : 0);
}

sub isSCUBA2Fault {
    my ($self) = @_;

    my $sys = $self->system();

    return $sys && $sys == $DATA{'JCMT'}->{'SYSTEM'}{'SCUBA-2'};
}

=item B<subject>

Short description of the fault that can be easily displayed
in summary tables and in email responses.

    $subj = $fault->subject();
    $fault->subject($subj);

=cut

sub subject {
    my $self = shift;
    if (@_) {$self->{Subject} = shift;}
    return $self->{Subject};
}

=item B<status>

Fault status (supplied as an integer - see C<faultStatus>).
Indicates whether the fault is "open" or "closed".

    $status = $fault->status();
    $fault->status($status);

=cut

sub status {
    my $self = shift;
    if (@_) {$self->{Status} = shift;}
    return $self->{Status};
}

=item B<timelost>

Time lost to the fault in hours.

    $tl = $fault->timelost();
    $fault->timelost($tl);

=cut

sub timelost {
    my $self = shift;
    if (@_) {
        my $tl = shift;
        # Dont need more than 2 decimal places
        $self->{TimeLost} = sprintf("%.2f", $tl);
    }
    return $self->{TimeLost};
}

=item B<faultdate>

Date the fault occurred. This may be different from the date
it was filed. Not required (default is that the date it was
filed is good enough). Must be a C<Time::Piece> object
(or undef).

    $date = $fault->faultdate();
    $fault->faultdate($date);

=cut

sub faultdate {
    my $self = shift;
    if (@_) {
        my $date = shift;
        croak "Date must be supplied as Time::Piece object"
            if (defined $date && !UNIVERSAL::isa($date, "Time::Piece"));
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
    $fault->urgency($urgency);

Still need to decide whether to use integers or strings.

=cut

sub urgency {
    my $self = shift;
    if (@_) {$self->{Urgency} = shift;}
    return $self->{Urgency};
}

=item B<condition>

Condition associated with the fault. Options are "chronic" and "normal".
See C<faultConditions> for the associated integer codes that must
be supplied.

    $condition = $fault->condition();
    $fault->condition($condition);

=cut

sub condition {
    my $self = shift;
    if (@_) {$self->{Condition} = shift;}
    return $self->{Condition};
}

=item B<projects>

Array of projects associated with this fault.

    $fault->projects(@projects);
    $fault->projects(\@projects);
    $projref = $fault->projects();
    @projects = $fault->projects();

The project IDs themselves are I<not> verified to ensure that
they refer to real projects. Can be empty.

=cut

sub projects {
    my $self = shift;
    if (@_) {
        my @new = (ref($_[0]) eq 'ARRAY' ? @{$_[0]} : @_);
        @{$self->{Projects}} = @new;
    }
    if (wantarray()) {
        return @{$self->{Projects}};
    }
    else {
        return $self->{Projects};
    }
}

=item B<entity>

Context sensitive information that should be associated with the
fault. In general this is an instrument name or a computer
name. Can be left empty.

    $thing = $fault->entity();
    $fault->entity($thing);

=cut

sub entity {
    my $self = shift;
    if (@_) {$self->{Entity} = shift;}
    return $self->{Entity};
}

=item B<category>

The main fault category that defines the entire system. This
defines what the type and system translations are. Examples
are "UKIRT", "JCMT" or "OMP".

    $category = $fault->category();
    $fault->category($cat);

Must be provided.

=cut

sub category {
    my $self = shift;
    if (@_) {$self->{Category} = uc(shift);}
    return $self->{Category};
}

=item B<responses>

The responses associated with the fault. There will always be at least
one response (the initial fault). Returned as a list of
C<OMP::Fault::Response> objects. The order corresponds to the sequence
in which the fault responses were filed.

If arguments are supplied it is assumed that they should
be pushed on to the response array.

    $fault->responses(@responses);

If the first argument is a reference to an array it is assumed
that all the existing responses are to be replaced.

    $fault->responses(\@responses);

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
        if (ref($_[0]) eq "ARRAY") {
            # We are replacing current entries
            $replace = 1;
            @input = @{$_[0]};
        }
        elsif (! defined $_[0]) {
            # Replace with empty
            $replace = 1;
        }
        else {
            @input = @_;
        }

        # Check they are the right class
        for (@input) {
            croak "Responses must be in class OMP::Fault::Response"
                unless UNIVERSAL::isa($_, "OMP::Fault::Response");
        }

        # Now store or overwrite
        if ($replace) {
            $self->{Responses} = \@input;
        }
        else {
            push(@{$self->{Responses}}, @input);
        }

        # Now modify the isfault flags
        my $i = 0;
        for (@{$self->{Responses}}) {
            my $isfault = ($i == 0 ? 1 : 0);
            $_->isfault($isfault);
            $i ++;
        }
    }

    # See if we are in void context
    my $want = wantarray;
    return unless defined $want;

    # Else return list or reference
    if (wantarray) {
        return @{$self->{Responses}};
    }
    else {
        my @copy = @{$self->{Responses}};
        return \@copy;
    }
}

=item B<getResponse>

Return the response object with the given response ID.

    $resp = $fault->getResponse($respid);

where C<$respid> is the ID of the response to be returned.

=cut

sub getResponse {
    my $self = shift;
    my $respid = shift;

    for (@{$self->responses}) {
        return $_ if $_->id eq $respid;
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

=item B<relevance>

Relevance score, if this fault was retrieved from the database
using a "full text" search.

    $score = $fault->relevance();

=cut

sub relevance {
    my $self = shift;
    $self->{Relevance} = shift if @_;
    return $self->{Relevance};
}

=back

=head2 General Methods

=over 4

=item B<mail_list>

Mailing lists associated with the fault category, as an array
reference.

    \@lists = $fault->mail_list;

Note: this is taken from the C<email-address> section of the
OMP configuration file.

=cut

sub mail_list {
    my $self = shift;
    my $cat = $self->category;
    my $config = OMP::Config->new();
    return [
        grep {$_}
        map {s/^ +//; s/ +$//; $_}
        $config->getData('email-address.' . lc $cat)];
}

=item B<mail_list_users>

Get a list of C<OMP::User> objects representing the addresses
given by C<mail_list>.

    @fault_users = $fault->mail_list_users;

=cut

sub mail_list_users {
    my $self = shift;

    my $name = $self->getCategoryFullName;

    return map {
        OMP::User->new(
            'name' => $name,
            'email' => $_,
        )
    } @{$self->mail_list};
}

=item B<respond>

Add a fault response.

    $fault->respond($response);

A convenience wrapper around the C<responses> method.
(effectively a synonym).

=cut

sub respond {
    my $self = shift;
    my $response = shift;
    $self->responses($response);
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
    my $firstresponsepreformatted = $responses[0]->preformatted;
    my $tlost = $self->timelost;
    my $urgcode = $self->urgency;
    my $category = $self->category;
    my $faultdate = $self->faultdate;
    my $entity = $self->entity;

    # Get the time and date as separate things
    my $time = $date->strftime("%H:%M");
    my $day = $date->strftime("%Y-%m-%d");

    # Actual time of fault as string
    my $actfaultdate;
    if (defined $faultdate) {
        $actfaultdate = $faultdate->strftime("%H:%M") . "UT";
    }
    else {
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
    my $email = join ', ', @{$self->mail_list};
    $email = "UNKNOWN" unless $email;

    # Entity has a special meaning if the system is Instrument
    # or we have CSG. Ignore that for now

    # Now build up the message
    my $output =
        "--------------------------------------------------------------------------------\n"
        . "    Report by     :  $author\n"
        . "                                         date: $day\n"
        . '    ' . $self->getCategorySystemLabel()
        . " is     :  $system\n"
        . "                                         time: $time\n"
        . "    Fault type is :  $type\n"
        .
        ($self->faultHasLocation()
            ? sprintf "    Location is   :  %s\n", $self->location
            : '')
        . "                                         loss: $tlost hrs\n"
        . "    Status        :  $status\n" . "\n"
        . "    Notice will be sent to: $email\n" . "\n"
        . "$urgency"
        . "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n"
        . "                                Actual time of failure: $actfaultdate\n"
        . "\n";

    $output .= OMP::Display->format_text($firstresponse, $firstresponsepreformatted) . "\n\n";

    # Now loop over remaining responses and add them in
    for (@responses[1 .. $#responses]) {
        $output .= "$_\n";
    }

    return $output;
}

1;

__END__

=back

=head1 SEE ALSO

C<OMP::Fault::Response>, C<OMP::DB::Fault>.

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002 Particle Physics and Astronomy Research Council.
Copyright (C) 2015-2017 East Asian Observatory.
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
along with this program; if not, write to the
Free Software Foundation, Inc., 59 Temple Place, Suite 330,
Boston, MA  02111-1307  USA

=cut
