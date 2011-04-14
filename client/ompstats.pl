#!/local/perl/bin/perl -w

=head1 NAME

ompstats - Generate OMP statistics

=head1 SYNOPSIS

  ompstats -tel jcmt -sem 05A

=head1 DESCRIPTION

Plot OMP project completion statistics for a given semester and
telescope or range of semesters.

=head1 OPTIONS

=over 4

=item B<-tel>

Telescope name.

=item B<-sem>

Semester name, or a space-separated list of contiguous semesters.

=item B<-verbose>

Be verbose.

=item B<-help>

A help message.

=item B<-man>

This manual page.

=back

=cut


BEGIN {
  # command line tools probably do not want full logging enabled
  # unless they are asking for it
  $ENV{OMP_LOG_LEVEL} = 'IMPORTANT'
    unless exists $ENV{OMP_LOG_LEVEL};
  $ENV{OMP_CFG_DIR} = "/jac_sw/omp/msbserver/cfg";
}

use strict;

# Locate the OMP software through guess work
use FindBin;
use lib "$FindBin::RealBin/..";

use Pod::Usage;
use Getopt::Long;
use Graphics::PLplot qw(:all);

use OMP::DBbackend;
use OMP::General;
use OMP::NightRep;

my $tel;
my @sems;
my $verbose;
my $help;
my $man;
my $result = GetOptions("tel=s" => \$tel,
			"sem=s" => \@sems,
			"verbose" => \$verbose,
		        "h|help" => \$help,
			"man" => \$man,
		       );

pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

die ("Please specify -tel and -sem\n")
  unless (defined $tel and defined $sems[0]);

# Get semester boundaries
my ($startdate, $enddate) = OMP::DateTools->semester_boundary(semester=>\@sems, tel=>$tel);

# Create the night report
my $nr = new OMP::NightRep(date => $startdate->ymd,
			   date_end => $enddate->ymd,
			   telescope => $tel,);

print "Retrieving time accounts...\n"
  if ($verbose);
my $acct = $nr->db_accounts;

print "Retrieving faults...\n"
  if ($verbose);
my @fault_acct = $nr->faults->timeacct;
$acct->pushacct(@fault_acct);

print "Generating statistics...\n"
  if ($verbose);
my %coords = $acct->completion_stats();

for my $stat (keys %coords) {
  next if $stat =~ /^__/;
  my $file = "nr${stat}.dat";
  print "Writing data to $file\n" if $verbose;
  open (my $DATA, ">", $file)
    or die "Could not create dat file '$file': $!\n";
  print $DATA join("\n", map {$_->[0] ." ". $_->[1]} @{$coords{$stat}}) . "\n";
  close($DATA) or die "Error closing file '$file': $!\n";

  # Print name of dat file to STDERR
  print STDERR "Created file $file\n";
}

# Draw plot
print "Drawing plot...\n"
  if ($verbose);

plsdev( "xwin" );
plinit();
plfont(2);

plcol0(1);
plenv( $coords{science}->[0]->[0], $coords{science}->[-1]->[0], 0, 100, 0, 1);
pllab ("", "", "Completion Statistics");

my $color = 1;
my $texty = 95;
for my $stat (keys %coords) {
  next if $stat =~ /^__/;
  my (@x, @y);
  @x = map {$_->[0]} @{$coords{$stat}};
  @y = map {$_->[1]} @{$coords{$stat}};
  plcol0(++$color);
  plline(\@x, \@y);
  plptex($x[0] + 3, $texty, 0, 0, 0, "$stat");
  $texty -= 5;
}

plend();

print "Done.\n"
  if ($verbose);

=head1 AUTHOR

Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2004-2005 Particle Physics and Astronomy Research Council.
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
