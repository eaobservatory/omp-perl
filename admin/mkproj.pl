#!/usr/local/bin/perl

=head1 NAME

mkproj - Populate project database with initial details

=head1 SYNOPSIS

  mkproj defines.ini
  mkproj -force defines.ini

=head1 DESCRIPTION

This program reads in a file containing the project information,
and adds the details to the OMP database. By default projects
that already exist in the database are ignored although this
behaviour can be over-ridden. See L<"FORMAT"> for details on the
file format.

=head1 ARGUMENTS

The following arguments are allowed:

=over 4

=item B<defines>

The project definitions file name. See L<"FORMAT"> for details on the
file format.

=back

=head1 OPTIONS

The following options are supported:

=over 4

=item B<-force>

By default projects that already exist in the database are not
overwritten. With the C<-force> option project details in the file
always override those already in the database. Use this option
with care.

=item B<-version>

Report the version number.

=item B<-help>

A help message.

=item B<-man>

This manual page.

=back

=cut

# Uses the infrastructure classes so each project is inserted
# independently rather than as a single transaction

use warnings;
use strict;

use OMP::Error qw/ :try /;
use Config::IniFiles;
use OMP::ProjServer;
use OMP::SiteQuality;
use Pod::Usage;
use Getopt::Long;

# Options
my ($help, $man, $version,$force);
my $status = GetOptions("help" => \$help,
                        "man" => \$man,
                        "version" => \$version,
			"force" => \$force,
                       );

pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

if ($version) {
  my $id = '$Id$ ';
  print "mkproj - upload project details from file\n";
  print " CVS revision: $id\n";
  exit;
}

# Read the file
my $file = shift(@ARGV);
my %alloc;
tie %alloc, 'Config::IniFiles', ( -file => $file );

# Get the defaults (if specified)
my %defaults;
%defaults = %{ $alloc{info} }
  if $alloc{info};

# Get the support information
my %support;
%support = %{ $alloc{support} }
  if $alloc{support};

# Loop over each project and add it in
for my $proj (keys %alloc) {
  next if $proj eq 'support';
  next if $proj eq 'info';

  # Copy the data from the file and merge with the defaults
  my %details = ( %defaults, %{ $alloc{$proj} });

  # Upper case country for lookup table
  # and split on comma in case we have more than one
  $details{country} = [split /,/,uc($details{country}) ];

  # TAG priority
  my @tag = split /,/, $details{tagpriority};

  die "Number of TAG priorities is neither 1 nor number of countries [$proj]"
    unless ($#tag == 0 || $#tag == $#{$details{country}});

  $details{tagpriority} = \@tag if scalar(@tag) > 1;

  # TAG adjustment
  my @tagadj;
  if ($details{tagadjustment}) {
    @tagadj = split /,/, $details{tagadjustment};
    $details{tagadjustment} = \@tagadj if scalar(@tagadj) > 1;
  }

  # Deal with support issues
  # but do not overrride one if it is already set
  if (!defined $details{support}) {
    if (exists $support{$details{country}->[0]}) {
      $details{support} = $support{$details{country}->[0]};
    } else {
      die "Can not find support for country ".
	$details{country}->[0]."\n";
    }
  }

  die "Must supply a telescope!!!" unless exists $details{telescope};

  # Now weather bands
  my ($taumin, $taumax) = OMP::SiteQuality::default_range('TAU');
  if (exists $details{taurange}) {
    ($taumin, $taumax) = split(/,/, $details{taurange});
  } elsif (exists $details{band}) {
    # Get the tau range from the weather bands if it exists
    my @bands = split( /,/, $details{band});
    my $taurange = OMP::SiteQuality::get_tauband_range($details{telescope},
						       @bands);
    die "Error determining tau range from band '$details{band}' !"
      unless defined $taurange;

    ($taumin, $taumax) = $taurange->minmax;

  }

  # And seeing
  my ($seemin, $seemax) = OMP::SiteQuality::default_range('SEEING');
  if (exists $details{seeing}) {
    ($seemin, $seemax) = split(/,/, $details{seeing});
  }

  # cloud
  my ($cloudmin, $cloudmax) = OMP::SiteQuality::default_range('CLOUD');
  if (exists $details{cloud}) {
    # if we have no comma, assume this is a cloudmax and "upgrade" it
    if ($details{cloud} !~ /,/) {
      my $r = OMP::SiteQuality::upgrade_cloud( $details{cloud} );
      ($cloudmin, $cloudmax) = $r->minmax;
    } else {
      ($cloudmin, $cloudmax) = split(/,/, $details{cloud});
    }
  }

  # And sky brightness
  my ($skymin, $skymax) = OMP::SiteQuality::default_range('SKY');
  if (exists $details{sky}) {
    ($skymin, $skymax) = split(/,/, $details{sky});
  }

  # Now convert the allocation to seconds instead of hours
  die "[project $proj] Allocation is mandatory!" unless $details{allocation};
  $details{allocation} *= 3600;

  print "Adding [$proj]";

  # Now add the project
  try {
    OMP::ProjServer->addProject('***REMOVED***', $force,
				$proj,  # project id
				uc($details{pi}),
				uc($details{coi}),
				uc($details{support}),
				$details{title},
				$details{tagpriority},
				$details{country},
				$details{tagadjustment},
				$details{semester},
				"xxxxxx", # default password
				$details{allocation},
				$details{telescope},
				$taumin, $taumax,
				$seemin,$seemax,
				$cloudmin, $cloudmax,
				$skymin, $skymax,
			       );

  } catch OMP::Error::ProjectExists with {
    print " - but the project already exists. Skipping.";

  };
  print "\n";

}


=head1 FORMAT

The input project definitions file is in the C<.ini> file format
with the following layout. A header C<[info]> and C<[support]>
provide general defaults that should apply to all projects
in the file, with support indexed by country:


 [info]
 semester=02B
 telescope=JCMT

 [support]
 UK=IMC
 CN=GMS
 INT=GMS
 UH=GMS
 NL=RPT

Individual projects are specified in the following sections, indexed
by project ID. C<pi>, C<coi> and C<support> must be valid OMP User IDs
(comma-separated).

 [m01bu32]
 tagpriority=1
 country=UK
 pi=HOLLANDW
 coi=GREAVESJ,ZUCKERMANB
 title=The Vega phenomenom around nearby stars
 allocation=24
 band=1

 [m01bu44]
 tagpriority=2
 country=UK
 pi=RICHERJ
 coi=FULLERG,HATCHELLJ
 title=Completion of the SCUBA survey
 allocation=28
 band=1

Allocations are in hours and "band" is the weather band. C<taurange>
can be used directly (as a comma delimited range) if it is known.

Multiple countries can be specified (comma-separated). If there is
more than one TAG priority (comma-separated) then there must
be one priority for every country. SUPPORT lookups only used the
first country. The first country is the primary key.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2005 Particle Physics and Astronomy Research Council.
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



