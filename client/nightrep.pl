#!/local/perl/bin/perl -X

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

=item B<-cache>

=item B<-no-cache>

Ignore any observations cache files related to given UT dates.
Default is to query cache files.

=item B<-dump>

Print mail to standard out instead of actually sending it.

=item B<-ut> YYYYMMDD | YYYY-MM-DD

Override the UT date used for the report. By default the current date
is used. The UT can be specified in either YYYY-MM-DD or YYYYMMDD format.
If the supplied date is not parseable, the current date will be used.

=item B<-tel> jcmt | ukirt

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

use Getopt::Long qw[ :config gnu_compat no_ignore_case require_order ];
use Pod::Usage;

use Tk;
use Tk::Toplevel;

# Locate the OMP software through guess work
use FindBin;
use lib "$FindBin::RealBin/../lib";

# OMP Classes
use OMP::Error qw/ :try /;
use OMP::DateTools;
use OMP::General;
use OMP::NightRep;

our $VERSION = '2.000';

use vars qw/ $DEBUG /;
$DEBUG = 0;

# Options
my $use_cache = 1;
my ($help, $man, $version, $dump, $tel, $ut );
GetOptions( "help"    => \$help,
            "man"     => \$man,
            "version" => \$version,
            'dump'    => \$dump,
            "ut=s"    => \$ut,
            "tel=s"   => \$tel,
            'cache!'  => \$use_cache
          )
          or pod2usage(1) ;

pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

if ($version) {
  print "nightrep - End of night reporting tool\n";
  print "Version: ", $VERSION, "\n";
  exit;
}

# Modify only the non-default behaviour.
unless ( $use_cache ) {

  require OMP::ArchiveDB;
  OMP::ArchiveDB::skip_cache_query();
}

# Now we can start
# Create a base Tk system that can be used by nightrep
# Multiple MainWindows seemingly lead to core dumps
my $MW = new MainWindow();
$MW->withdraw;

# First thing we need to do is determine the telescope and
# the UT date
$ut = OMP::DateTools->determine_utdate( $ut )->ymd;

# Telescope
my $telescope;
if(defined($tel)) {
  $telescope = uc($tel);
} else {
  my $w = $MW->Toplevel;
  $w->withdraw;
  $telescope = OMP::General->determine_tel( $w );
  $w->destroy;
  die "Unable to determine telescope. Exiting.\n" unless defined $telescope;
}

# Night report
my $NR = new OMP::NightRep( date => $ut, telescope => $telescope);

if ($dump) {
    print scalar $NR->astext();
    exit 0;
}

# Now put up a button bar
my $TL = $MW->Toplevel;
my $TopButtons = $TL->Frame()->pack(-side => 'top');
top_button_bar( $TopButtons );

# Now scan the project database and put up the project
# entries
my $Projects = $TL->Frame()->pack(-side => 'top');
project_window( $Projects, $NR );

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
  my $nr = shift;

  # Get the telescope for efficiency
  my $tel = $nr->telescope;

  # Get the project statistics
  my ($warnings,%times) = generate_project_info($nr);

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
    next if $proj eq $tel . "OTHER";
    next if $proj eq $tel . "FAULT";
    add_project( $f, 1, $proj, $times{$proj}, \$final{$proj}, $sums);
  }

  # Now put up the WEATHER, UNKNOWN
  my %strings = ( WEATHER => "Time lost to weather",
                  OTHER => 'Other time',
                );
  for my $label ( qw/WEATHER OTHER/ ) {
    my $proj = $tel . $label;
    my $times = (exists $times{$proj} ? $times{$proj} : {});
    add_project( $f, 1, $strings{$label}, $times, \$final{$proj},
               $sums);
  }

  # Fault time is not editable
  add_project($f, 0, "Time lost to Faults", {}, \$final{$tel."FAULTS"});

  # Calculate the time lost
  $final{$tel."FAULTS"} = sprintf("%.2f",$nr->timelost->hours);

  # Widget with the total
  add_project($f, 0,"Total time", {}, \$total_time);


  # And finally extended time if we determined that we had extended
  # time (difficult to imagine extended time if we have no data
  # taken in extended time)
  my $exttime = (exists $times{$tel."EXTENDED"} ? $times{$tel."EXTENDED"}
                 : {});
  add_project( $f, 1,"Extended time", $exttime,
               \$final{$tel."EXTENDED"},$sums);

  # And force a summation
  $sums->();

  # Presumably there has to be a button for "CONFIRM" and "CONFIRM AND MAIL"
  my $bf = $w->Frame()->pack(-side => 'top');
  $bf->Button(-text => "CONFIRM",
              -command => sub { &confirm_totals($nr,%final);
                                &confirm_popup($w);
                                &redraw_main_window($w);
                              }
             )->pack(-side =>'right');
  $bf->Button(-text => "CONFIRM and MAIL",
              -command => sub {&confirm_totals($nr,%final);
                               &confirm_popup($w);
                               &redraw_main_window($w);
                               $nr->mail_report;
                             }
             )->pack(-side =>'right');
  $bf->Button(-text => "ADD PROJECT",
              -command => sub {
                &request_extra_project( $f, \%final, $sums);
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

    # Format for displaying the hours
    my $hfmt = "%.2f";

    # Label
    $w->Label( -text => $proj.":" )->grid(-row=>$Row, -column=>0,
                                          -sticky => 'e');

    # Decide on the default value
    # Choose DATA over DB unless DB is confirmed.
    if (exists $times->{DB} && $times->{DB}->confirmed) {
      # Confirmed overrides data headers
      $$varref = sprintf($hfmt,
                         _round_to_ohfive($times->{DB}->timespent->hours));
    } elsif (exists $times->{DATA}) {
      $$varref = sprintf($hfmt,
                         _round_to_ohfive($times->{DATA}->timespent->hours));
    } elsif (exists $times->{DB}) {
      $$varref = sprintf($hfmt,
                         _round_to_ohfive($times->{DB}->timespent->hours));
    } else {
      # Empty
      $$varref = '';
    }

    # Entry widget if editable
    if ($editable) {
      # Create the entry widget
      my $ent = $w->Entry( -width => 10, -textvariable => $varref
                         )->grid(-row=>$Row,
                                 -column => 1);

      # Bind "leave" and "enter" to update the total
      if (defined $cb) {
        $ent->bind("<Leave>",$cb);
        $ent->bind("<Return>",$cb);
      }
    } else {
      $w->Label( -textvariable => $varref)->grid(-row=>$Row, -column=>1);
    }

    # Notes about the data source
    if (exists $times->{DB}) {
      my $status = "ESTIMATED";
      if ($times->{DB}->confirmed) {
        $status = "CONFIRMED";
      }
      $w->Label(-text => $status)->grid(-row=>$Row, -column=>2);

      # Now also add the MSB estimate if it is an estimate
      # Note that we put it after the DATA estimate
      if (!$times->{DB}->confirmed) {
        my $hrs = sprintf($hfmt,
                          _round_to_ohfive($times->{DB}->timespent->hours));
        $w->Label(-text => "$hrs hrs from MSB acceptance")->grid(-row=>$Row,
                                                                 -column=>4);
      }

    } elsif (exists $times->{DATA} && !$times->{DATA}->confirmed) {
            $w->Label(-text => "ESTIMATED")->grid(-row=>$Row, -column=>2);
    }

    if (exists $times->{DATA}) {
      my $hrs = sprintf($hfmt,
                        _round_to_ohfive($times->{DATA}->timespent->hours));
      $w->Label(-text => "$hrs hrs from data headers")->grid(-row=>$Row,
                                                             -column=>3);
    }

  }
}

