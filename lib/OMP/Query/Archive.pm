package OMP::Query::Archive;

=head1 NAME

OMP::Query::Archive - Class representing an XML OMP query of the header archive

=head1 SYNOPSIS

    $query = OMP::Query::Archive->new(XML => $xml);
    $sql = $query->sql();

=head1 DESCRIPTION

This class can be used to process data archive header queries.
The queries are usually represented as XML.

=cut

use 5.006;
use strict;
use warnings;
use Carp;

# External modules
use OMP::DateTools;
use OMP::Config;
use OMP::Error qw/:try/;
use OMP::General;
use OMP::Range;

use Time::Piece;
use Time::Seconds;

# TABLES
our $SCUTAB = 'jcmt_tms.SCU S';
our $GSDTAB = 'jcmt_tms.SCA G';
our $SUBTAB = 'jcmt_tms.SUB H';
our $SPHTAB = 'jcmt_tms.SPH I';
our $UKIRTTAB = 'ukirt.COMMON U';
our $UFTITAB = 'ukirt.UFTI F';
our $CGS4TAB = 'ukirt.CGS4 C';
our $UISTTAB = 'ukirt.UIST I';
our $IRCAMTAB = 'ukirt.IRCAM3 I';
our $WFCAMTAB = 'ukirt.WFCAM W';
our $MICHELLETAB = 'ukirt.MICHELLE M';
our $JCMTTAB = 'jcmt.COMMON J';
our $ACSISTAB = 'jcmt.ACSIS A';
our $FILESTAB = 'jcmt.FILES F';
our $SCUBA2TAB = 'jcmt.SCUBA2 S2';
our $RXH3TAB = 'jcmt.RXH3 H3';

{
    my $cf = OMP::Config->new;

    # If a database name prefix is configured, apply it.
    my $prefix = $cf->getData('arc-database-prefix');

    if ($prefix) {
        # Need to keep list of table references here in sync with above.
        my %db = (
            jcmt => [
                \$JCMTTAB,
                \$ACSISTAB,
                \$FILESTAB,
                \$SCUBA2TAB,
                \$RXH3TAB,
            ],
            jcmt_tms => [
                \$SCUTAB,
                \$GSDTAB,
                \$SUBTAB,
                \$SPHTAB,
            ],
            ukirt => [
                \$UKIRTTAB,
                \$UFTITAB,
                \$CGS4TAB,
                \$UISTTAB,
                \$IRCAMTAB,
                \$WFCAMTAB,
                \$MICHELLETAB,
            ],
        );

        for my $key (keys %db) {
            # The Switchroo.
            for my $table (@{$db{$key}}) {
                ${$table} =~ s/^/$prefix/x;
            }
        }
    }
}

our %insttable = (
    CGS4 => [$UKIRTTAB, $CGS4TAB],
    UFTI => [$UKIRTTAB, $UFTITAB],
    UIST => [$UKIRTTAB, $UISTTAB],
    MICHELLE => [$UKIRTTAB, $MICHELLETAB],
    WFCAM => [$UKIRTTAB, $WFCAMTAB],
    IRCAM => [$UKIRTTAB, $IRCAMTAB],
    SCUBA => [$SCUTAB],
    HETERODYNE => [$GSDTAB, $SUBTAB],
    ACSIS => [$JCMTTAB, $ACSISTAB],
    'SCUBA-2' => [$JCMTTAB, $SCUBA2TAB],
    RXH3 => [$JCMTTAB, $RXH3TAB],
);

our %jointable = (
    $GSDTAB => {
        $SUBTAB => 'G.`sca#` = H.`sca#`',
    },
    $UKIRTTAB => {
        $UFTITAB => 'U.idkey = F.idkey',
        $CGS4TAB => 'U.idkey = C.idkey',
        $UISTTAB => 'U.idkey = I.idkey',
        $IRCAMTAB => 'U.idkey = I.idkey',
        $WFCAMTAB => 'U.idkey = W.idkey',
        $MICHELLETAB => 'U.idkey = M.idkey',
    },
    $JCMTTAB => {
        $ACSISTAB => 'J.obsid = A.obsid',
        $SCUBA2TAB => 'J.obsid = S2.obsid',
        $RXH3TAB => 'J.obsid = H3.obsid',
    },
);

