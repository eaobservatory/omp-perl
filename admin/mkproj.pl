#!/usr/local/bin/perl

# Populates project database with initial details

# Input: .ini format text file containing project details
#
#[info]
#semester=02B
#telescope=JCMT
#
#[support]
#UK=IMC
#CN=GMS
#INT=GMS
#UH=GMS
#NL=RPT
#
#[m01bu32]
#tagpriority=1
#country=UK
#pi=HOLLANDW
#coi=GREAVESJ,ZUCKERMANB
#title=The Vega phenomenom around nearby stars
#allocation=24
#band=1
#
#[m01bu44]
#tagpriority=2
#country=UK
#pi=RICHERJ
#coi=FULLERG,HATCHELLJ,QUALTROUGHC,CHANDLERC,LADDN
#title=Completion of the SCUBA survey of star formation Perseus Molecular Cloud
#allocation=28
#band=1

# where the [info] field provides default values for each project, the [support] field can be used to index support id from the country field. Allocations are in hours and "band" is the weather band. taurange can be used directly (comma delimited range) if it is known. coi list uses user IDs and is comma delimited.

# perl mkproj.pl  FILENAME.ini

# Uses the infrastructure classes so each project is inserted
# independently rather than as a single transaction

use warnings;
use strict;

use Config::IniFiles;
use OMP::ProjServer;
use OMP::General;

# Read the file
my $file = shift(@ARGV);
my %alloc;
tie %alloc, 'Config::IniFiles', ( -file => $file );

# Get the defaults
my %defaults = %{ $alloc{info} };

# Get the support information
my %support = %{ $alloc{support} };

# Loop over each project and add it in
for my $proj (keys %alloc) {
  next if $proj eq 'support';
  next if $proj eq 'info';

  # Copy the data from the file and merge with the defaults
  my %details = ( %defaults, %{ $alloc{$proj} });

  # Deal with support issues
  # but do not overrride one if it is already set
  if (!defined $details{support}) {
    if (exists $support{$details{country}}) {
      $details{support} = $support{$details{country}};
    }
  }

  # Now weather bands
  my ($taumin, $taumax) = (0,undef);
  if (exists $details{taurange}) {
    ($taumin, $taumax) = split(/,/, $details{taurange});
  } else {
    # Get the tau range from the weather bands
    my @bands = split( /,/, $details{band});
    my $taurange = OMP::General->get_band_range($details{telescope}, @bands);
    die "Error determining tau range from band $details{band}"
      unless $taurange;

    ($taumin, $taumax) = $taurange->minmax;

  }

  # Now convert the allocation to seconds instead of hours
  die "[project $proj] Allocation is mandatory!" unless $details{allocation};
  $details{allocation} *= 3600;

  print "Adding [$proj]\n";

  # Now add the project
  OMP::ProjServer->addProject('***REMOVED***',
			      $proj,  # project id
			      $details{pi},
			      $details{coi},
			      $details{support},
			      $details{title},
			      $details{tagpriority},
			      $details{country},
			      $details{semester},
			      "xxxxxx", # default password
			      $details{allocation},
			      $details{telescope},
			      $taumin, $taumax,
			     );



}






