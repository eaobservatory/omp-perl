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

  %grouping = $grp->groupby('msbid');
  %grouping = $grp->groupby('instrument');

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
use OMP::Constants qw/ :timegap /;
use OMP::ProjServer;
use OMP::DBbackend::Archive;
use OMP::ArchiveDB;
use OMP::ArcQuery;
use OMP::ObslogDB;
use OMP::Info::Obs;
use OMP::Info::Obs::TimeGap;
use OMP::Error qw/ :try /;
use Data::Dumper;

use vars qw/ $VERSION $DEBUG/;
$VERSION = 0.02;
$DEBUG = 0;

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

Object constructor. Accept arguments in hash form with keys:

  obs - expects to point to array ref of Info::Obs objects
  telescope/instrument/projectid - arguments recognized by
     populate methods are forwarded to the populate method.
  timegap - interleaves observations with timegaps if a gap
            longer than the value in this hash is detected.

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

If a UT date and projectID are supplied then an additional parameter,
"inccal", can be supplied to indicate whether calibrations should
be included along with the project information. Defaults to false.
Note that if "inccal" is true it is likely that observations will
match even if no data was taken for the project. [As an aside maybe
we should have an extra flag that can be used to control that behaviour?
Returning no matches if no project data were found?]

IF THE TELESCOPE IS JCMT AND NO INSTRUMENT IS SUPPLIED WE FORCE
SCUBA AS THE INSTRUMENT BECAUSE ARCHIVEDB CAN NOT YET HANDLE
TWO SEPARATE DATABASE QUERIES.

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
    $args{telescope} = OMP::ProjServer->getTelescope( $args{projectid});
  }

  # KLUGE JCMT and SCUBA
  $args{instrument} = 'scuba' if (!exists $args{instrument} &&
				  exists $args{telescope} &&
				  $args{telescope} =~ /jcmt/i);

  # Liust of interesting keys for the query
  my @keys = qw/ instrument telescope /;

  # Calibrations?
  # If we have both a UT date and projectID we should look
  # for inccal. If it is true we need to modify the query so that
  # it does not include a projectid by default.
  my $inccal;
  if (exists $args{projectid} && exists $args{date} 
      && exists $args{inccal}) {
    $inccal = $args{inccal};
  }

  # if we are including calibrations we should not include projectid
  if (! $inccal) {
    push(@keys, "projectid");
  }

  # Form the XML.[restrict the keys
  for my $key ( @keys ) {
    if (exists $args{$key}) {
      $xmlbit .= "<$key>$args{$key}</$key>";
    }
  }


  my $xml = "<ArcQuery>$xmlbit</ArcQuery>";

  # Form the query.
  my $arcquery = new OMP::ArcQuery( XML => $xml );

  # run the query
  $self->runQuery( $arcquery );

  # If we are really looking for a single project plus calibrations we
  # have to massage the entries removing other science observations.
  if ($inccal && exists $args{projectid}) {

    my @newobs = grep { uc($_->projectid) eq uc($args{projectid}) 
			  || ! $_->isScience  } $self->obs;

    # store it [comments will already be attached]
    $self->obs(\@newobs);

  }

  # Add in timegaps if necessary.
  if(exists $args{timegap}) {
    $self->locate_timegaps( $args{timegap} );
  }

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
C<ObsGroup> object and associated warnings.

  my ($warnings, @timeacct) = $obsgroup->projectStats;

This method will determine all the projects in the given
C<ObsGroup> object, then use time allocations in that object
to populate the C<Project::TimeAcct> objects.

The first argument returned is an array of warning messages generated
by the time accounting tool. Usually these will indicate calibrations
that are not required by any science observations, or science 
observations that have no corresponding calibration.

Calibrations are shared amongst those projects that required
them. General calibrations are shared amongst all projects
in proportion to the amount of time used by the project.
Science calibrations that are not required by any project
are stored in the "$telCAL" project (eg UKIRTCAL or JCMTCAL).
These owner-less calibrations do not get allocated their share
of general calibrations. This may be a bug.

Observations taken outside the normal observing periods
are not charged to any particular project but are charged
to project $tel"EXTENDED". This definition of extended time
is telescope dependent. 

Does not yet take the observation status (questionable, bad, good)
into account when calculating the statistics. In principal observations
marked as bad should be charged to the general overhead.

Also does not charge for time gaps even if they have been flagged
as WEATHER.

=cut