my $ukirt_inst = qr{^(?: CGS4 | IRCAM | UFTI | MICHELLE | UIST | WFCAM )}xi;

# Lookup table
my %lut = (
    # XML tag -> database table -> column name
    instrument => {
        $SCUTAB => undef,  # implied
        $GSDTAB => 'G.frontend',
        $UKIRTTAB => 'U.INSTRUME',
        $JCMTTAB => 'J.instrume',
    },
    date => {
        $SCUTAB => 'S.ut',
        $GSDTAB => 'G.ut',
        $UKIRTTAB => 'U.UT_DATE',
        $JCMTTAB => 'J.date_obs',
    },
    dateend => {
        $SCUTAB => undef,
        $GSDTAB => undef,
        $UKIRTTAB => undef,
        $JCMTTAB => 'J.date_end',
    },
    runnr => {
        $SCUTAB => 'S.run',
        $GSDTAB => 'G.scan',
        $UKIRTTAB => 'U.OBSNUM',
        $JCMTTAB => 'J.obsnum',
    },
    obsid => {
        $SCUTAB => undef,
        $GSDTAB => undef,
        $UKIRTTAB => "U.OBSID",
        $JCMTTAB => "J.obsid",
    },
    projectid => {
        $SCUTAB => 'S.proj_id',
        $GSDTAB => 'G.projid',
        $UKIRTTAB => 'U.PROJECT',
        $JCMTTAB => 'J.project',
    },
    shifttype => {
        $SCUTAB => undef,
        $GSDTAB => undef,
        $UKIRTTAB => undef,
        $JCMTTAB => "J.oper_typ",
    },
    remote => {
        $SCUTAB => undef,
        $GSDTAB => undef,
        $UKIRTTAB => undef,
        $JCMTTAB => "J.oper_loc",
    },
);

# Inheritance
use base qw/OMP::Query/;

# Package globals

our $VERSION = '2.000';

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

This class adds one additional argument to the C<OMP::Query> constructor,
"GSDFromJCMT".  If given a true value, fetch GSD data converted to ACSIS format.

=cut

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(@_);

    my %args = @_;

    $self->gsdFromJCMT($args{'GSDFromJCMT'}) if exists $args{'GSDFromJCMT'};

    return $self;
}

=back

=head2 Accessor Methods

=over 4

=item B<gsdFromJCMT>

Whether to fetch GSD data converted to ACSIS format.

=cut

sub gsdFromJCMT {
    my $self = shift;
    if (@_) {
        $self->{'GSDFromJCMT'} = !! shift;
    }
    return 0 unless exists $self->{'GSDFromJCMT'};
    return $self->{'GSDFromJCMT'};
}

=item B<isfile>

Are we querying a database or files on disk?

    $q->isfile(1);
    $dbquery = $q->isfile;

Defaults to false.

=cut

sub isfile {
    my $self = shift;
    if (@_) {
        my $new = shift;
        $self->{IsFILE} = $new;

        # Now we need to clear the query_hash so that it is regenerated
        # with the new state
        $self->query_hash({});
    }
    return $self->{IsFILE};
}

=item B<daterange>

Date range for the given query.

    $daterange = $q->daterange;

Only used as an accessor, cannot be set. Returns an C<OMP::Range>
object.

=cut

