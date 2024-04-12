package OMP::Util::Project;

=head1 NAME

OMP::Util::Project - Project information utility class

=head1 DESCRIPTION

This class provides a utility method for project creation.

=cut

use strict;
use warnings;
use Carp;

# OMP dependencies
use OMP::DateTools;
use OMP::ProjDB;
use OMP::DB::ProjAffiliation;
use OMP::SiteQuality;
use OMP::UserDB;
use OMP::Project;
use OMP::Error qw/:try/;

our $VERSION = '2.000';

=head1 METHODS

=over 4

=item B<addProject>

Add details of a project to the database.

    OMP::Util::Project->addProject(
        $database,
        $force,
        $projectid, $pi, $coi, $support,
        $title, $tagpriority, $country, $tagadj,
        $semester, $allocated, $telescope,
        $taumin, $taumax,
        $seemin, $seemax,
        $cloudmin, $cloudmax,
        $skymin, $skymax,
        $state,
        $pi_affiliation, $coi_affiliation,
        $expirydate);

The second argument indicates
whether it is desirable to overwrite an existing project. An exception
will be thrown if this value is false and the project in question
already exists.

taumin and taumax are optional (assume minimum of zero and no upper
limit). As are seemax, seemin, cloudmin, cloudmax and skymin and
skymax. Note that in order to specify a seeing range the tau range
must be specified!

TAG priority, tag adjust and country can be references to an
array. The number of priorities must match the number of countries
unless the number of priorities is one (in which case that priority is
used for all).  Also, the first country is always set as the primary
country.

People are supplied as OMP User IDs. CoI and Support can be colon or comma
separated.

=cut

sub addProject {
    my $class = shift;
    my $db = shift;
    my $force = shift;
    my @project = @_;
    OMP::General->log_message("Util::Project::addProject: $project[0]\n");

    throw OMP::Error::BadArgs(
        "Should be at least 11 elements in project array. Found "
        . scalar(@project))
        unless scalar(@project) >= 11;

    my $userdb = OMP::UserDB->new(DB => $db);

    # Split CoI and Support on colon or comma
    my @coi;
    if ($project[2]) {
        @coi = map {
            $userdb->getUser($_)
                or throw OMP::Error::FatalError(
                    "User ID $_ not recognized by OMP system [project=$project[0]]")
            }
            split /[:,]/, $project[2];
    }
    if (defined $project[21]) {
        my @coi_affiliations = split /[:,]/, $project[21];
        foreach my $this_coi (@coi) {
            last unless scalar @coi_affiliations;
            my $affiliation = shift @coi_affiliations;
            throw OMP::Error::FatalError(
                "CoI [$project[1]] affiliation '$affiliation' not recognized by the OMP")
                unless exists $OMP::DB::ProjAffiliation::AFFILIATION_NAMES{$affiliation};
            $this_coi->affiliation($affiliation);
        }
    }

    my @support;
    if ($project[3]) {
        @support = map {
            $userdb->getUser($_)
                or throw OMP::Error::FatalError(
                    "User ID $_ not recognized by OMP system [project=$project[0]]")
        } split /[:,]/, $project[3];
    }

    # Create range object for tau (and force defaults if required)
    my $taurange = OMP::Range->new(Min => $project[11], Max => $project[12]);
    OMP::SiteQuality::undef_to_default('TAU', $taurange);

    # And seeing
    my $seerange = OMP::Range->new(Min => $project[13], Max => $project[14]);
    OMP::SiteQuality::undef_to_default('SEEING', $seerange);

    # and cloud
    my $cloudrange = OMP::Range->new(Min => $project[15], Max => $project[16]);
    OMP::SiteQuality::undef_to_default('CLOUD', $cloudrange);

    # and sky brightness
    # reverse min and max for magnitudes (but how do we know?)
    my $skyrange = OMP::Range->new(Min => $project[18], Max => $project[17]);

    # Set up queue information
    # Convert tag to array ref if required
    my $tag = (ref($project[5]) ? $project[5] : [$project[5]]);
    my $tagadjs = (ref($project[7]) ? $project[7] : [$project[7]]);

    throw OMP::Error::FatalError("TAG priority/country mismatch")
        unless ($#$tag == 0 || $#$tag == $#{$project[6]});

    # set up queue for each country in turn
    my %queue;
    my %tagadj;
    for my $i (0 .. $#{$project[6]}) {
        # read out priority (this is the TAG priority)
        my $pri = ($#$tag > 0 ? $tag->[$i] : $tag->[0]);

        # find the TAG adjustment (default to 0 if we run out)
        my $adj = ($#$tagadjs > 0 ? $tagadjs->[$i] : $tagadjs->[0]);
        $adj = 0 unless defined $adj;

        # must correct the TAG priority
        $tagadj{uc($project[6]->[$i])} = $adj;
        $queue{uc($project[6]->[$i])} = $pri + $adj;

    }
    my $primary = uc($project[6]->[0]);

    throw OMP::Error::FatalError("Must supply a telescope")
        unless defined $project[10];

    # Get the PI information
    my $pi = $userdb->getUser($project[1]);
    throw OMP::Error::FatalError(
        "PI [$project[1]] not recognized by the OMP")
        unless defined $pi;
    if (defined $project[20]) {
        throw OMP::Error::FatalError(
            "PI [$project[1]] affiliation '$project[20]' not recognized by the OMP")
            unless exists $OMP::DB::ProjAffiliation::AFFILIATION_NAMES{$project[20]};
        $pi->affiliation($project[20]);
    }

    my $expirydate = undef;
    if (defined $project[22]) {
        $expirydate = OMP::DateTools->parse_date($project[22]);
        throw OMP::Error::FatalError("Expiry date not understood")
            unless defined $expirydate;
    }

    throw OMP::Error::FatalError("Semester is mandatory.")
        unless defined $project[8];

    # Instantiate OMP::Project object
    my $proj = OMP::Project->new(
        projectid => $project[0],
        pi => $pi,
        coi => \@coi,
        support => \@support,
        title => $project[4],
        primaryqueue => $primary,
        queue => \%queue,
        tagadjustment => \%tagadj,
        semester => $project[8],
        allocated => $project[9],
        telescope => $project[10],
        taurange => $taurange,
        seeingrange => $seerange,
        cloudrange => $cloudrange,
        skyrange => $skyrange,
        state => $project[19],
        expirydate => $expirydate,
    );

    my $projdb = OMP::ProjDB->new(
        DB => $db,
        ProjectID => $proj->projectid,
    );

    $projdb->addProject($proj, $force);

    return 1;
}

1;

__END__

=back

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
