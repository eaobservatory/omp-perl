#!/local/bin/perl

=head1 NAME

nightrep - Review and send end of night observing report

=head1 SYNOPSIS

  nightrep 
  nightrep -ut 2002-12-10
  nightrep -tel jcmt
  nightrep -ut 2002-10-05 -tel ukirt
  nightrep --help

=head1 DESCRIPTION

This program allows you to review, edit and submit an end of night
report. This mainly involves declaring who the observers and TSSs
were, and confirming the amount of time spent on each project and
time lost to weather.

Note that this program is for a single night of observing and does not
treat split nights independently.

=head1 OPTIONS

The following options are supported:

=over 4

=item B<-ut>

Override the UT date used for the report. By default the current date
is used.

=item B<-tel>

Specify the telescope to use for the report. If the telescope can
be determined from the domain name it will be used automatically.
If the telescope can not be determined from the domain and this
option has not been specified a popup window will request the
telescope from the supplied list (assume the list contains more
than one telescope).

=item B<-version>

Report the version number.

=item B<-help>

A help message.

=item B<-man>

This manual page.

=back

=cut

use 5.006;
use strict;
use warnings;

use Getopt::Long;
use Pod::Usage;

use Tk;

# Locate the OMP software through guess work
use FindBin;
use lib "$FindBin::RealBin/..";

# OMP Classes
use OMP::Error qw/ :try /;
use OMP::General;
use OMP::TimeAcctDB;
use OMP::Info::ObsGroup;
use OMP::ProjServer;
use OMP::FaultDB;
use OMP::FaultStats;

use vars qw/ $DEBUG /;
$DEBUG = 0;

# Options
my ($help, $man, $version, $tel, $ut);
my $status = GetOptions("help" => \$help,
                        "man" => \$man,
                        "version" => \$version,
			"ut=s" => \$ut,
			"tel=s" => \$tel,
                       );

pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

if ($version) {
  my $id = '$Id$ ';
  print "nightrep - End of night reporting tool\n";
  print " CVS revision: $id\n";
  exit;
}

# First thing we need to do is determine the telescope and
# the UT date
$ut = OMP::General->determine_utdate( $ut )->ymd;

# Telescope
my $telescope;
if(defined($tel)) {
  $telescope = uc($tel);
} else {
  my $w = new MainWindow;
  $w->withdraw;
  $telescope = OMP::General->determine_tel( $w );
  $w->destroy;
  die "Unable to determine telescope. Exiting.\n" unless defined $telescope;
}

# Now we can start
my $MW = new MainWindow();

# Now put up a button bar
my $TopButtons = $MW->Frame()->pack(-side => 'top');
top_button_bar( $TopButtons );

# Now scan the project database and put up the project
# entries
my $Projects = $MW->Frame()->pack(-side => 'top');
project_window( $Projects, $telescope, $ut );

# And time for the event loop
MainLoop();



# Button bar
sub top_button_bar {
  my $w = shift;

  $w->Button( -text => 'Exit', -command => sub { exit; }
	    )->pack(-side => 'left');

}

