#!/local/perl/bin/perl

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

See also B<info> blurb elsewhere in relation to I<country>,
I<priority>, I<semester>, I<telescope> options.

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

=item B<-country> "country" code

Specify default country code to use for a project missing one.

=item B<-no-country-check> | B<-no-cc>

Specify that project with new country code is being added, so
avoid country code check.

This implies that B<country code check will be avoided for all of the
projects being added> during current run.

=item B<--no-project-check>

Specify that the given project identifiers should not be validated.

This option should be used with caution: if project idenifiers are
not valid then they will not be recognized by the OMP in some situations.
For example it will not be possible to send feedback to the project via
email to flex.

=item B<-priority> integer

Specify default tag priority to use.

=item B<-semester> semester

Specify default semester to use.

=item B<-telescope> UKIRT | JCMT

Specify default telescope.

=item B<--disable>

Create projects in the "disabled" state.

=item B<--dry-run>

Dry run mode: do not actually add projects to the database.

=back

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

=cut

# Uses the infrastructure classes so each project is inserted
# independently rather than as a single transaction

use warnings;
use strict;

use FindBin;
use constant OMPLIB => "$FindBin::RealBin/../lib";

use lib OMPLIB;

BEGIN {
    $ENV{'OMP_CFG_DIR'} = File::Spec->catdir(OMPLIB, '../cfg')
        unless exists $ENV{'OMP_CFG_DIR'};
}

use OMP::Error qw/ :try /;
use Config::IniFiles;
use Data::Dumper;
use IO::File;
use OMP::DB::Backend;
use OMP::General;
use OMP::DB::Project;
use OMP::Util::Project;
use OMP::SiteQuality;
use OMP::Password;
use OMP::DB::User;
use Pod::Usage;
use Getopt::Long;

our $VERSION = '2.000';

# Options
my $do_country_check = 1;
my $do_project_check = 1;
my ($help, $man, $version, $force, $disable, $dry_run, %defaults);
my $status = GetOptions(
    "help" => \$help,
    "man" => \$man,
    "version" => \$version,
    "force" => \$force,
    "disable" => \$disable,
    "dry-run" => \$dry_run,
    'no-cc|no-country-check' => sub {$do_country_check = 0;},
    'no-project-check' => sub {$do_project_check = 0;},

    "country=s" => \$defaults{'country'},
    "priority=i" => \$defaults{'tagpriority'},
    "semester=s" => \$defaults{'semester'},
    "telescope=s" => \$defaults{'telescope'},
) or pod2usage(-exitstatus => 1, -verbose => 0);

pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

if ($version) {
    print "mkproj - upload project details from file\n";
    print "Version: ", $VERSION, "\n";
    exit;
}

# Read the file
my $file = shift(@ARGV);
my %alloc;
my $fh = IO::File->new($file, 'r');
die "Could not open file '$file'" unless defined $fh;
$fh->binmode(':utf8');
tie %alloc, 'Config::IniFiles', (-file => $fh);
$fh->close();

my $db = OMP::DB::Backend->new;

my %ok_field;
{
    my @field = (
        'allocation',
        'band',
        'cloud',
        'coi',
        'coi_affiliation',
        'country',
        'expiry',
        'pi',
        'pi_affiliation',
        'seeing',
        'semester',
        'sky',
        'support',
        'tagadjustment',
        'tagpriority',
        'taurange',
        'telescope',
        'title',
    );
    @ok_field{@field} = ();
}

# Get the defaults (if specified)
%defaults = (%defaults, %{$alloc{info}})
    if $alloc{info};

check_fields(\%defaults);

# Get the support information
my %support;
%support = %{$alloc{support}}
    if $alloc{support};

# oops
unless (keys %alloc) {
    for my $err (@Config::IniFiles::errors) {
        print "! $err\n";
    }
    collect_err("Did not find any projects in input file");
}

if (any_err()) {
    print "Could not import projects due to ... \n", get_err();
    exit 1;
}

unless ($dry_run) {
    OMP::Password->get_verified_auth($db, 'staff');
}

