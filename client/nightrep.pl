#!/local/perl/bin/perl -X

=head1 NAME

nightrep - View end of night observing report

=head1 SYNOPSIS

    nightrep
    nightrep -ut 2002-12-10
    nightrep -tel jcmt
    nightrep -ut 2002-10-05 -tel ukirt
    nightrep --help

=head1 DESCRIPTION

This program previously allowed you to review, edit and submit an end of night
report.  Please see instead the new time accounting web page:

    https://omp.eao.hawaii.edu/cgi-bin/timeacct.pl?telescope=JCMT

This program can now only be used in software debugging modes
(options C<--dump> and C<--ashtml>).

=head1 OPTIONS

The following options are supported:

=over 4

=item B<-dump>

Print log to standard out in text format.

=item B<-ashtml>

Print log to standard out in HTML format.

=item B<-ut> YYYYMMDD | YYYY-MM-DD

Override the UT date used for the report. By default the current date
is used. The UT can be specified in either YYYY-MM-DD or YYYYMMDD format.
If the supplied date is not parseable, the current date will be used.

=item B<-tel> jcmt | ukirt

Specify the telescope to use for the report. If the telescope can
be determined from the domain name it will be used automatically.

=item B<-cache>

=item B<-no-cache>

Ignore any observations cache files related to given UT dates.
Default is to query cache files.

=item B<-version>

Report the version number.

=item B<-help>

A help message.

=item B<-man>

This manual page.

=back

=cut

use 5.006;
use strict;
use warnings;

use Getopt::Long qw/:config gnu_compat no_ignore_case require_order/;
use Pod::Usage;

# Locate the OMP software through guess work
use FindBin;
use lib "$FindBin::RealBin/../lib";

# OMP Classes
use OMP::ArchiveDB;
use OMP::DB::Backend;
use OMP::DB::Backend::Archive;
use OMP::Error qw/ :try /;
use OMP::DateTools;
use OMP::General;
use OMP::NightRep;

our $VERSION = '2.000';

my $DEBUG = 0;

# Options
my $use_cache = 1;
my ($help, $man, $version, $dump, $tel, $ut, $ashtml);
GetOptions(
    "help" => \$help,
    "man" => \$man,
    "version" => \$version,
    'dump' => \$dump,
    "ut=s" => \$ut,
    "tel=s" => \$tel,
    'cache!' => \$use_cache,
    'ashtml' => \$ashtml,
) or pod2usage(1);

pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

if ($version) {
    print "nightrep - End of night reporting tool\n";
    print "Version: ", $VERSION, "\n";
    exit;
}

# First thing we need to do is determine the telescope and
# the UT date
$ut = OMP::DateTools->determine_utdate($ut)->ymd;

# Telescope
my $telescope;
if (defined $tel) {
    $telescope = uc $tel;
}
else {
    require Term::ReadLine;
    my $term = Term::ReadLine->new('View night log');
    $telescope = OMP::General->determine_tel($term);
    die "Unable to determine telescope. Exiting.\n" unless defined $telescope;
}

unless ($dump or $ashtml) {
    # Neither debugging option was specified: provide the URL of the
    # web page for the requested telescope and date.
    my $url = sprintf
        'https://omp.eao.hawaii.edu/cgi-bin/timeacct.pl?telescope=%s&utdate=%s',
        $telescope,
        $ut;

    print "Please see instead the time accounting web page:\n$url\n";
    exit 0;
}

# Night report

my $db = OMP::DB::Backend->new;
my $arcdb = OMP::ArchiveDB->new(DB => OMP::DB::Backend::Archive->new);

# Modify only the non-default behaviour.
unless ($use_cache) {
    $arcdb->skip_cache_query();
}

my $NR = OMP::NightRep->new(
    DB => $db,
    ADB => $arcdb,
    date => $ut,
    telescope => $telescope);

if ($dump) {
    print scalar $NR->astext();
    exit 0;
}
else {
    require OMP::CGIPage;
    my $template = '[% USE scalar -%]'
        . '[% PROCESS "macro_night_report.html" -%]'
        . '[% PROCESS "macro_shift_log.html" -%]'
        . '[% render_night_report(night_report) %]';
    OMP::CGIPage->new()->render_template(\$template, {night_report => $NR});
    exit 0;
}

__END__

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002-2005 Particle Physics and Astronomy Research Council.

Copyright (C) 2015 East Asian Observatory.

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