sub daterange {
    my $self = shift;

    my $isfile = $self->isfile;
    $self->isfile(1);

    my $query_hash = $self->query_hash;

    my $daterange;

    if (ref($query_hash->{date}) eq 'ARRAY') {
        if (scalar(@{$query_hash->{date}}) == 1) {
            my $timepiece = Time::Piece->new;
            $timepiece = $query_hash->{date}->[0];
            my $maxdate;
            if (($timepiece->hour == 0)
                    && ($timepiece->minute == 0)
                    && ($timepiece->second == 0)) {
                # We're looking at an entire day, so set up an OMP::Range object with Min equal to this
                # date and Max equal to this date plus one day.
                $maxdate = $timepiece + ONE_DAY - 1;  # constant from Time::Seconds
            }
            else {
                # We're looking at a specific time, so set up an OMP::Range object with Min equal to
                # this date second and Max equal to this date.
                $maxdate = $timepiece;
            }
            $daterange = OMP::Range->new(Min => $timepiece, Max => $maxdate);
        }
    }
    elsif (UNIVERSAL::isa($query_hash->{date}, "OMP::Range")) {
        $daterange = $query_hash->{date};
        # Subtract one second from the range, because the max date is not
        # inclusive, but only if the max is actually defined.
        if (defined($daterange->max)) {
            my $max = $daterange->max;
            $max = $max - 1;
            $daterange->max($max);
        }
    }
    else {
        throw OMP::Error("Unable to get date range from query");
    }

    $self->isfile($isfile);

    return $daterange;
}

=item B<returncomment>

Are we returning a comment with this query?

    $returncomment = $q->returncomment;

Defaults to false;

=cut

sub returncomment {
    my $self = shift;
    if (defined $self->{returncomment}) {
        return $self->{returncomment};
    }
    else {
        return 0;
    }
}

=item B<telescope>

Telescope to use for this query. This governs the query since the
tables are different.

=cut

sub telescope {
    my $self = shift;

    # Get the hash form of the query
    my $href = $self->query_hash;

    # check for telescope
    my $telescope;
    if (exists $href->{telescope}) {
        $telescope = $href->{telescope}->[0];
    }
    elsif (defined $self->instrument) {
        $telescope = uc(OMP::Config->inferTelescope('instruments', $self->instrument));
    }

    for my $t (keys %$href) {
        next if defined $telescope;

        try {
            $telescope = uc(OMP::Config->inferTelescope('instruments', $t));
        }
        catch OMP::Error with {} otherwise {
            my $Error = shift;
            my $errortext = $Error->{'-text'};
            print "Error in OMP::Query::Archive::telescope: $errortext\n";
        };
    }

    unless (defined($telescope)) {
        throw OMP::Error::DBMalformedQuery("No telescope supplied!");
    }

    return $telescope;
}

=item B<instrument>

First instrument to use for this query. Returns undef if no instrument
is supplied.

=cut

sub instrument {
    my $self = shift;

    # Get the hash form of the query
    my $href = $self->raw_query_hash;

    # check for telescope
    my $instrument;
    if (exists $href->{instrument}) {
        $instrument = $href->{instrument}->[0];
    }

    return $instrument;
}

=item B<obsid>

First observation ID to use for this query. Returns undef if no
ID supplied.

=cut

sub obsid {
    my $self = shift;
    my $href = $self->raw_query_hash;
    if (exists $href->{obsid}) {
        return $href->{obsid}->[0];
    }
    return;
}

=back

=head2 General Methods

=over 4

=item B<istoday>

Returns true if the query starts on the current date,
false otherwise.

Should probably return true if the query spans the current
date. This is useful for determining whether a query should
use caching or be allowed to go to the database.

B<Note>: always returns 0 if the query has an obsid.  This is because
OMP::DB::Archive::queryArc wants to treat obsid queries as not "today".
An obsid query will likely not contain a date range, so allowing this
method to proceed and call "daterange" will cause an error.

=cut

sub istoday {
    my $self = shift;

    if (defined $self->obsid) {
        return 0;
    }

    my $date = $self->daterange->min;
    my $currentdate = gmtime;

    # Determine whether we are "today"
    # cannot rely on seconds here, all that matters is the day
    my $currstr = $currentdate->strftime("%Y-%m-%d");
    my $qstr = $date->strftime("%Y-%m-%d");
    my $istoday = ($currstr eq $qstr ? 1 : 0);

    return $istoday;
}

=item B<sql>

Returns an SQL representation of the database Archive header XML Query.

    $sql = $query->sql();

