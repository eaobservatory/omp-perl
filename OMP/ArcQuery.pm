package OMP::ArcQuery;

=head1 NAME

OMP::ArcQuery - Class representing an XML OMP query of the header archive

=head1 SYNOPSIS

  $query = new OMP::ArcQuery( XML => $xml );
  $sql = $query->sql( $table );

=head1 DESCRIPTION

This class can be used to process data archive header queries.
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

use Time::Piece;
use Time::Seconds;

# TABLES
our $SCUTAB = 'archive..SCU S';
our $GSDTAB = 'jcmt..SCA G';
our $UKIRTTAB = 'ukirt..COMMON U';


# Inheritance
use base qw/ OMP::DBQuery /;

# Package globals

our $VERSION = (qw$Revision$ )[1];

=head1 METHODS

=head2 Accessor Methods

=over 4


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
    $self->query_hash( {} );
  }
  return $self->{IsFILE};
}

=item B<mindate>

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

  if( ref( $query_hash->{date} ) eq 'ARRAY' ) {
    if (scalar( @{$query_hash->{date}} ) == 1) {
      my $timepiece = new Time::Piece;
      $timepiece = $query_hash->{date}->[0];
      my $maxdate;
      if( ($timepiece->hour == 0) && ($timepiece->minute == 0) && ($timepiece->second == 0) ) {
        # We're looking at an entire day, so set up an OMP::Range object with Min equal to this
        # date and Max equal to this date plus one day.
        $maxdate = $timepiece + ONE_DAY - 1; # constant from Time::Seconds
      } else {
        # We're looking at a specific time, so set up an OMP::Range object with Min equal to
        # this date minus one second and Max equal to this date plus one second. These plus/minus
        # seconds are necessary because OMP::Range does an exclusive check instead of inclusive.
        $maxdate = $timepiece + 1;
        $timepiece = $timepiece - 1;
      }
      $daterange = new OMP::Range( Min => $timepiece, Max => $maxdate );
    }
  } elsif( UNIVERSAL::isa( $query_hash->{date}, "OMP::Range" ) ) {
    $daterange = $query_hash->{date};
    # Subtract one second from the range, because the max date is not inclusive.
    my $max = $daterange->max;
    $max = $max - 1;
    $daterange->max($max);
  } else {
    throw OMP::Error( "Unable to get date range from query" );
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
  } else {
    return 0;
  }
}

=item B<telescope>

Telescope to use for this query. This governs the query since the
tables are different.

A telescope must be specified in the query.

=cut

sub telescope {
  my $self = shift;

  # Get the hash form of the query
  my $href = $self->query_hash;

  # check for telescope
  my $telescope;
  if ( exists $href->{telescope} ) {
    $telescope = $href->{telescope}->[0];
  } else {
    throw OMP::Error::DBMalformedQuery( "No telescope supplied!");
  }

  return $telescope;
}

=item B<instrument>

Instrument to use for this query. Returns undef if no instrument
is supplied.

=cut

sub instrument {
  my $self = shift;

  # Get the hash form of the query
  my $href = $self->query_hash;

  # check for telescope
  my $instrument;
  if ( exists $href->{instrument} ) {
    $instrument = $href->{instrument}->[0];
  }

  return $instrument;
}

=item B<_tables>

List of database tables used for this query. They are usually
just joined by a comma and placed in the initial line of the
SQL.

  $q->_tables( @tables );
  @tables = $q->_tables;

In principal the entries should match values stored in the global
table variables used in this class but we do not check this.

=cut

sub _tables {
  my $self = shift;
  if (@_) { $self->{Tables} = [ @_ ]; }
  return @{ $self->{Tables}};
}

=back

=head2 General Methods

=over 4

=item B<sql>

Returns an SQL representation of the database Archive header XML Query.

  $sql = $query->sql();

Returns undef if the query could not be formed.

=cut

sub sql {
  my $self = shift;

  throw OMP::Error::DBMalformedQuery("sql method invoked with incorrect number of arguments\n") 
    unless scalar(@_) == 0;

  # Generate the WHERE clause from the query hash
  my $subsql = $self->_qhash_tosql( [qw/ telescope /]);

  # Construct the the where clause. Depends on which
  # additional queries are defined
  my @where = grep { $_ } ( $subsql );
  my $where = '';
  $where = " WHERE " . join( " AND ", @where)
    if @where;

  # Now need to put this SQL into the template query
  # Need to switch on telescope
  my $tel = $self->telescope;
  my $tabsql = join(", ", $self->_tables);
  throw OMP::Error::DBMalformedQuery("No tables specified!")
    unless $self->_tables;
  my $sql;
  if ($tel eq 'JCMT') {

    # SCUBA only for now [note that we explicitly
    # select the database and table
    $sql = "SELECT * FROM $tabsql $where";

  } elsif ($tel eq 'UKIRT') {

    # UKIRT - query common table first
    $sql = "SELECT * FROM $tabsql $where ORDER BY UT_DATE";

  } else {
    throw OMP::Error::DBMalformedQuery("Unknown telescope: $tel\n");
  }

  #print "SQL: $sql\n";
  return "$sql\n";

}