# Project window: Needs a frame and a telescope and a ut
sub project_window {
  my $w = shift;
  my $tel = shift;
  my $ut = shift;

  # Get the project statistics
  my ($warnings,%times) = generate_project_info($tel, $ut);

  # If we have warnings insert them
  # Create lots of messages
  my $wf = $w->Frame(-relief => 'groove',
		     -borderwidth => 2)->pack(-side=>'top',-fill=>'x');
  if (@$warnings) {
    $wf->Label(-text => 'Warnings from header analysis')->pack(-side => 'top',
							      -fill => 'x');
    my $i = 0;
    for (@$warnings) {
      chomp($_);
      $wf->Label(-text => "#$i".": $_",
		-relief=> 'sunken')->pack(-side => 'top');
      $i++;
    }
  }

  # We want to use the Gridder for packing the components
  my $f = $w->Frame(-border => 3)->pack(-side => 'top');

  # This hash contains the times (in hours) for each
  # entry
  my %final;
  my $total_time;

  # This callback sums up all the times
  my $sums = sub {
    $total_time = 0.0;
    for my $proj (keys %final) {
      next if $proj =~ /EXTENDED/;
      if (defined $final{$proj} && $final{$proj} =~ /^(\d+|\d+\.|\d+\.\d+)$/) {
	$total_time += $final{$proj};
      }
    }
  };

  # Go through the array creating the GUI, but skipping
  # keys not directly related
  my %rem;
  for my $proj (keys %times) {
    if ($proj =~ /^$tel/) {
      $rem{$proj}++;
    } else {
      add_project( $f, 1,$proj, $times{$proj}, \$final{$proj}, $sums );
    }
  }

  # Now put up everything else (except EXTENDED which is a special case)
  # and special WEATHER and UNKNOWN which we want to force the order
  for my $proj (keys %rem) {
    next if $proj eq $tel . "EXTENDED";
    next if $proj eq $tel . "WEATHER";
    next if $proj eq $tel . "UNKNOWN";
    next if $proj eq $tel . "FAULT";
    add_project( $f, 1, $proj, $times{$proj}, \$final{$proj}, $sums);
  }

  # Now put up the WEATHER, UNKNOWN
  for my $label ( qw/WEATHER UNKNOWN/ ) {
    my $proj = $tel . $label;
    my $times = (exists $times{$proj} ? $times{$proj} : {});
    add_project( $f, 1,"Time lost to ".lc($label), $times, \$final{$proj},
	       $sums);
  }

  # Fault time is not editable
  add_project($f, 0, "Time lost to Faults", {}, \$final{$tel."FAULTS"});

  # Calculate the time lost
  my $fdb = new OMP::FaultDB( DB => new OMP::DBbackend );
  my @results = $fdb->getFaultsByDate($ut, $tel);
  my $faultstats = new OMP::FaultStats( faults => \@results );
  $final{$tel."FAULTS"} = sprintf("%.1f",$faultstats->timelost->hours);

  # And finally extended time if we determined that we had extended
  # time (difficult to imagine extended time if we have no data 
  # taken in extended time)
  my $exttime = (exists $times{$tel."EXTENDED"} ? $times{$tel."EXTENDED"}
		 : {});
  add_project( $f, 1,"Extended time", $exttime, 
	       \$final{$tel."EXTENDED"},$sums);


  # Widget with the total
  add_project($f, 0,"Total time", {}, \$total_time);

  # And force a summation
  $sums->();

  # Presumably there has to be a button for "CONFIRM" and "CONFIRM AND MAIL"
  my $bf = $w->Frame()->pack(-side => 'top');
  $bf->Button(-text => "CONFIRM",
	      -command => sub { &confirm_totals(%final);
				&confirm_popup($w);
				&redraw_main_window($w);
			      }
	     )->pack(-side =>'right');
  $bf->Button(-text => "CONFIRM and MAIL",
	      -command => sub {&confirm_totals(%final);
			       &confirm_popup($w);
			       &redraw_main_window($w);
			     }
	     )->pack(-side =>'right');

  # Something to view the faults, the shift log?

}

# Create the gui entries for each project
# Must use the gridder in $w, and $w must be an empty frame
# first time we are called.
# Keep internal count on row position
{
  my $Row;

  sub add_project {
    my $w = shift;
    my $editable = shift;
    my $proj = shift;
    my $times = shift;
    my $varref = shift;
    my $cb = shift;

    # Increment the row counter
    $Row++;

    # Label
    $w->Label( -text => $proj.":" )->grid(-row=>$Row, -col=>0,
					  -sticky => 'e');

    # Decide on the default value
    # Choose DATA over DB unless DB is confirmed.
    if (exists $times->{DB} && $times->{DB}->confirmed) {
      # Confirmed overrides data headers
      $$varref = sprintf("%.1f",$times->{DB}->timespent->hours);
    } elsif (exists $times->{DATA}) {
      $$varref = sprintf("%.1f",$times->{DATA}->timespent->hours);
    } elsif (exists $times->{DB}) {
      $$varref = sprintf("%.1f",$times->{DB}->timespent->hours);
    } else {
      # Empty
      $$varref = '';
    }

    # Entry widget if editable
    if ($editable) {
      # Create the entry widget
      my $ent = $w->Entry( -width => 10, -textvariable => $varref
			 )->grid(-row=>$Row,
				 -col => 1);

      # Bind "leave" and "enter" to update the total
      if (defined $cb) {
	$ent->bind("<Leave>",$cb);
	$ent->bind("<Return>",$cb);
      }
    } else {
      $w->Label( -textvariable => $varref)->grid(-row=>$Row, -col=>1);
    }

    # Notes about the data source
    if (exists $times->{DB}) {
      my $status = "ESTIMATED";
      if ($times->{DB}->confirmed) {
	$status = "CONFIRMED";
      }
      $w->Label(-text => $status)->grid(-row=>$Row, -col=>2);

      # Now also add the MSB estimate if it is an estimate
      # Note that we put it after the DATA estimate
      if (!$times->{DB}->confirmed) {
      	my $hrs = sprintf("%.1f", $times->{DB}->timespent->hours);
	$w->Label(-text => "$hrs hrs from MSB acceptance")->grid(-row=>$Row,
								 -col=>4);
      }

    } elsif (exists $times->{DATA} && !$times->{DATA}->confirmed) {
            $w->Label(-text => "ESTIMATED")->grid(-row=>$Row, -col=>2);
    }

    if (exists $times->{DATA}) {
      my $hrs = sprintf("%.1f", $times->{DATA}->timespent->hours);
      $w->Label(-text => "$hrs hrs from data headers")->grid(-row=>$Row,
							     -col=>3);
    }

  }
}