sub projectStats {
  my $self = shift;
  my @obs = $self->obs;

  my @warnings;
  my %projbycal;
  my %cals;
  my %extended; # Extended time by telescope
  my %instlut; # Lookup table to map instruments to telescope when sharing
               # Generic calibrations

  # Go through all the observations, determining the time spent on 
  # each project and the calibration requirements for each observation
  # Note that calibrations are not spread over instruments
  my %night_totals;
  for my $obs (@obs) {
    my $projectid = $obs->projectid;

    # if we have a SCUBA project ID that seems to be a science observation
    # we charge this to projectID JCMTCAL. Clearly SCUBA::ODF should be responsible
    # for this logic but for now we add it here for testing.
    # This should be a rare occurence
    if ($projectid =~  /scuba/i && $obs->isScience) {
      # use JCMTCAL rather than tagging as a calibrator because we don't
      # want other people charged for it
      $projectid = 'JCMTCAL';
    }

    my $inst = $obs->instrument;
    my $startobs = $obs->startobs;
    my $tel = uc($obs->telescope);
    my $endobs = $obs->endobs;
    my $ymd = $obs->startobs->ymd;
    my $timespent;
    my $duration = $obs->duration;

    # We can calculate extended time so long as we have 2 of startobs, endobs and duration
    if( (defined $startobs && defined $endobs ) ||
        (defined $startobs && defined $duration) ||
	(defined $endobs   && defined $duration)
      ) {

      # Get the extended time
      ($timespent, my $extended) = OMP::General->determine_extended(
								    duration => $duration,
								    start=> $startobs,
								    end=> $endobs,
								    tel => $tel,
								   );

      # And sort out the EXTENDED time
      $extended{$ymd}{$tel} += $extended->seconds if defined $extended && $extended->seconds > 0;


    } else {
      # We cannot tell whether this was done in extended time or not
      # so assume not.
      $timespent = Time::Seconds->new( $obs->duration );
    }
    $night_totals{$ymd} += $timespent->seconds;

    # Create instrument telescope lookup
    $instlut{$ymd}{$inst} = $tel unless exists $instlut{$ymd}{$inst};

    my $cal = $obs->calType;
    if ($obs->isScience) {
      $projbycal{$ymd}{$projectid}{$inst}{$cal} += $timespent->seconds;
    } else {
      if ($obs->isGenCal) {
	# General calibrations are deemed to be instrument
	# specific (if you do a skydip for scuba you should
	# not be charged for it if you use RxA)
	$cals{$ymd}{$inst}{"CAL"} += $timespent->seconds;
      } else {
	$cals{$ymd}{$inst}{$cal} += $timespent->seconds;
      }
    }
  }

  print Dumper( \%projbycal, \%cals, \%extended) if $DEBUG;

  # Now go through the science observations to find the total
  # of each required calibration regardless of project
  my %cal_totals;
  for my $ymd (keys %projbycal) {
    for my $proj (keys %{$projbycal{$ymd}}) {
      for my $inst (keys %{$projbycal{$ymd}{$proj}}) {
	for my $cal (keys %{$projbycal{$ymd}{$proj}{$inst}}) {
	  $cal_totals{$ymd}{$inst}{$cal} += $projbycal{$ymd}{$proj}{$inst}{$cal};
	}
      }
    }
  }

  print "Science calibration totals:".Dumper(\%cal_totals) if $DEBUG;

  # Now we need to calculate project totals by apporitoning the
  # actual calibration data in proportion to the total amount
  # of time each project spent requiring these observations
  # This is still done on a per-instrument basis
  my %proj;
  for my $ymd (keys %projbycal) {
    for my $proj (keys %{$projbycal{$ymd}}) {
      for my $inst (keys %{$projbycal{$ymd}{$proj}}) {
	for my $cal (keys %{$projbycal{$ymd}{$proj}{$inst}}) {
	  # This project should be charged for calibrations
	  # as a fraction of the total time spent time on data
	  # that uses the calibration and instrument
	  if (exists $cals{$ymd}{$inst}{$cal}) {
	    # We have a calibration
	    my $caltime = $projbycal{$ymd}{$proj}{$inst}{$cal} / 
	      $cal_totals{$ymd}{$inst}{$cal} *
	      $cals{$ymd}{$inst}{$cal};

	    # Add on the actual observations
	    $proj{$ymd}{$proj}{$inst} += int($projbycal{$ymd}{$proj}{$inst}{$cal});

	    # And the calibrations
	    $proj{$ymd}{$proj}{$inst} += int($caltime);

	  } else {
	    # oops, no relevant calibrations...
	    push(@warnings, "No calibration data of type $cal for project $proj on $ymd\n");
	  }

	}
      }
    }
  }

  print "Proj after science calibrations:".Dumper( \%proj) if $DEBUG;

  # Now need to apportion the generic calibrations amongst
  # all the projects by instrument
  for my $ymd (keys %proj) {
    # Calculate the total project time for this instrument
    # including calibrations
    my %total;
    for my $proj (keys %{$proj{$ymd}}) {
      for my $inst (keys %{$proj{$ymd}{$proj}}) {
	$total{$inst} += $proj{$ymd}{$proj}{$inst};
      }
    }

    # Add on the general calibrations (for each instrument)
    for my $proj (keys %{$proj{$ymd}}) {
      for my $inst (keys %{$proj{$ymd}{$proj}}) {
	$proj{$ymd}{$proj}{$inst} += int( $cals{$ymd}{$inst}{CAL} * 
					  $proj{$ymd}{$proj}{$inst} / 
					  $total{$inst});
      }
    }
  }

  print "Proj after adding CAL: ".Dumper(\%proj) if $DEBUG;

  # Now go through and create a CAL entry for calibrations
  # that were not used by anyone. Technically the General data
  # should be shared onto CAL as well...For now, CAL is just treated
  # as non-science data that is not useful for anyone else
  for my $ymd (keys %cals) {
    for my $inst (keys %{ $cals{$ymd} }) {
      for my $cal (keys %{ $cals{$ymd}{$inst} } ) {
	# Skip general calibrations
	next if $cal =~  /CAL$/;

	# Check specific calibrations
	if (!exists $cal_totals{$ymd}{$inst}{$cal}) {
	  push(@warnings,"Calibration $cal is not used by any science observations on $ymd\n");
	  $proj{$ymd}{CAL}{$inst} += $cals{$ymd}{$inst}{$cal};
	}
      }
    }
  }

  # If we have some nights without any science calibrations we need
  # to charge it to CAL
  for my $ymd (keys %cals) {
    for my $inst (keys %{$cals{$ymd}}) {
      # Now need to look for this instrument usage on this date
      my $nocal;
      for my $proj (keys %{$projbycal{$ymd}}) {
	if (exists $projbycal{$ymd}{$proj}{$inst}) {
	  # Science data found for this instrument
	  $nocal = 1;
	  last;
	}
      }
      if (!$nocal) {
	# Need to add this to cal
	print "Adding on CAL data for $inst on $ymd of $cals{$ymd}{$inst}{CAL}\n" if $DEBUG;
	$proj{$ymd}{CAL}{$inst} += $cals{$ymd}{$inst}{CAL};
      }
    }
  }


  print "Proj after leftovers: " . Dumper(\%proj) if $DEBUG;

  # Now we need to add up all the projects by UT date
  my %proj_totals;
  for my $ymd (keys %proj) {
    for my $proj (keys %{$proj{$ymd}}) {
      for my $inst (keys %{$proj{$ymd}{$proj}}) {
	my $projkey = $proj;

	# If we have some shared calibrations that are not associated
	# with a project we need to associate them with a telescope
	# so that UKIRTCAL and JCMTCAL do not clash in the system
	if ($proj eq 'CAL') {
	  $projkey = $instlut{$ymd}{$inst} . "CAL";
	}

	$proj_totals{$ymd}{$projkey} += $proj{$ymd}{$proj}{$inst};
      }
    }
  }

  # Add in the extended time
  for my $ymd (keys %extended) {
    for my $tel (keys %{ $extended{$ymd} }) {
      my $key = $tel . "EXTENDED";
      $proj_totals{$ymd}{$key} += $extended{$ymd}{$tel};
    }
  }


  print "Final totals: ".Dumper(\%proj_totals) if $DEBUG;

  # Work out the night total
  if ($DEBUG) {
    for my $ymd (keys %proj_totals) {
      my $total = 0;
      for my $proj (keys %{$proj_totals{$ymd}}) {
	$total += $proj_totals{$ymd}{$proj};
      }
      $total /= 3600;
      printf "$ymd: %.1f hrs\n",$total;
      printf "From files: %.1f hrs\n", $night_totals{$ymd}/3600;
    }
  }

  # Now create the time accounting objects and store them in an
  # array
  my @timeacct;
  for my $ymd (keys %proj_totals) {
    my $date = OMP::General->parse_date( $ymd );
    print "Date: $ymd\n" if $DEBUG;
    for my $proj (keys %{$proj_totals{$ymd}}) {
      printf "Project $proj : %.1f\n", $proj_totals{$ymd}{$proj}/3600 if $DEBUG; 
      push @timeacct, new OMP::Project::TimeAcct(projectid => $proj,
						 date => $date,
						 timespent => new Time::Seconds($proj_totals{$ymd}{$proj})
						);
    }
  }

  return (\@warnings,@timeacct);

}