Returns undef if the query could not be formed.

=cut

sub sql {
    my $self = shift;

    throw OMP::Error::DBMalformedQuery(
        "sql method invoked with incorrect number of arguments\n")
        unless scalar(@_) == 0;

    my @sql;
    my $href = $self->query_hash;

    foreach my $t (sort keys %$href) {
        # Construct the the where clauses. Depends on which
        # additional queries are defined
        next if $t eq 'telescope';

        my $subhash = $href->{$t};

        # Skip if there are no constraints, e.g. if none of the query
        # parameters have entries for this table in %lut. (Need to check this
        # because the query_hash method will regenerate if QHash is empty.)
        next unless scalar %$subhash;

        my $subsql;
        do {
            # Locally override the query hash attribute so that we can
            # call the base class _qhash_tosql method.  (Note QHash should
            # normally be only accessed via the query_hash method.)
            local $self->{QHash} = $subhash;
            $subsql = $self->_qhash_tosql([qw/telescope/]);
        };

        # If there is no SQL returned here then we have an open query
        # so skip this telescope (should probably already have skipped due
        # to an empty $subhash above).
        next unless $subsql;

        # Form the join.
        my $tables = $insttable{$t};
        my @join;

        # Add the first table to the list.
        push @join, $tables->[0];

        # Add join expression for subsequent tables.
        for (my $i = 1; $i <= $#$tables; $i ++) {
            push @join,
                'JOIN', $tables->[$i],
                'ON', $jointable{$tables->[0]}{$tables->[$i]};
        }

        # Now need to put this SQL into the template query
        # Need to switch on telescope
        my $from = join ' ', @join;
        my $tel = $self->telescope;
        my $sql;
        if ($tel eq 'JCMT') {
            $sql = 'SELECT *, '
                . $lut{date}->{$tables->[0]} . " AS 'date_obs'";
            if (defined($lut{dateend}->{$tables->[0]})) {
                $sql .= ', '
                    . $lut{dateend}->{$tables->[0]}
                    . " AS 'date_end'";
            }
            $sql .= " FROM $from WHERE $subsql";
        }
        elsif ($tel eq 'UKIRT') {
            # UKIRT - query common table first
            $sql = "SELECT * FROM $from WHERE $subsql ORDER BY UT_DATE";
        }
        else {
            throw OMP::Error::DBMalformedQuery(
                "Unknown telescope in OMP::Query::Archive::sql: $tel\n");
        }

        push @sql, $sql;
    }

    if (wantarray) {
        return @sql;
    }
    else {
        return $sql[0];
    }
}

=item B<_root_element>

Class method that returns the name of the XML root element to be
located in the query XML. This changes depending on whether we
are doing an MSB or Project query.
Returns "ArcQuery" by default.

=cut

sub _root_element {
    return "ArcQuery";
}

=item B<_post_process_hash>

Do table specific post processing of the query hash. For projects this
mainly entails converting range hashes to C<OMP::Range> objects (via
the base class), upcasing some entries and other table specific
modifications.

    $query->_post_process_hash(\%hash);

We can not provide a generic interface to queries without providing a
lookup table to go from a XML query to a specific table row. The
following are supported:

=over 4

=item E<lt>dateE<gt>

"ut" on SCUBA and GSD, "UT_DATE" on UKIRT.

=item E<lt>instrumentE<gt>

none on SCUBA, "frontend" on GSD, "INSTRUME" on UKIRT.

=item E<lt>projectidE<gt>

"proj_id" SCUBA, "projid" GSD, none on UKIRT.

=item E<lt>runnrE<gt>

"run" on SCUBA, "scan" on GSD, "OBSNUM" on UKIRT.

=back

Due to the layout of the database tables only a single database can
be used for any given query. This means that you can not query on
UKIRT and JCMT together but also means that for JCMT queries we must
be able to distinguish between a query of the heterodyne table
(this includes UKT14) and a query on the SCUBA table.