# Loop over each project and add it in
for my $proj (sort {uc $a cmp uc $b} keys %alloc) {
    next if $proj eq 'support';
    next if $proj eq 'info';

    reset_err();

    normalize_field_case($alloc{$proj});
    normalize_coi($alloc{$proj});
    check_fields($alloc{$proj});

    # Copy the data from the file and merge with the defaults
    my %details = (%defaults, %{$alloc{$proj}});

    for my $key (keys %details) {
        next unless defined $details{$key};

        $details{$key} =~ s/\s*#.*$//;
    }

    collect_err("No country code given")
        unless exists $details{'country'}
        and defined $details{'country'}
        and length $details{'country'};

    # Upper case country for lookup table
    # and split on comma in case we have more than one
    $details{country} = [split /,/, uc($details{country})];

    #if exists $details{country};

    upcase(\%details, qw/pi coi support semester telescope/);

    downcase(\%details, qw/pi_affiliation coi_affiliation/);

    check_project($proj) if $do_project_check;

    check_country($details{country}) if $do_country_check;

    # TAG priority
    my @tag;
    @tag = split /,/, $details{tagpriority}
        if exists $details{tagpriority};

    collect_err("Number of TAG priorities is neither 1 nor number of countries [$proj]")
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
    if (! defined $details{support}
            && exists $details{country}
            && exists $details{country}->[0]) {
        my $country = $details{country}->[0];
        if (exists $support{$country}) {
            $details{support} = $support{$country};
        }
        else {
            collect_err("Can not find support for country " . $country);
        }
    }

    collect_err("Must supply a valid telescope.")
        unless exists $details{telescope}
        && verify_telescope($details{telescope});

    # Now weather bands
    my ($taumin, $taumax) = OMP::SiteQuality::default_range('TAU');
    if (exists $details{taurange}) {
        ($taumin, $taumax) = split_range($details{taurange});
    }
    elsif (exists $details{band}) {
        # Get the tau range from the weather bands if it exists
        my @bands = split_range($details{band});
        my $taurange = OMP::SiteQuality::get_tauband_range($details{telescope}, @bands);
        collect_err("Error determining tau range from band '$details{band}' !")
            unless defined $taurange;

        ($taumin, $taumax) = $taurange->minmax;
    }

    # And seeing
    my ($seemin, $seemax) = OMP::SiteQuality::default_range('SEEING');
    if (exists $details{seeing}) {
        ($seemin, $seemax) = split_range($details{seeing});
    }

    # cloud
    my ($cloudmin, $cloudmax) = OMP::SiteQuality::default_range('CLOUD');
    if (exists $details{cloud}) {

        # if we have no comma, assume this is a cloudmax and "upgrade" it
        if ($details{cloud} !~ /[-,]/) {
            my $r = OMP::SiteQuality::upgrade_cloud($details{cloud});
            ($cloudmin, $cloudmax) = $r->minmax;
        }
        else {
            ($cloudmin, $cloudmax) = split_range($details{cloud});
        }
    }

    # And sky brightness
    my ($skymin, $skymax) = OMP::SiteQuality::default_range('SKY');
    if (exists $details{sky}) {
        ($skymin, $skymax) = split_range($details{sky});
    }

    # Now convert the allocation to seconds instead of hours
    collect_err("[project $proj] Allocation is mandatory!")
        unless defined $details{allocation};

    # Set minimum of 1 s of time to avoid divide-by-zero problem elsewhere.
    # Further, specifying (in configuration file) decimal result of 1/3600 is a
    # pain.
    $details{allocation} ||= 1 / 3600;

    collect_err("[project $proj] Allocation must be non-zero and positive!")
        unless $details{allocation} > 0;

    $details{allocation} *= 3600;

    # User ids
    if (my @unknown = unverified_users(@details{qw/pi coi support/})) {
        collect_err('Unverified user(s): ' . join ', ', @unknown);
    }

    print "\nAdding [$proj]\n";

    if (any_err()) {
        print " skipped due to ... \n", get_err();
        next;
    }

    my @project_args = (
        $proj,  # project id
        $details{pi},
        $details{coi},
        $details{support},
        $details{title},
        $details{tagpriority},
        $details{country},
        $details{tagadjustment},
        $details{semester},
        $details{allocation},
        $details{telescope},
        $taumin, $taumax,
        $seemin, $seemax,
        $cloudmin, $cloudmax,
        $skymin, $skymax,
        ($disable ? 0 : 1),
        $details{'pi_affiliation'},
        $details{'coi_affiliation'},
        $details{'expiry'},
    );

    # Stop here in dry-run mode.
    if ($dry_run) {
        print Dumper(\@project_args);
        next;
    }

    # Now add the project
    try {
        OMP::Util::Project->addProject($db, $force, @project_args);
    }
    catch OMP::Error::ProjectExists with {
        print " - but the project already exists. Skipping.\n";
    };
}