# Round to nearest 0.05
# Accepts number, returns number with the decimal part rounded to 0.05

sub _round_to_ohfive {
  my $num = shift;

  my $frac = 100 * ($num - int($num));
  my $byfive = $frac / 5;

  $frac = 5 * int( $byfive + 0.5 );

  return int($num) + ($frac / 100);

}

# Retrieve project statistics as a hash
# The keys are projects and for each project there is a hash
# containing keys "DATA" and "DB" indicating whether the information
# comes from the data headers or the database.

# Question: Should this query the headers if the times from TimeAcctDB
# are confirmed values??

sub generate_project_info {
  my $nr = shift;

  # Kluge for testing outside the DB system
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

  # Ask for accounting information
  my %accounting = $nr->accounting;

  my $warnings;
  if (exists $accounting{ $OMP::NightRep::WARNKEY} ) {
    $warnings = $accounting{ $OMP::NightRep::WARNKEY };
    delete $accounting{ $OMP::NightRep::WARNKEY };
  } else {
    $warnings = [];
  }

  return ($warnings, %accounting);

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
  my $nr = shift;
  my %totals = @_;

  # Create a date object
  my $date = $nr->date;

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

  # and update the night report
  $nr->db_accounts( new OMP::TimeAcctGroup(accounts => \@acct) );

}

# Simple routine to remove the main frame and repopuplate it
sub redraw_main_window {
  my $w = shift;

  # TBD

}

# Sometimes some project was observed that did not result in
# data files. Must be able to add extras
sub request_extra_project {
  my ($w, $finalRef, $sums ) = @_;

  # First request it
  require Tk::DialogBox;

  my $d = $w->DialogBox( -title => "New Project",
                         -buttons => ["Accept","Cancel"]);
  my $proj;
  $d->add("Entry", -width => 10, -textvariable => \$proj)->pack(-side=>'top');

  # Wait for action
  my $but = $d->Show;

  # Cancel if we have changed our mind
  return if $but ne "Accept";

  # Now need to verify the project - also check to see whether it is disabled
  if (OMP::ProjServer->verifyProject($proj)) {
    # Yay
    # Popup information on the project
    my $p = OMP::ProjServer->projectDetailsNoAuth($proj, "object");
    if ($p->state) {
      my $dialog = $w->DialogBox(-title => "Project: $proj",
                                 -buttons => ["Accept","Cancel"]);

      # All information
      $dialog->add("Label", -text => "Title: ". $p->title
                  )->pack(-side=>'top');
      $dialog->add("Label", -text => "PI: ". $p->pi
                  )->pack(-side=>'top');

      $but = $dialog->Show;
      # Cancel if we have changed our mind
      return if $but ne "Accept";

      # Add information to the table
      $finalRef->{$proj} += 0;
      add_project($w, 1, $proj, {}, \$finalRef->{$proj}, $sums);
    } else {
      require Tk::Dialog;
      my $dialog = $w->Dialog( -text => "This project exists but is disabled",
                               -title => "Selected project unavailable",
                               -buttons => ["OK"],
                               -bitmap => 'error',
                             );
      $dialog->Show;
    }
  } else {
    # Not yay
    require Tk::Dialog;
    my $dialog = $w->Dialog( -text => "This project does not exist.",
                             -title => "Error verifying project",
                             -buttons => ["OK"],
                             -bitmap => 'error',
                           );

    $dialog->Show;
  }

}


=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002-2005 Particle Physics and Astronomy Research Council.

Copyright (C) 2105 East Asian Observatory.

All Rights Reserved.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful,but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 59 Temple
Place,Suite 330, Boston, MA  02111-1307, USA

=cut
