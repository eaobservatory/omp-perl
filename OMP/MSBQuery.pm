package OMP::MSBQuery;

=head1 NAME

OMP::MSBQuery - Class representing an OMP query of the MSB database

=head1 SYNOPSIS

  $query = new OMP::MSBQuery( XML => $xml );
  $sql = $query->sql( $table );


=head1 DESCRIPTION

This class can be used to process OMP MSB queries.
The queries are usually represented as XML.

=cut

use 5.006;
use strict;
use warnings;
use Carp;

# External modules
use OMP::Error;
use OMP::General;
use OMP::Range;
use Time::Piece ':override'; # for gmtime

# Inheritance
use base qw/ OMP::DBQuery /;

# Package globals

our $VERSION = (qw$Revision$ )[1];

=head1 METHODS

=head2 Accessor Methods

Instance accessor methods. Methods beginning with an underscore
are deemed to be private and do not form part of the publi interface.

=over 4

=item B<refDate>

Return the date object associated with the query. If no date has been
specified explicitly in the query the current date is returned.
[although technically the "current" date is actually the date when the
query was parsed rather than the date the exact time this method was
called]

  $date = $query->refDate;

The time can not be specified as an input argument.

This allows the target availability to be calculated.

=cut

sub refDate {
  my $self = shift;

  # Get the hash form of the query
  my $href = $self->query_hash;

  # Check for "date" key
  my $date;
  if ( exists $href->{date} ) {
    $date = $href->{date}->[0];
  } else {
    # Need to get a gmtime object that stringifies as a Sybase date
    $date = gmtime;

    # Rebless
    bless $date, "Time::Piece::Sybase";
  }
  return $date;
}

=item B<airmass>

Return the requested airmass range as an C<OMP::Range> object.

  $range = $query->airmass;

Returns C<undef> if the range has not been specified.

=cut

sub airmass {
  my $self = shift;

  # Get the hash form of the query
  my $href = $self->query_hash;

  # Check for "airmass" key
  my $airmass;
  $airmass = $href->{airmass} if exists $href->{airmass};
  return $airmass;
}

=item B<constraints>

Returns a hash containing the general project constraints that 
can be applied to this query.

Supported constraints are:

  observability  - is the source up
  remaining      - is the MSB still to be observed
  allocation     - has the full project allocation been used

Each of these will have a true (constraint is active) or false
(constraint is disabled) value.

If the query includes an instruction to disable all constraints
this will be respected by setting all values to false.

Default is all values set to true.

  my %constraints = $q->constraints;

The constraints are cached (ie only calculated once per instance).

=cut

sub constraints {
  my $self = shift;

  # Check in cache
  return %{ $self->{Constraints} } if $self->{Constraints};

  # Get the query in hash form
  my $href = $self->query_hash;

  # Default values
  my %constraints = (
		     observability => 1,
		     remaining => 1,
		     allocation => 1,
		    );

  # Go through the disableconstraint array making a hash
  if (exists $href->{disableconstraint}) {
    for my $con (@{ $href->{disableconstraint} } ) {
      $con = lc( $con );
      # immediately drop out if we hit "all"
      if ($con eq "all" ) {
	for my $key (keys %constraints) {
	  $constraints{$key} = 0;
	}
	last;
      } elsif (exists $constraints{$con}) {
	# If its in the allowed constraints list set to false
	$constraints{$con} = 0;
      }
    }
  }

  # Store it in cache
  $self->{Constraints} = \%constraints;

  return %constraints;

}

=back

=head2 General Methods

=over 4

=item B<sql>

Returns an SQL representation of the MSB Query using the specified
database table.

  $sql = $query->sql( $msbtable, $obstable, $projtable );

Returns undef if the query could not be formed.

The query includes explicit tests to make sure that time remains
on the project and that the target is available (in terms of being
above the horizon and in terms of being schedulable)

=cut