=begin __PRIVATE__METHODS__

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

  $query->_post_process_hash( \%hash );

We can not provide a generic interface to queries without providing a
lookup table to go from a XML query to a specific table row. The
following are supported:

 <date>      : "ut" on SCUBA and GSD, "UT_DATE" on UKIRT
 <instrument>: none on SCUBA, "frontend" on GSD, "INSTRUME" on UKIRT
 <projectid> : "proj_id" SCUBA, "projid" GSD, none on UKIRT
 <obsnum>    : "run" on SCUBA, "scan" on GSD, "OBSNUM" on UKIRT

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

# Lookup table
my %lut = (
	   # XML tag -> database table -> column name
	   instrument => {
			  $SCUTAB => undef, # implied
			  $GSDTAB => 'G.frontend',
			  $UKIRTTAB => 'U.INSTRUME',
			 },
	   date => {
		    $SCUTAB => 'S.ut',
		    $GSDTAB => 'G.ut',
		    $UKIRTTAB => 'U.UT_DATE',
		   },
	   obsnum => {
		    $SCUTAB => 'S.run',
		    $GSDTAB => 'G.scan',
		    $UKIRTTAB => 'U.OBSNUM',
		   },
	   projectid => {
		    $SCUTAB => 'S.proj_id',
		    $GSDTAB => 'G.projid',
		    $UKIRTTAB => 'U.project',
		   },

	  );


sub _post_process_hash {
  my $self = shift;
  my $href = shift;

  # Do the generic pre-processing
  $self->SUPER::_post_process_hash( $href );

  # If we're looking at a file, we don't need to do these translations.
  if($self->isfile) {
    return;
  }

  # Check we only have one instrument
  if (exists $href->{telescope}) {
    throw OMP::Error::DBMalformedQuery("Can not mix multiple telescopes in a single query") if scalar(@{$href->{telescope}}) > 1;
  }

  # Loop over instruments if specified
  # This is required for a sanity check to make sure incorrect combos are
  # trapped
  my %tables;
  if (exists $href->{instrument}) {
    my %tels;
    for (@{ $href->{instrument} }) {
      my $inst = uc($_);
      if ($inst eq "SCUBA") {
	$tables{$SCUTAB}++;
	$tels{JCMT}++;
      } elsif ($inst =~ /^(RX|UKT)/i) {
	$tables{$GSDTAB}++;
	$tels{JCMT}++;
      } elsif ($inst =~ /^(CGS4|IRCAM|UFTI|MICHELLE|UIST)/) {
	$tables{$UKIRTTAB}++;
	$tels{UKIRT}++;
      } else {
	throw OMP::Error::DBMalformedQuery("Unknown instrument: $inst");
      }
    }

    # Prevent ukirt and jcmt together
    throw OMP::Error::DBMalformedQuery("Can not mix multiple telescopes in a single query [inferred from instrument choice]") if scalar(keys %tels) > 1;

    if (exists $href->{telescope} && !exists $tels{$href->{telescope}->[0]}) {

      throw OMP::Error::DBMalformedQuery("Can not mix multiple telescopes in a single query [implied telescope differs from specified telescope]");


    } else {
      # Store the telescope
      $href->{telescope} = [ keys %tels ];

    }

    # Finally - make sure that we are not mixing tables at JCMT
    if ($href->{telescope}->[0] eq 'JCMT') {
      if (exists $tables{$GSDTAB} && exists $tables{$SCUTAB}) {
	throw OMP::Error::DBMalformedQuery("Unfortunately can not mix a SCUBA and heterodyne query.");
      }
    }


  } else {

    # No instrument specified so we must select the tables
    my $tel = $href->{telescope}->[0];
    if ($tel eq 'UKIRT') {
      $tables{$UKIRTTAB}++;
    } elsif ($tel eq 'JCMT') {
      # Just use GSDTAB by default
      $tables{$GSDTAB}++;
    } else {
      throw OMP::Error::DBMalformedQuery("Unable to determine tables from telescope name " . $tel);
    }
  }

  # Now store the selected tables
  $self->_tables( keys %tables );

  # Translate the query to be table specific
  # Note that this ruins the hash to a certain extent.
  for my $xmlkey (keys %lut) {
    if (exists $href->{$xmlkey}) {

      # Save the entry and create a new subhash
      my $entry = $href->{$xmlkey};
      $href->{$xmlkey} = {};

      # Now loop over the relevant tables
      # The real trick here is that the table queries
      # should be ORed together rather than ANDed
      # since we want to find all observations which
      # are within a date range in each table rather than
      # in *BOTH* tables. The trick is indicating to the
      # SQL builder that we mean to do this
      # Indicate it by an array/range within another hash
      # date => { U.UT_DATE => [], S.ut => [] }
      for my $table (keys %tables) {
	# Find the column name for this table
	my $column = $lut{$xmlkey}->{$table};

	# Skip it if the key is not defined
	next unless defined $column;

	# Copy the entry to the new hash
	$href->{$xmlkey}->{$column} = $entry;
      }

      # Delete the key if we didnt put anything in it
      # This will break if someone does a search for
      # SCUBA or heterodyne since there will not be a
      # corresponding clause for SCUBA
      delete $href->{$xmlkey} unless scalar(keys %{$href->{$xmlkey}});

    }
  }

  # These things should be lower/upper cased [note that we dont use href directly]
  if (exists $href->{instrument}) {
    $self->_process_elements($href->{instrument}, sub { lc(shift) }, 
			     [ $lut{instrument}{$GSDTAB} ] );
    $self->_process_elements($href->{instrument}, sub { uc(shift);}, 
			     [ $lut{instrument}{$UKIRTTAB}]);
  }
  if (exists $href->{projectid}) {
    $self->_process_elements($href->{projectid}, sub { lc(shift);  }, 
			     [ $lut{projectid}{$GSDTAB},
			       $lut{projectid}{$SCUTAB}]);
    $self->_process_elements($href->{projectid}, sub { uc(shift) }, 
			     [ $lut{projectid}{$UKIRTTAB} ] );
  }

  # Remove attributes since we dont need them anymore
  delete $href->{_attr};

}