=item B<groupby>

Returns a hash of C<OMP::Info::ObsGroup> objects grouped by accessor.

  %grouped = $grp->groupby('instrument');

The argument must be a valid C<OMP::Info::Obs> accessor. If it is not,
this method will throw an C<OMP::Error::BadArgs> error.

The keys of the returned hash will be the discrete values for the accessor
found in the given C<OMP::Info::ObsGroup> object, and the values will be
C<OMP::Info::ObsGroup> objects corresponding to those keys.

=cut

sub groupby {
  my $self = shift;
  my $method = shift;

  throw OMP::Error::BadArgs("Cannot group by $method in Info::ObsGroup->groupby")
    unless OMP::Info::Obs->can($method);

  my %group;
  foreach my $obs ($self->obs) {
    push @{$group{$obs->$method}}, $obs;
  }

  return map { $_, new OMP::Info::ObsGroup(obs=>$group{$_}) } keys %group;

}

=item B<locate_timegaps>

Inserts C<OMP::Info::Obs::TimeGap> objects in appropriate locations
and sorts the C<ObsGroup> object by time.

  $obsgrp->locate_timegaps( $gap_length );

A timegap is inserted if there are more than C<gap_length> seconds between
the completion of one observation (taken to be the value of the C<end_obs>
accessor) and the start of the next (taken to be the value of the
C<start_obs> accessor). If the second observation is done with a different
instrument than the first, then the timegap will be an B<INSTRUMENT> type.
Otherwise, the timegap will be an B<UNKNOWN> type.

