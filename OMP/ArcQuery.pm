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
  if ( exists $href->{_telescope} ) {
    $telescope = $href->{_telescope}->[0];
  } else {
    throw OMP::Error::DBMalformedQuery( "No telescope supplied!");
  }

  return $telescope;
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
  my $subsql = $self->_qhash_tosql();

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

  # print "SQL: $sql\n";
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

Note that this translation requires that we can determine the
instrument (at least) or telescope from the query. A query on the JCMT
tables must involve two tables and many OR clauses. No attempt is
made to combine queries to separate telescopes.

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

  # Telescope is renamed _telescope so that it skips the
  # SQL creation [can also only have one telescope]
  if (exists $href->{telescope}) {
    throw OMP::Error::DBMalformedQuery("Can not mix multiple telescopes in a single query") if scalar(@{$href->{telescope}}) > 1;
    $href->{_telescope} = $href->{telescope};
    delete $href->{telescope};
  }

  # Loop over instruments if specified
  # This is required for a sanity check
  my %tables;
  if (exists $href->{instrument}) {
    my %tels;
    for my $inst (@{ $href->{instrument} }) {
      $inst = uc($inst);
      if ($inst eq "SCUBA") {
	$tables{$SCUTAB}++;
	$tels{JCMT}++;
      } elsif ($inst =~ /^RX/) {
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

    if (exists $href->{_telescope} && !exists $tels{$href->{_telescope}->[0]}) {

      throw OMP::Error::DBMalformedQuery("Can not mix multiple telescopes in a single query [implied telescope differs from specified telescope]");


    } else {
      # Store the telescope
      $href->{_telescope} = [ keys %tels ];

    }
	
  } else {
    # No instrument specified so we must select the tables
    my $tel = $href->{_telescope}->[0];
    if ($tel eq 'UKIRT') {
      $tables{$UKIRTTAB}++;
    } elsif ($tel eq 'JCMT') {
      for ($SCUTAB, $GSDTAB) {
	$tables{$_}++;
      }
    } else {
      throw OMP::Error::DBMalformedQuery("Unable to determine tables from telescope name " . $tel);
    }
  }

  # Now store the selected tables
  $self->_tables( keys %tables );


  # Loop over each key
  for my $key (keys %$href ) {
    # Skip private keys
    next if $key =~ /^_/;

    # Protect against rounding errors
    # Not sure we need this so leave it out for now
    #if ($key eq 'faultid') {
    # Need to loop over each fault
    #  $href->{$key} = [
    #		       map {
    #			 new OMP::Range(Min => ($_ - 0.0005),
    #					Max => ($_ + 0.0005))
    #		       } @{ $href->{$key} } ];

    #    }

  }


  # Translate the query to be table specific
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

  # Remove attributes since we dont need them anymore
  delete $href->{_attr};

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