=item B<_create_sql_recurse>

Routine called to translate each key of the query hash into SQL.
Separated from C<_qhash_tosql> in order to allow recursion.
Returns a chunk of SQL

  $sql = $self->_create_sql( $column, $entry );

where C<$column> is the database column name and 
C<$entry> can be 

  - An array of values that will be ORed
  - An OMP::Range object
  - A hash containing items to be ORed
    using the rules for OMP::Range and array refs
    [hence recursion]

KLUGE: If the key begins with TEXTFIELD__ a "like" match
will be performed rather than a "=". This is so that text fields
can be queried.

Column names beginning with an _ are ignored.

Any ranges made up of Time::Piece objects will have one second
subtracted from the end date, such that date ranges are inclusive
on the minimum and exclusive on the maximum.

=cut

sub _create_sql_recurse {
  my $self = shift;
  my $column = shift;
  my $entry = shift;

  return undef if $column =~ /^_/;

  my $sql;
  if (ref($entry) eq 'ARRAY') {

    # default to actual column name and simple equality
    my $colname = $column;
    my $cmp = "equal";
    if ($colname =~ /^TEXTFIELD__/) {
      $colname =~ s/^TEXTFIELD__//;
      $cmp = "like";
    }

    # use an OR join [must surround it with parentheses]
    $sql = "(".join(" OR ",
		    map { $self->_querify($colname, $_, $cmp); }
		    @{ $entry }
		   ) . ")";

  } elsif (UNIVERSAL::isa( $entry, "OMP::Range")) {
    # A Range object
    my %range = $entry->minmax_hash;

    # We need to redefine the max date so that this check will be
    # exclusive on the maximum, so that we don't return entries
    # from the UKIRT archive for the day we want plus the next
    # day (because dates in the UKIRT archive only have a resolution
    # of one day and not one second)
    if (UNIVERSAL::isa( $range{'max'}, "Time::Piece")) {
      $range{'max'} -= 1;
      bless $range{'max'}, ref($range{'min'});
    }

    # an AND clause
    $sql = join(" AND ",
		map { $self->_querify($column, $range{$_}, $_);}
		keys %range
	       );

  } elsif (ref($entry) eq 'HASH') {
    # Call myself but join with an OR
    my @chunks = map { $self->_create_sql_recurse( $_, $entry->{$_} )
		      } keys %$entry;

    # Need to bracket each of the sub entries
    $sql = "(". join(" OR ", map { "($_)" } @chunks ) . ")";

  } else {
    # use Data::Dumper;
    # print Dumper($entry);

    throw OMP::Error::DBMalformedQuery("Query hash contained a non-ARRAY non-OMP::Range non-HASH for $column: $entry\n");
  }

  # print "SQL: $column: $sql\n";
  return $sql;
}

=end __PRIVATE__METHODS__

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

L<OMP::DBQuery>, L<OMP::MSBQuery>

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
