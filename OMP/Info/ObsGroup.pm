package OMP::Info::ObsGroup;

=head1 NAME

OMP::Info::ObsGroup - General manipulations of groups of Info::Obs objects

=head1 SYNOPSIS

  use OMP::Info::ObsGroup;

  $grp = new OMP::Info::ObsGroup( obs => \@obs );
  $grp = new OMP::Info::ObsGroup( instrument => 'SCUBA',
                            date => '1999-08-15');

  $grp = new OMP::Info::ObsGroup( instrument => 'SCUBA',
                            projectid => 'm02ac46');

  $grp->obs( @obs );
  @obs = $grp->obs;

  $grp->runQuery( $query );
  $grp->populate( instrument => 'SCUBA', projectid => 'M02BU52');

  %summary = $grp->stats;
  $html = $grp->format( 'html' );

  %grouping = $grp->groupby_msbid;
  %grouping = $grp->groupby_inst;
  %grouping = $grp->groupby_mode;

  # retrieve OMP::Info::MSB objects
  @msbs = $grp->getMSBs;

=head1 DESCRIPTION

This class is a place for general purpose methods that can
dela with groups of observations (as OMP::Info::Obs objects). Including
retrieval of observations for particular dates and obtaining
statistical information and summary from groups of observations.

=cut

use 5.006;
use strict;
use warnings;
use OMP::DBbackend::Archive;
use OMP::ArchiveDB;
use OMP::ArcQuery;
use OMP::ObslogDB;
use OMP::Info::Obs;
use OMP::Error qw/ :try /;

use vars qw/ $VERSION /;
$VERSION = 0.01;

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

Object constructor. Accept arguments in hash form with keys:

  obs - expects to point to array ref of Info::Obs objects
  telescope/instrument/projectid - arguments recognized by
     populate methods are forwarded to the populate method.

  $grp = new OMP::Info::ObsGroup( obs => \@obs );

=cut

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my %args = @_;

  my $grp = bless {
		   ObsArray => [],
		  }, $class;

  # if we have an "obs" arg we just store the objects
  if (exists $args{obs}) {
    $grp->obs($args{obs});
  } elsif (@_) {
    # any other args are forwarded to populate
    $grp->populate( %args );
  }

  return $grp;
}

=back

=head2 Accessor Methods

=over 4

=item B<obs>

Retrieve (or set) the array of observations that are to be manipulated
by this class.

  $ref = $grp->obs;
  @obs = $grp->obs;
  $grp->obs(\@obs);
  $grp->obs(@obs);

All elements in the supplied arrays I<must> be of class
C<OMP::Info::Obs> (or subclass thereof).

All previous entries are removed when new observation objects
are stored.

=cut

sub obs {
  my $self = shift;
  if (@_) {
    my @obs;
    # look for ref to array
    if (ref($_[0]) eq 'ARRAY') {
      @obs = @{$_[0]};
    } else {
      @obs = @_;
    }

    for (@obs) {
      throw OMP::Error::BadArgs("Observation must be a OMP::Info::Obs")
	unless UNIVERSAL::isa($_,"OMP::Info::Obs");
    }

    @{$self->{ObsArray}} = @obs;
  }
  if (wantarray) {
    return @{$self->{ObsArray}};
  } else {
    return $self->{ObsArray};
  }
}

=back

=head2 General Methods

=over 4

=item B<runQuery>

Run a query on the archive (using an OMP::ArcQuery object),
store the results and attach any relevant comments.

  $grp->runQuery( $query );

Previous observations are overwritten.

=cut

sub runQuery {
  my $self = shift;
  my $q = shift;

  throw OMP::Error::FatalError("runQuery: The query argument must be an OMP::ArcQuery class")
    unless UNIVERSAL::isa($q, "OMP::ArcQuery");

  # Grab the results.
  my $adb = new OMP::ArchiveDB();
  try {
    my $db = new OMP::DBbackend::Archive;
    $adb->db( $db );
  }
  catch OMP::Error::DBConnection with {
    # let it pass through
  };
  my @result = $adb->queryArc( $q );

  # Store the results
  $self->obs(\@result);

  # Attach comments
  $self->commentScan;

  return;
}

=item B<numobs>

Returns the number of observations within the group.

  $num = $grp->numobs;

=cut

sub numobs {
  my $self = shift;
  my $obs = $self->obs;
  return scalar(@$obs);
}

=item B<populate>

Retrieve the observation details and associated comments for
the specified instrument and/or UT date and/or project.
The results are stored in the object and retrievable via
the C<obs> method.

  $grp->populate( instrument => $inst,
                  date => $date,
                  projectid => $proj);