# Retrieve project statistics as a hash
# The keys are projects and for each project there is a hash
# containing keys "DATA" and "DB" indicating whether the information
# comes from the data headers or the database.

# Question: Should this query the headers if the times from TimeAcctDB
# are confirmed values??

sub generate_project_info {
  my $tel = shift;
  my $ut = shift;

  # Kluge
  if ($DEBUG) {
    return (['some calibrations are useless'],
	    m02bu53 => { DB => new OMP::Project::TimeAcct(projectid =>'m02bu53',
							  timespent => new Time::Seconds(3600)),
			 DATA => new OMP::Project::TimeAcct(timespent=> new Time::Seconds(3000)),
		       },
	    m02bu32 => { DB => new OMP::Project::TimeAcct(projectid =>'m02bu32',
							  timespent => new Time::Seconds(7000)),
			 DATA => new OMP::Project::TimeAcct(timespent=> new Time::Seconds(7500)),
		       },
	   );
  }

  # Database connection
  my $db = new OMP::TimeAcctDB( DB => new OMP::DBbackend);

  # Get the time accounting statistics from
  # the TimeAcctDB table
  # We need to also select by telescope here
  my @dbacct = $db->getTimeSpent( utdate => $ut );

  # Select by telescope
  @dbacct = grep { istel($tel, $_->projectid) } @dbacct;

  # Get the time accounting statistics from the data headers
  # Need to catch directory not found
  my ($warnings, @hdacct);
  try {
    my $grp = new OMP::Info::ObsGroup( telescope => $tel,
				     date => $ut,);
    ($warnings, @hdacct) = $grp->projectStats();
  };

  # Form a hash
  my %results;

  # Starting with DB
  for my $acct (@dbacct) {
    $results{$acct->projectid}->{DB} = $acct;
  }

  # Then with headers
  for my $acct (@hdacct) {
    $results{$acct->projectid}->{DATA} = $acct;
  }

  return ($warnings, %results);
}

# Check that we have the right telescope
sub istel {
  my $tel = uc(shift);
  my $projectid = shift;

  if ($projectid =~ /^$tel/i) {
    # True if the project id starts with the telescope string
    return 1;
  } elsif ($tel eq 'JCMT' && ($projectid eq 'WEATHER' || 
			      $projectid eq 'FAULT' || 
			      $projectid eq 'OTHER' || $projectid eq 'SCUBA')) {
    # Kluge for historical data until the tables are changed
    return 1;

  } else {
    # Must query the project database [eek]
    # Requires password
    return 1 if $tel eq OMP::ProjServer->getTelescope( $projectid );
  }
  return 0;
}

# Popup indicating success
sub confirm_popup {
  my $w = shift;

  require Tk::DialogBox;
  my $dbox = $w->DialogBox(-title=> "Times accepted",
			  -buttons => ["OK"]);
  $dbox->add("Label",-text => "Time Confirmed")->pack(-side =>'top');
  $dbox->Show;
}

# Submit the totals to the database
sub confirm_totals {
  my %totals = @_;

  # Create a date object
  my $date = OMP::General->parse_date( $ut );

  # Contact the accounting database
  my $db = new OMP::TimeAcctDB( DB => new OMP::DBbackend );

  # Loop over each project
  my @acct;
  for my $proj (keys %totals) {
    # Skip faults since they come from fault database
    next if $proj =~ /FAULTS/;

    # time spent [assuming we have a number]
    # We should probably distinguish '' from 0.0
    # We also do not really want to set extended to 0 if there
    # was no extended time at all
    my $tot = $totals{$proj};
    $tot = 0.0 unless length($totals{$proj});
    my $timespent = new Time::Seconds($tot * 3600);

    # Create a new object
    my $time = new OMP::Project::TimeAcct( projectid => $proj,
					   timespent => $timespent,
					   date=> $date,
					   confirmed => 1,
					 );

    # Store it in array
    push(@acct, $time);

  }

  # Now store the times
  $db->setTimeSpent( @acct );

}

# Simple routine to remove the main frame and repopuplate it
sub redraw_main_window {
  my $w = shift;

  # TBD

}

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut
