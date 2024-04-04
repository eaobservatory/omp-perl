#!/local/perl/bin/perl

=head1 NAME

check_expiry - Update projects with defined expiration dates

=head1 SYNOPSIS

    check_expiry [--dry-run] --tel JCMT|UKIRT

=head1 DESCRIPTION

This program processes projects which have expiration dates
as follows:

=over 4

=item *

Projects past their expiration date are disabled.

=item *

Enabled projects are updated to be in the current semester,
unless they already are.

=back

=cut

use strict;

use DateTime;
use FindBin;
use File::Spec;
use Getopt::Long;
use Pod::Usage;

use constant OMPLIB => "$FindBin::RealBin/../lib";

BEGIN {
    $ENV{'OMP_CFG_DIR'} = File::Spec->catdir(OMPLIB, '../cfg')
        unless exists $ENV{'OMP_CFG_DIR'};
}

use lib OMPLIB;

use OMP::DateTools;
use OMP::DB::Backend;
use OMP::ProjDB;
use OMP::ProjQuery;

my ($tel, $verbose, $dry_run);
GetOptions(
    'tel=s' => \$tel,
    'verbose' => \$verbose,
    'dry-run' => \$dry_run,
) or pod2usage(-exitstatus => 1, -verbose => 0);

die 'Telescope not specified' unless defined $tel;

my $db = OMP::DB::Backend->new;

check_project_expiry();

exit 0;

sub check_project_expiry {
    my $standard_semester = qr/^\d\d[AB]$/a;
    my $dt = DateTime->now(time_zone => 'UTC');
    my $semester = OMP::DateTools->determine_semester(date => $dt, tel => $tel);

    my $pdb = OMP::ProjDB->new(DB => $db);

    # Check for expired projects.
    foreach my $project ($pdb->listProjects(OMP::ProjQuery->new(XML => '<ProjQuery>' .
                '<telescope>' . $tel . '</telescope>'.
                '<state>1</state>' .
                '<expirydate><max>' . $dt->strftime('%F %T') . '</max></expirydate>' .
            '</ProjQuery>'))) {
        my $projectid = $project->projectid();

        print "Expired: $projectid\n";

        disable_project($pdb, $project) unless $dry_run;
    }


    # Check for projects to advance to the current semester.
    foreach my $project ($pdb->listProjects(OMP::ProjQuery->new(XML => '<ProjQuery>' .
            '<telescope>' . $tel . '</telescope>'.
            '<not><semester>' . $semester . '</semester></not>'.
            '<state>1</state>' .
            '<expirydate><null>0</null></expirydate>' .
        '</ProjQuery>'))) {
        my $projectid = $project->projectid();

        if ($project->semester() !~ $standard_semester) {
            print "Not advancing semester: $projectid (non-standard semester)\n"
                if $verbose;
        }
        else {
            print "Advancing semester: $projectid\n";

            advance_project($pdb, $project, $semester) unless $dry_run;
        }
    }
}

sub disable_project {
    my ($pdb, $project) = @_;

    $project->state(0);

    $pdb->_update_project_row($project);
}

sub advance_project {
    my ($pdb, $project, $semester) = @_;

    $project->semester($semester);

    $pdb->_update_project_row($project);
}

__END__

=head1 COPYRIGHT

Copyright (C) 2019 East Asian Observatory
All Rights Reserved.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful,but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc.,51 Franklin
Street, Fifth Floor, Boston, MA  02110-1301, USA

=cut