This requires access to the obs log database (C<OMP::ObslogDB>) and
also C<OMP::ArchiveDB>. The archive connections are handled
automatically.

UT date can be either "YYYY-MM-DD" string or a Time::Piece
object from which "YYYY-MM-DD" is extracted.

Currently, only one instrument is supported at a time.
This could be modified to support a telescope and/or instrument
in the future with minor tweaks to the calling arguments.

The method will fail if an instrument is not supplied. It will
also fail if one of "date" or "projectid" are not present (otherwise
the query will not be constrained).

Usually called from the constructor.

IF THE TELESCOPE IS JCMT AND NO INSTRUMENT IS SUPPLIED WE FORCE
SCUBA AS THE INSTRUMENT BECAUSE ARCHIVEDB CAN NOT YET HANDLE
TO SEPARATE DATABASE QUERIES.

=cut

sub populate {
  my $self = shift;
  my %args = @_;

  throw OMP::Error::BadArgs("Must supply a telescope or instrument or projectid")
    unless exists $args{telescope} || exists $args{instrument}
      || exists $args{projectid};

  # if we have a date it could be either object or string
  # also need special XML code
  my $xmlbit = '';
  if (exists $args{date}) {
    if (ref($args{date})) {
      $args{date} = $args{date}->strftime("%Y-%m-%d");
    }
    $xmlbit = "<date delta=\"1\">$args{date}</date>";
  }

  # If we have a project ID but no telescope we must determine
  # the telescope from the database
  if (exists $args{projectid} && !exists $args{telescope}) {
    # KLUGE need to know the password for this. Should we really
    # ask or can we assume it is okay?????
    my $proj = OMP::ProjServer->projectDetails($args{projectid},
					       '***REMOVED***',
					       'object');
    $args{telescope} = $proj->telescope;
  }

  # KLUGE JCMT and SCUBA
  $args{instrument} = 'scuba' if (!exists $args{instrument} &&
				  exists $args{telescope} &&
				  $args{telescope} =~ /jcmt/i);

  # Form the XML.[restrict the keys
  for my $key (qw/ instrument telescope projectid/ ) {
    if (exists $args{$key}) {
      $xmlbit .= "<$key>$args{$key}</$key>";
    }
  }


  my $xml = "<ArcQuery>$xmlbit</ArcQuery>";

  # Form the query.
  my $arcquery = new OMP::ArcQuery( XML => $xml );

  # run the query
  $self->runQuery( $arcquery );

}

=item B<commentScan>

Ensure that the comments stored in the observations are up-to-date.

 $grp->commentScan;

=cut

sub commentScan {
  my $self = shift;
  my $obs = $self->obs;

  # Add the comments.
  my $odb = new OMP::ObslogDB( DB => new OMP::DBbackend );
  $odb->updateObsComment( $obs );

}

=item B<projectStats>

Return an array of C<Project::TimeAcct> objects for the given
C<ObsGroup> object.

  @timeacct = $obsgroup->projectStats;

This method will determine all the projects in the given
C<ObsGroup> object, then use time allocations in that object
to populate the C<Project::TimeAcct> objects.

=cut

sub projectStats {
  my $self = shift;
  my @obs = $self->obs;

  my %hash;
  my @return;

  foreach my $obs ( @obs ) {
    my $projectid = $obs->projectid;
    my $startobs = $obs->startobs;
    my $endobs = $obs->endobs;
    my $timespent;
    if( defined( $startobs ) &&
        defined( $endobs ) ) {
      $timespent = $endobs - $startobs;
    } else {
      $timespent = Time::Seconds->new( $obs->duration );
    }
    my $date = OMP::General->parse_date( $obs->startobs->ymd );

    # Check to see if this project on this date has time already.
    if(defined($hash{$obs->startobs->ymd}{$projectid})) {

      # Add the time in the current observation to the TimeAcct
      # object that is already there.
      $hash{$obs->startobs->ymd}{$projectid}->incTime( $timespent );
    } else {

      # Create a new TimeAcct object.
      $hash{$obs->startobs->ymd}{$projectid} = new OMP::Project::TimeAcct(
                                                 projectid => $projectid,
                                                 date => $date,
                                                 timespent => $timespent );
    }
  }

  # And create the array out of the hash.
  foreach my $ymd (keys %hash) {
    foreach my $projectid (keys %{$hash{$ymd}}) {
      push @return, $hash{$ymd}{$projectid};
    }
  }

  return @return;

}

=back

=head1 SEE ALSO

For related classes see C<OMP::ArchiveDB> and C<OMP::ObslogDB>.

=head1 AUTHORS

Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>,
Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