This means that each query must include either a C<telescope> tag
or be able to determine the telescope from the C<instrument>
requirements. If no instrument is supplied there must be a telescope.
If the telescope is supplied and no instrument is supplied then
I<the GSD table is implied>.

ASIDE: The alternative is to raise an error in the implicit case
and require explicit use of an additional tag to specify the
database table.

This means that if you want to query both JCMT tables you must
do the query twice. Once with SCUBA and once without SCUBA.

ASIDE: Not sure if it is possible to infer a query on both tables
and run them separately automatically.

This method will throw an exception if a query is requested for
an instrument/telescope combination that can not work.

=cut

sub _post_process_hash {
    my $self = shift;
    my $href = shift;

    # Do the generic pre-processing
    $self->SUPER::_post_process_hash($href);

    for my $key (keys %$href) {
        next if $key =~ /^_/;

        my $entry = $href->{$key};

        if (eval {$entry->isa('OMP::Range')}) {
            my $max = $entry->max;

            # We need to redefine the max date so that this check will be
            # exclusive on the maximum, so that we don't return entries
            # from the UKIRT archive for the day we want plus the next
            # day (because dates in the UKIRT archive only have a resolution
            # of one day and not one second)
            if (defined $max and eval {$max->isa('Time::Piece')}) {
                $entry->max($max - 1);
            }
        }
    }

    # If we're looking at a file, we don't need to do these translations.
    if ($self->isfile) {
        return;
    }

    # Check we only have one instrument
    if (exists $href->{telescope}) {
        throw OMP::Error::DBMalformedQuery(
            "Can not mix multiple telescopes in a single query")
            if scalar(@{$href->{telescope}}) > 1;

        # Telescope should be upper case
        $self->_process_elements($href, sub {uc(shift)}, [qw/telescope/]);
    }

    my $newjcmt;
    # Override date dance to get GSD data from jcmt.{COMMON,ACSIS} tables.
    if ($self->gsdFromJCMT) {
        $newjcmt = 1;
    }
    elsif (exists $href->{date}) {
        # For JCMT there is a date at which we switch from bespoke tables to a COMMON+Instrument format
        # This knowledge can help to optimize queries (although it may get complicate if the heterodyne
        # data are moved to COMMON leaving behind the continuum data)
        #
        # Use semester 06B as break: 20060801
        my $refdate = 1154391000;  # no need to be spot on
        my $min = $href->{date}->min;
        $min = $min->epoch if defined $min;
        my $max = $href->{date}->max;
        $max = $max->epoch if defined $max;
        # Options are:  min greater than refdate meaning we have only new data
        #               max less than refdate so only old data
        #               must span the refdate so need both
        if ($min && $min > $refdate) {
            $newjcmt = 1;
        }
        elsif ($max && $max < $refdate) {
            $newjcmt = 0;
        }
    }

    # Loop over instruments if specified
    # This is required for a sanity check to make sure incorrect combos are
    # trapped
    my %insts;
    if (exists $href->{instrument}) {
        my %tels;
        for (@{$href->{instrument}}) {
            my $inst = uc($_);
            if ($inst eq "SCUBA") {
                $tels{JCMT} ++;
                $insts{SCUBA} ++;
            }
            elsif ($inst =~ /^SCUBA-?2/i) {
                $tels{JCMT} ++;
                $insts{'SCUBA-2'} ++;
            }
            elsif ($inst =~ /^RXH3/i) {
                $tels{JCMT} ++;
                $insts{'RXH3'} ++;
            }
            elsif ($inst =~ /^(HARP|GLT|ALAIHI|UU|AWEOWEO|KUNTUR)/i) {
                # Only new data for harp so no GSD
                $tels{JCMT} ++;
                $insts{ACSIS} ++;
            }
            elsif ($inst =~ /^ACSIS/i) {
                $tels{JCMT} ++;

                # ACSIS is a backend, not an instrument.  So if $insts{ACSIS} is set,
                # then that could result in zero rows returned from dataabse.
            }
            elsif ($inst =~ /^UKT/) {
                # must be old JCMT
                $tels{JCMT} ++;
                $insts{HETERODYNE} ++;
            }
            elsif ($inst =~ /^(RX|HETERODYNE)/i) {
                # can make a decision to trim if we have a date
                if (defined $newjcmt) {
                    unless ($newjcmt) {
                        $insts{HETERODYNE} ++;
                    }
                    else {
                        $insts{ACSIS} ++;
                    }
                }
                else {
                    $insts{HETERODYNE} ++;
                }
                $tels{JCMT} ++;
            }
            elsif ($inst =~ $ukirt_inst) {
                $tels{UKIRT} ++;
                $insts{$inst} ++;
            }
            else {
                throw OMP::Error::DBMalformedQuery("Unknown instrument: $inst");
            }
        }
    }
    else {
        # No instrument specified so we must select the tables
        my $tel = $href->{telescope}->[0];
        if (defined $tel && $tel eq 'UKIRT') {
            $insts{CGS4} ++;
            $insts{IRCAM} ++;
            $insts{UFTI} ++;
            $insts{MICHELLE} ++;
            $insts{UIST} ++;
            $insts{WFCAM} ++;
        }
        elsif (defined $tel && $tel eq 'JCMT') {
            if (defined $newjcmt) {
                if ($newjcmt) {
                    $insts{ACSIS} ++;
                    $insts{'SCUBA-2'} ++;
                    $insts{'RXH3'} ++;
                }
                else {
                    $insts{SCUBA} ++;
                    $insts{HETERODYNE} ++;
                }
            }
            else {
                $insts{ACSIS} ++;
                $insts{SCUBA} ++;
                $insts{'SCUBA-2'} ++;
                $insts{HETERODYNE} ++;
                $insts{'RXH3'} ++;
            }
        }
        else {
            throw OMP::Error::DBMalformedQuery(
                "Unable to determine instruments from telescope name "
                . (defined $tel ? "'$tel'" : "'<undef>'"));
        }
    }

    # Translate the query to be keyed by instrument.
    # Note that this ruins the hash to a certain extent.
    for my $inst (keys %insts) {
        for my $xmlkey (keys %lut) {
            if (exists $href->{$xmlkey}) {
                # Save the entry and create a new subhash
                my $entry = $href->{$xmlkey};

                # Now loop over the relevant tables
                # The real trick here is that the table queries
                # should be ORed together rather than ANDed
                # since we want to find all observations which
                # are within a date range in each table rather than
                # in *BOTH* tables. The trick is indicating to the
                # SQL builder that we mean to do this
                # Indicate it by an array/range within another hash
                # date => { U.UT_DATE => [], S.ut => [] }
                for my $table (@{$insttable{$inst}}) {
                    # Find the column name for this table
                    my $column = $lut{$xmlkey}->{$table};

                    # Skip it if the key is not defined
                    next unless defined $column;

                    # Copy the entry to the new hash
                    $href->{$inst}->{$xmlkey}->{$column} = $entry;
                }

                # Delete the key if we didnt put anything in it
                # This will break if someone does a search for
                # SCUBA or heterodyne since there will not be a
                # corresponding clause for SCUBA
                if (! scalar(keys %{$href->{$inst}->{$xmlkey}})) {
                    delete $href->{$inst}->{$xmlkey};
                }
            }
        }

        $self->_adjust_instrument($href, $inst);

        if (exists $href->{$inst}->{projectid}) {
            $self->_process_elements(
                $href->{$inst}->{projectid},
                sub {
                    lc(shift);
                }, [
                    $lut{projectid}{$GSDTAB},
                    $lut{projectid}{$SCUTAB},
            ]);
            $self->_process_elements(
                $href->{$inst}->{projectid},
                sub {
                    uc(shift)
                }, [
                    $lut{projectid}{$UKIRTTAB},
            ]);
        }
    }
    for my $xmlkey (keys %lut) {
        delete $href->{$xmlkey};
    }
    # These things should be lower/upper cased [note that we dont use href directly]

    # Remove attributes since we dont need them anymore
    delete $href->{_attr};

    return 1;
}