sub sql {
  my $self = shift;

  throw OMP::Error::MSBMalformedQuery("sql method invoked with incorrect number of arguments\n") 
    unless scalar(@_) ==3;

  my ($msbtable, $obstable, $projtable) = @_;

  # Generate the WHERE clause from the query hash
  # Note that we ignore elevation, airmass and date since
  # these can not be dealt with in the database at the present
  # time [they are used to calculate source availability]
  # Disabling constraints on queries should be left to this
  # subclass
  my $subsql = $self->_qhash_tosql( [qw/ elevation airmass date
				     disableconstraint /]);

  # If the resulting query contained anything we should prepend
  # an AND so that it fits in with the rest of the SQL. This allows
  # an empty query to work without having a naked "AND".
  $subsql = " AND " . $subsql if $subsql;

  #print "SQL: $subsql\n";

  # Some explanation is probably in order.
  # We do three queries
  # 1. Do a query on MSB and OBS tables looking for relevant
  #    matches but only retrieving the matching MSBID, the
  #    corresponding MSB obscount and the total number of observations
  #    that matched within each MSB. The result is stored to a temp table
  # 2. Query the temporary table to determine all the MSB's that had
  #    all their observations match and return the MSB information

  # We also DROP the temporary table immediately since sybase
  # keeps them around for until the connection is ended.

  # It is assumed that the observation information will be retrieved
  # in a subsequent query if required.

  # Get the names of the temporary tables
  # Sybase limit if 13 characters for uniqueness
  my $tempcount = "#ompcnt";
  my $tempmsb = "#ompmsb";


  # Additionally there are a number of constraints that are
  # always applied to the query simply because they make
  # sense for the OMP. These are:
  #  observability  - is the source up
  #  remaining      - is the MSB still to be observed
  #  allocation     - has the full project allocation been used
  # These constraints can be disabled individually by using
  # XML eg. <disableconstraint>observability</disableconstraint>
  # All can be disabled using "all".
  my %constraints = $self->constraints;
  my $constraint_sql = '';

  $constraint_sql .= " AND M.remaining > 0 " if $constraints{remaining};
  $constraint_sql .= " AND (P.remaining - P.pending) >= M.timeest " 
    if $constraints{allocation};

  # Now need to put this SQL into the template query
  my $sql = "(SELECT
          M.msbid, M.obscount, COUNT(*) AS nobs
           INTO $tempcount
           FROM $msbtable M,$obstable O, $projtable P
            WHERE M.msbid = O.msbid
              AND P.projectid = M.projectid
               $constraint_sql
                $subsql
              GROUP BY M.msbid)
               (SELECT * FROM $msbtable M2, $tempcount T
                 WHERE M2.msbid = T.msbid
                   AND M2.obscount = T.nobs)

                DROP TABLE $tempcount";

  #print "$sql\n";

  return "$sql\n";

  # To subvert query
  return "SELECT * FROM $msbtable WHERE remaining > 0";
}

=begin __PRIVATE__METHODS__

=item B<_root_element>

Class method that returns the name of the XML root element to be
located in the query XML. This changes depending on whether we
are doing an MSB or Project query.
Returns "MSBQuery" by default.

=cut

sub _root_element {
  return "MSBQuery";
}

=item B<_post_process_hash>

Go through the hash creating C<OMP::Range> objects where appropriate
and fixing up known issues such as "cloud" and "moon" which are
treated as lower limits rather than exact matches.

  $query->_post_process_hash( \%hash );

"date" strings are converted to a date object.

"date", "tau" and "seeing" queries are each converted to two separate
queries (one on "max" and one on "min") [but the "date" key is
retained so that the reference date can be obtained in order to
calculate source availability).

Also converts abbreviated form of project name to the full form
recognised by the database.

=cut