# Given a a list of users (see "FORMAT" section of pod elsewhere) for a project,
# returns a list of unverified users. C<OMP::Error> exceptions are caught &
# saved for later display elsewhere.
#
# OMP::Util::Project->addProject throws exceptions for each user one at a time.  So
# user id verification is also done for all the user ids related to a project in
# one go.
sub unverified_users {
    my (@list) = @_;

    # For reference, see C<OMP::Util::Project->addProject()>.
    my $id_sep = qr/[,:]+/;

    my $udb = OMP::DB::User->new(DB => $db);

    my @user;
    for my $user (map {$_ ? split /$id_sep/, $_ : ()} @list) {
        try {
            push @user, $user
                unless $udb->verifyUser($user);
        }
        catch OMP::Error with {
            my $E = shift;
            collect_err("Error while checking user id [$user]: $E");
        }
    }

    return sort {uc $a cmp uc $b} @user;
}

sub verify_telescope {
    my ($tel) = @_;

    return defined $tel
        && grep {uc $tel eq $_} ('JCMT', 'UKIRT');
}

sub check_project {
    my ($proj) = shift;

    # If the project is valid, we should be able to "extract" it and end up
    # with the same as what we started with.
    my $extracted = OMP::General->extract_projectid($proj);

    if ($proj ne $extracted) {
        collect_err('Project does not match any expected pattern: ' . $proj);
        return 0;
    }

    return 1;
}

sub check_country {
    my ($countries) = @_;

    my $projdb = OMP::DB::Project->new(DB => $db);
    my %allowed = map {$_ => undef} $projdb->listCountries;

    my $ok = 1;
    for my $c (@{$countries}) {
        unless (exists $allowed{$c}) {
            collect_err("Unrecognized country code: $c");
            $ok = 0;
        }
    }

    return $ok;
}

# Collect the errors for a project.
{
    my (@err);

    # To reset the error string list, say, while looping over a list of projects.
    sub reset_err {
        undef @err;
        return;
    }

    # Tell if any error strings have been saved yet.
    sub any_err {
        return scalar @err;
    }

    # Save errors.
    sub collect_err {
        push @err, @_;
        return;
    }

    # Returns a list of error strings with newlines at the end.  Optionally takes
    # a truth value to disable addition of a newline.
    sub get_err {
        my ($no_newline) = @_;

        return unless any_err();

        return map {
            my $nl = $no_newline || $_ =~ m{\n\z}x ? '' : "\n";
            sprintf " - %s$nl", $_;
        } @err;
    }
}

# Changes case of values (plain scalars or array references) to upper case in
# place, given a hash reference and a list of interesting keys.
sub upcase {
    my ($hash, @key) = @_;

    KEY: for my $k (@key) {
        next unless exists $hash->{$k};

        for ($hash->{$k}) {
            next KEY unless defined $_;

            # Only an array reference is expected.
            $_ = ref $_ ? [map {uc $_} @{$_}] : uc $_;
        }
    }

    return;
}

sub downcase {
    my ($hash, @keys) = @_;

    foreach my $key (@keys) {
        $hash->{$key} = lc $hash->{$key} if exists $hash->{$key};
    }
}

sub split_range {
    my ($in) = @_;

    return
        unless defined $in
        && length $in;

    return split /[-,]/, $in;
}

# Change field name to lower case.
sub normalize_field_case {
    my ($details) = @_;

    for my $key (keys %{$details}) {
        $key eq lc $key and next;

        $details->{lc $key} = delete $details->{$key};
    }

    return;
}

# Convert all variations on 'coi' to 'coi'.
sub normalize_coi {
    my ($details) = @_;

    for my $alt ('cois', 'co-i', 'co-is') {
        next unless exists $details->{$alt};

        $details->{'coi'} = join ',',
            (exists $details->{'coi'} ? $details->{'coi'} : ()),
            delete $details->{$alt};
    }

    return;
}

# Check for unknown, possibly misspelled, fields.
sub check_fields {
    my ($details) = @_;

    my @unknown;
    for my $field (sort {lc $a cmp lc $b} keys %{$details}) {
        push @unknown, $field
            unless exists $ok_field{lc $field};
    }

    return 1 unless scalar @unknown;

    collect_err(sprintf 'Unknown field(s) listed: %s.', join ', ', @unknown);

    return;
}

__END__

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
