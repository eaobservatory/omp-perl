#!/local/perl/bin/perl

=head1 NAME

getobs - Retrieve an observation FITS header from database

=head1 SYNOPSIS

  gethead -ut 20110912 -runnr 42
  gethead -ut 20110912 -runnr 42 -inst SCUBA-2
  gethead --obsid=scuba2_00052_20110912T165816

=head1 DESCRIPTION

Given a UT date and run number along with optional instrument
(to avoid ambiguity) retrieve the shared observation metadata
from the database and write it to standard output in FITS
header format. Use --obsid to avoid any possibility of
ambiguity.

If more than one observation match the first (for some
definition of first) is retrieved.

UKIRT is not supported (yet).

=head1 OPTIONS

=item B<-obsid>

Observation unique identifier. Used in preference to all other
options.

=item B<-ut>

The YYYYMMDD UT date of the observation. Requires use of --runnr.

=item B<-runnr>

The observation run number. Requiers -ut.

=item B<-inst>

The instrument name. To be used with -ut and -runnr if there is
some ambiguity (ie both ACSIS and SCUBA-2 wrote observation 5).

=item B<-version>

Report the version number.

=item B<-help>

A help message.

=item B<-man>

This manual page.

=back

=cut

use strict;
use warnings;

use JAC::Setup qw/ omp sybase /;
use Getopt::Long;
use Pod::Usage;

use OMP::ArchiveDB;



my ($ut, $inst, $runnr, $obsid, $help, $version, $man);
my $status = GetOptions("help" => \$help,
                        "man" => \$man,
                        "version" => \$version,
                        "ut=i" => \$ut,
                        "instrument=s" => \$inst,
                        "runnr=i" => \$runnr,
                        "obsid=s" => \$obsid,
                       );

pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

if ($version) {
  print "gethead - Get header of an observation from the database\n";
  exit;
}

my %args = ( telescope => "JCMT" );
if (defined $obsid) {
  $args{obsid} = $obsid;
} elsif (defined $ut && defined $runnr) {
  $args{runnr} = $runnr;
  $args{ut} = $ut;
  $args{instrument} = $inst
    if defined $inst;
} else {
  die "Need an obsid or ut with runnr";
}

my $arcdb = OMP::ArchiveDB->new();
my $obs= $arcdb->getObs( %args );

if ($obs) {
  my $fits = $obs->fits;
  print join( "\n", sort $fits->cards ),"\n";
}

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2011 Particle Physics and Astronomy Research Council.
All Rights Reserved.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 3 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful,but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 59 Temple
Place,Suite 330, Boston, MA  02111-1307, USA

=cut