sub _post_process_hash {
  my $self = shift;
  my $href = shift;

  # Do the generic pre-processing
  $self->SUPER::_post_process_hash( $href );

  # Need a telescope
  throw OMP::Error::MSBMalformedQuery( "Please supply a telescope")
    unless exists $href->{telescope};

  # We always need a reference date
  if (exists $href->{date}) {
    # But not a date range
    throw OMP::Error::MSBMalformedQuery( "date can not be specified as a range. Only a specific date can be supplied.")
      unless ref($href->{date}) eq "ARRAY";

  } else {
    # Need to get a gmtime object that stringifies as a Sybase date
    my $date = gmtime;

    # Rebless
    bless $date, "Time::Piece::Sybase";

    # And store it
    $href->{date} = [ $date ];

  }

  # Also do timeest as a special case since that becomes
  # a hash (and so wont be modified in the loop once converted
  # to a range)
  if (exists $href->{timeest}) {

    my $key = "timeest";

    # Need the estimated time to be in seconds
    # Look at the attributes
    if (exists $href->{_attr}->{$key}->{units}) {
      my $units = $href->{_attr}->{$key}->{units};

      my $factor = 1; # multiplication factor
      if ($units =~ /^h/) {
	$factor = 3600;
      } elsif ($units =~ /^m/) {
	$factor = 60;
      }

      # Now scale all values by this factor
      if (ref($href->{timeest}) eq 'HASH') {
	for (keys %{ $href->{timeest} }) {
	  $href->{timeest}->{$_} *= $factor;
	}
      } elsif (ref($href->{timeest}) eq 'ARRAY') {
	for (@{ $href->{timeest}}) {
	  $_ *= $factor;
	}
      }
    }
  }

  # Loop over each key
  for my $key (keys %$href ) {
    # Skip private keys
    next if $key =~ /^_/;

    if ($key eq "cloud" or $key eq "moon") {
      # convert to range with the supplied value as the min
      $href->{$key} = new OMP::Range( Min => $href->{$key}->[0] );

    } elsif ($key eq "seeing" or $key eq "tau" or $key eq "date") {
      # Convert to two independent ranges

      # Note that taumin indicates a MAX for the supplied value
      # and taumax indicates a minimum for the supplied value
      my %outkey = ( max => "Min", min => "Max");

      # Loop over min and max
      for my $type (qw/ min max /) {
	$href->{"$key$type"} = new OMP::Range( $outkey{$type} =>
					       $href->{$key}->[0]);
      }

      # And remove the old key (unless it is the reference date)
      delete $href->{$key} unless $key eq "date";

    } elsif ($key eq 'projectid') {

      # Get the telescope and date if we know it
      my %options;
      $options{telescope} = $href->{telescope}->[0] 
	if exists $href->{telescope};
      $options{date} = $href->{date}->[0]
	if exists $href->{date}->[0];

      # Translate project IDs
      for my $pid (@{ $href->{$key}}) {
	$pid = OMP::General->infer_projectid(%options,
					     projectid => $pid);
      }

    }

  }

  # Case sensitivity
  # If we are dealing with a these we should make sure we upper
  # case them (more efficient to upper case everything than to do a
  # query that ignores case)
  $self->_process_elements($href, sub { uc(shift) }, 
			   [qw/projectid telescope semester country/]);


  # These entries are in more than one table so we have to 
  # explicitly choose the MSB table
  for (qw/ projectid timeest /) {
    if (exists $href->{$_}) {
      my $key = "M.$_";
      $href->{$key} = $href->{$_};
      delete $href->{$_};
    }
  }

  # Remove attributes since we dont need them anymore
  delete $href->{_attr};

}


=end __PRIVATE__METHODS__

=back

=head1 Query XML

The Query XML is specified as follows:

=over 4

=item B<MSBQuery>

The top-level container element is E<lt>MSBQueryE<gt>.

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

=item B<Reference date>

The C<date> element can be used to specify a specific date
for the query. This date is used for determining source availability
and is compared with any date constraints for a particular MSB. If a date
is not supplied the current date is automatically inserted. The date
should be supplied in ISO format YYYY-MM-DDTHH:MM

  <date>2002-04-15T04:52</date>

=item B<cloud and moon>

Queries on "cloud" and "moon" columns are really a statement of the
current weather conditions rather than a request for a match of exactly
the specified value. In fact these elements are really saying that the
retrieved records should be within the range 0 to the value in the table.
ie the table contains an upper limit with an implied lower limit of zero.

This translates to an effective query of:

  <moon><min>2</min></moon>

Queries on "cloud" and "moon" are translated to this form.

=item B<tau and seeing>

Queries including tau and seeing reflect the current weather conditions
but do not correspond to an equivalent table in the database. The database
contains allowable ranges (e.g. taumin and taumax) and the supplied
value must lie within the range. Therefore for a query such as:

  <tau>0.06</tau>

the query would become

  taumin <= 0.05 AND taumax >= 0.05

=item B<target observability>

Constraints on the observability of the target are not calculated in
SQL. These must be done post-query. Methods are provided to make the
target constraints available (essentially the minimum elevation).

=item B<constraints>

Additionally there are a number of constraints that are
always applied to the query simply because they make
sense for the OMP. These are:

 observability  - is the source up
 remaining      - is the MSB still to be observed
 allocation     - has the full project allocation been used

These constraints can be disabled individually by using
XML for example,

 <disableconstraint>observability</disableconstraint>

Any number of these elements can be included.

Alternatively all scheduling constraints can be disabled
using "all".

 <disableconstraint>all</disableconstraint>

=back

=head1 SEE ALSO

OMP/SN/004, C<OMP::DBQuery>

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