=item B<_adjust_instrument>

Given hash reference and instrumnet, adjusts the instrument case, and sometimes
name, based on table name.

    $q->_adjust_instrument($href, $inst);

=cut

sub _adjust_instrument {
    my ($self, $href, $inst) = @_;

    my %inst_case = (
        $GSDTAB => sub {lc(shift)},
        $JCMTTAB => sub {uc(shift)},
        $UKIRTTAB => sub {uc(shift)},
    );

    my $gsd_inst = qr/^rx(?!h3)|ukt/i;

    unless (exists $href->{$inst}->{instrument}) {
        if ($inst =~ $gsd_inst) {
            $href->{$inst}->{instrument}->{$lut{instrument}{$GSDTAB}}
                = [qw/HETERODYNE/];
        }
        elsif ($inst =~ $ukirt_inst) {
            $href->{$inst}->{instrument}->{$lut{instrument}{$UKIRTTAB}}
                = ["$inst"];
        }
    }

    for (keys %inst_case) {
        $self->_process_elements(
            $href->{$inst}->{instrument},
            $inst_case{$_}, [
                $lut{instrument}{$_},
        ])
            if exists $href->{$inst}->{instrument};
    }

    return;
}

=item B><_querify>

Make SQL to match instrument or backend values by matching upper case versions.
Rest of the calls are sent to the parent C<_querify> method; see L<OMP::Query>
for details.

    $sql = $q->_querify("instrument", "SCUBA");