=cut

sub locate_timegaps {
  my $self = shift;
  my $length = shift;

  # Make sure the array of Obs objects is sorted in time, but only if there
  # actually are observations.
  my @obs = sort {
    $a->startobs <=> $b->startobs
  } $self->obs;

  my @newobs;
  for( my $i = 0; $i < $#obs; $i++ ) {
    my $curobs = $obs[$i];
    my $nextobs = $obs[$i+1];
    push @newobs, $curobs;

    if ( abs( $nextobs->startobs - $curobs->endobs ) > $length ) {

      my $timegap = new OMP::Info::Obs::TimeGap;
      # Aha, we have a timegap! We need to figure out what kind it is.

      # Set the necessary accessors in the timegap object.
      $timegap->instrument( $nextobs->instrument );
      $timegap->runnr( $nextobs->runnr );
      $timegap->startobs( $curobs->endobs );
      $timegap->endobs( $nextobs->startobs );
      $timegap->telescope( $curobs->telescope );

      # Grab any comments for the timegap object.
      my $odb = new OMP::ObslogDB( DB => new OMP::DBbackend );
      my $comments = $odb->getComment( $timegap );
      $timegap->comments( $comments );

      if( !defined( $timegap->status ) ) {
        if( uc( $curobs->instrument ) eq uc( $nextobs->instrument ) ) {

          # It's either weather or a fault, so set the timegap's status
          # to UNKNOWN.
          $timegap->status( OMP__TIMEGAP_UNKNOWN );
        } else {
          $timegap->status( OMP__TIMEGAP_INSTRUMENT );
        }
      }

      # Push the timegap object onto the array.
      push @newobs, $timegap;

    }
  } # end for loop

  # We need to push the last observation on the array, since
  # it got skipped in the amazing loop structure, but only if there's
  # more than one observation in the array.
  if($#obs > 0) {
    push @newobs, $obs[$#obs];

    # And now, set $self to use the new observations.
    $self->obs( \@newobs );
  }

  return;

}

=item B<summary>

Returns a text-based summary for observations in an observation
group.

  $summary = $grp->summary;

Currently implements the '72col' version of the C<OMP::Info::Obs::summary>
method.

=cut

sub summary {
  my $self = shift;

  if(wantarray) {
    my @summary;
    foreach my $obs ($self->obs) {
      my @obssum = $obs->summary( '72col' );
      push @summary, @obssum;
    }
    return @summary;
  } else {
    my $summary;
    foreach my $obs ($self->obs) {
      $summary .= $obs->summary( '72col' );
    }
    return $summary;
  }
}

=back

=head1 SEE ALSO

For related classes see C<OMP::ArchiveDB> and C<OMP::ObslogDB>.

For information on time gaps see C<OMP::Info::Obs::TimeGap>.

=head1 AUTHORS

Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>,
Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
