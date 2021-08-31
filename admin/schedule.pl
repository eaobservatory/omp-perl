#!/local/perl/bin/perl -X

=head1 NAME

ompschedule - View telescope observing schedule

=head1 SYNOPSIS

    ompschedule --tel JCMT --semester 21B

=head1 DESCRIPTION

This program displays schedule information from the OMP database.

=head1 OPTIONS

=over 4

=item B<--tel>

Specify the telescope to use.  If the telescope can
be determined from the domain name it will be used automatically.

=item B<--semester>

Specify the semester.  If not specified, the current semester
will be used.

=back

=cut

use warnings;
use strict;

use Getopt::Long;
use Pod::Usage;
use File::Spec;
use FindBin;

BEGIN {
  use constant OMPLIB => "$FindBin::RealBin/../lib";
  use lib OMPLIB;
}

use OMP::General;
use OMP::SchedDB;
use OMP::DateTools;
use OMP::DBbackend;

my ($tel, $semester, $help);
my $status = GetOptions(
    'semester=s' => \$semester,
    'tel=s' => \$tel,
    'help' => \$help,
) or pod2usage(1);

pod2usage(-exitstatus => 0, -verbose => 2) if $help;

if (defined $tel) {
    $tel = uc($tel);
}
else {
    $tel = OMP::General->determine_tel();
    die 'Telescope not specified' unless (defined $tel) and (not ref $tel);
}

unless (defined $semester) {
    $semester = OMP::DateTools->determine_semester(tel => $tel);
}

my ($start, $end) = OMP::DateTools->semester_boundary(
    tel => $tel, semester => $semester);

my $db = new OMP::SchedDB(DB => new OMP::DBbackend());
my $sched = $db->get_schedule(tel => $tel, start => $start, end => $end);

print $sched, "\n";

__END__

=head1 COPYRIGHT

Copyright (C) 2021 East Asian Observatory
All Rights Reserved.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful,but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc.,51 Franklin
Street, Fifth Floor, Boston, MA  02110-1301, USA
