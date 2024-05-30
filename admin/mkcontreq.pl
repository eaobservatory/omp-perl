#!/local/perl/bin/perl

=head1 NAME

mkcontreq - Add continuation requests to the OMP database

=head1 SYNOPSIS

    mkcontreq continuations.ini

=head1 DESCRIPTION

Reads a continuation request definition file and adds the details
to the OMP database.

Currently only stores the request in the C<ompprojcont> table to allow
the project to be automatically advanced up to the requested semester.
Other aspects (such as the member list, or the time remaining)
are not (yet) processed.

=head1 OPTIONS

=over 4

=item B<--dry-run>

Do not write to database.

=item B<--no-project-check>

Do not check that projects for continuation exist.

=back

=cut

use strict;
use FindBin;
use constant OMPLIB => "$FindBin::RealBin/../lib";

use lib OMPLIB;

BEGIN {
    $ENV{'OMP_CFG_DIR'} = File::Spec->catdir(OMPLIB, '../cfg')
        unless exists $ENV{'OMP_CFG_DIR'};
}

use Config::IniFiles;
use Getopt::Long;
use Pod::Usage;

use OMP::DB::Backend;
use OMP::DB::Project;
use OMP::General;

my ($help, $dry_run);
my $project_check = 1;
GetOptions(
    'project-check!' => \$project_check,
    'help' => \$help,
    'dry-run' => \$dry_run,
) or pod2usage(-exitstatus => 1, -verbose => 0);

pod2usage(1) if $help;

my $filename = shift;
die "mkcontreq: file does not exist: $filename"
    unless -e $filename;

my $defaultsection = 'info';
my $cfg = Config::IniFiles->new(
    -file => $filename,
    -default => $defaultsection,
);

my $db = OMP::DB::Backend->new;
my $projdb = OMP::DB::Project->new(DB => $db);

foreach my $projectid ($cfg->Sections) {
    next if $projectid eq $defaultsection;

    my $semester = $cfg->val($projectid, 'semester');
    my $requestid = $cfg->val($projectid, 'continuation');

    if ($project_check) {
        $projdb->projectid($projectid);
        unless ($projdb->verifyProject) {
            die "Project $projectid does not exist";
        }
    }

    print "Adding continuation of $projectid: $semester via request $requestid\n";

    $projdb->add_project_continuation($projectid, $semester, $requestid)
        unless $dry_run;
}

__END__

=head1 COPYRIGHT

Copyright (C) 2024 East Asian Observatory
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

=cut
