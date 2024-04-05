#!/local/perl/bin/perl

=head1 NAME

maillist - Generate a list of PI and Co-I email addresses

=head1 SYNOPSIS

    maillist -country UK [-telescope TEL]

    maillist -project M99XY000

=head1 DESCRIPTION

This program generates a list of OMP project PI and Co-I email
addresses and sends the list to standard output.

=head1 OPTIONS

The following options are supported:

=over 4

=item B<-country>

Specify the country queue.

=item B<-telescope>

Specify the telescope.

=item B<-project>

Specify an individual project identifier.  (In this mode the -country
and -project options are ignored.)

=item B<-help>

A help message.

=item B<-man>

This manual page.

=item B<-version>

Report the version number.

=back

=cut

use warnings;
use strict;

use Getopt::Long;
use Pod::Usage;
use Term::ReadLine;

# Locate the OMP software through guess work
use FindBin;
use lib "$FindBin::RealBin/../lib";

use OMP::DB::Backend;
use OMP::ProjDB;
use OMP::ProjQuery;

our $VERSION = '2.000';

$| = 1; # Make unbuffered

# Options
my ($country, $telescope, $single_project, $help, $man, $version);
my $status = GetOptions(
    "country=s" => \$country,
    "telescope=s" => \$telescope,
    'project=s' => \$single_project,
    "help" => \$help,
    "man" => \$man,
    "version" => \$version,
);

pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

if ($version) {
    print "maillist - Generate a list of PI and Co-I email addresses\n";
    print "Version: ", $VERSION, "\n";
    exit;
}

my %queryhash;
if (defined $single_project) {
    $queryhash{'projectid'} = $single_project;
}
elsif (defined $country) {
    $queryhash{'country'} = $country;
    $queryhash{'telescope'} = $telescope
        if $telescope;
}
else {
    # Die if missing certain arguments
    die "The country or project argument must be specified\n";
}

# Get projects
my $db = OMP::DB::Backend->new;
my $projdb = OMP::ProjDB->new(DB => $db);
my $projquery = OMP::ProjQuery->new(HASH => \%queryhash);
my @projects = $projdb->listProjects($projquery);
my %email_users;

for my $project (@projects) {
    my @pis = $project->pi;
    my @cois = $project->coi;

    for my $user (@pis, @cois) {
        $email_users{$user->userid} = $user
            if $user->email;
    }
}

# Print sorted
for my $userid (sort keys %email_users) {
    print $email_users{$userid}->as_email_hdr . "\n";
}

__END__

=head1 AUTHOR

Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2005 Particle Physics and Astronomy Research Council.
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