=cut

sub _querify {
    my ($self, $name, $val, $cmp) = @_;

    $name =~ m/\b(?: instrum | back.?end )/ix
        or return $self->SUPER::_querify($name, $val, $cmp);

    # Default is "=";
    $cmp = lc($cmp ||= 'equal');
    # only care for "=" or "like" comparison.
    $cmp =~ m/^(?: like | equal )$/x
        or throw OMP::Error::DBMalformedQuery(
            "Do not know how to use \"$cmp\" operator with \"$name\" column and \"$val\" value.\n");

    if ($cmp eq 'equal') {
        $cmp = '=';
    }
    else {
        $val = '%' . $val . '%';
    }

    return sprintf ' UPPER( %s ) %s UPPER( %s ) ',
        $name,
        $cmp,
        "'$val'";
}

1;

__END__

=back

=head1 Query XML

The Query XML is specified as follows:

=over 4

=item B<ArcQuery>

The top-level container element is E<lt>ArcQueryE<gt>.

=item B<Equality>

Elements that contain simply C<PCDATA> are assumed to indicate
a required value.

    <instrument>SCUBA</instrument>

Would only match if C<instrument=SCUBA>.

=item B<Ranges>

Elements that contain elements C<max> and/or C<min> are used
to indicate ranges.

    <elevation><min>30</min></elevation>
    <priority><max>2</max></priority>

Why dont we just use attributes?

    <priority max="2" /> ?

Using explicit elements is probably easier to generate.

Ranges are inclusive.

=item B<Multiple matches>

Elements that contain other elements are assumed to be containing
multiple alternative matches (C<OR>ed).

    <instruments>
        <instrument>CGS4</instrument>
        <instrument>IRCAM</instrument>
    </isntruments>

C<max> and C<min> are special cases. In general the parser will
ignore the plural element (rather than trying to determine that
"instruments" is the plural of "instrument"). This leads to the
dropping of plurals such that multiple occurrence of the same element
in the query represent variants directly.

    <name>Tim</name>
    <name>Kynan</name>

would suggest that names Tim or Kynan are valid. This also means

    <instrument>SCUBA</instrument>
    <instruments>
        <instrument>CGS4</instrument>
    </instruments>

will select SCUBA or CGS4.

Neither C<min> nor C<max> can be included more than once for a
particular element. The most recent values for C<min> and C<max> will
be used. It is also illegal to use ranges inside a plural element.

=back

=head1 SEE ALSO

L<OMP::Query>, L<OMP::Query::MSB>

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
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
