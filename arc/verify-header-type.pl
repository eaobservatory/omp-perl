#!/local/perl/bin/perl

use strict;
use warnings;

=head1 NAME

type-verify - Verify that expected and actual JCMT data file header
types match

=head1 SYNOPSIS

Get usage ...

    type-verify -h

Verify ACSIS file headers ...

    type-verify [ -acsis ] file.sdf [file2.sdf file3.sdf ...]

Verify ACSIS file headers in debug mode, thus verbose mode ...

    type-verify -debug file.sdf

Verify SCUBA2 file headers ...

    type-verify -scuba2 file.sdf [file2.sdf file3.sdf ...]

=head1 DESCRIPTION

This program verifies that expected and actual ACSIS and SCUBA2 data
file header types match.  Currently there is complete support for
ACSIS files; support for SCUBA2 is underway.

I<ACSIS> is assumed to be the default file types.

=head1 OPTIONS

The following options are supported:

=over 4

=item B<-acsis>

Set the verification mode to be 'ACSIS' (default).

=item B<-debug>

Run in debug mode, implies I<verbose> mode.

=item B<-help>

Display usage information.

=item B<-man>

Display manual page.

=item B<-scuba2>

Set the verification mode to be 'SCUBA2'.

=item B<-verbose>

Run in verbose mode (see L<JAC::OCS::Config::Header/read_header_exclusion_file>
and  L<JAC::OCS::Config::Header/remove_excluded_headers>).

=back

=cut

use FindBin;
use File::Spec;

use constant OMPLIB => File::Spec->catdir(
    "$FindBin::RealBin", File::Spec->updir, 'lib');
use lib OMPLIB;

BEGIN {
    $ENV{'OMP_CFG_DIR'} = File::Spec->catdir(OMPLIB, '../cfg')
        unless exists $ENV{'OMP_CFG_DIR'};
}

use JAC::Setup qw/dataverify ocscfg/;

my $DEBUG = 0;

use Getopt::Long qw/:config gnu_compat no_ignore_case/;
use Pod::Usage;

use JAC::OCS::Config::Header;
use JCMT::DataVerify::ACSIS;
use OMP::Config;
use OMP::Info::Obs;
# One of OMP::Translator::(ACSIS|SCUBA2) is require'd later.

my ($type, $verbose, @file) = ('acsis');
($type, $verbose, @file) = get_opt($type);

die "SCUBA2 header verification is not complete yet.\n"
    if $type eq 'scuba2';

my $class = join '::', 'OMP::Translator', uc $type;
eval "require $class" or die $@;
my $translator = $class->new;

if ($DEBUG) {
    $translator->debug(1);
}

# XML file describing the headers.
my $header_def = File::Spec->catfile(
    $translator->wiredir, 'header',
    $type eq 'acsis' ? 'headers_acsis.ent' : 'headers_scuba2.ent');

# List of headers to skip from verification.
my %skip = (
    'acsis' => JCMT::DataVerify::ACSIS->undefined_headers,
    'scuba2' => [],
);

$| = 1;

my (%status, %obs, %order);

foreach my $file (@ARGV) {
    my $obs = OMP::Info::Obs->readfile($file, retainhdr => 1);

    unless (defined $obs) {
        print "Could not read '$file'; skipped\n";
        next;
    }

    my $ocs_cf = JAC::OCS::Config::Header->new(
        'File' => $header_def,
        'validation' => 0);

    warn sprintf "obs type: %s  obs mode: %s  mapping mode: ?\n",
                 map {$obs->$_ || ''} qw/type mode/
        if $DEBUG;

    my $ex_file = $translator->header_exclusion_file(
        'obs_type' => $obs->type,
        'observing_mode' => $obs->mode,
        # XXX mapping_mode is additionally needed for SCUBA2.
    );

    warn sprintf "Header exclusion file: %s\n" , $ex_file
        if $DEBUG;

    $ocs_cf->remove_excluded_headers(
        [$ocs_cf->read_header_exclusion_file($ex_file, $verbose)],
        $verbose);

    eval {
        $ocs_cf->verify_header_types($obs->fits, $skip{$type});
    };
    $status{$file} = $@ ? $@ : 'OK';
}

print make_status(\%status, my $err_only = 1);

exit;

# Returns status message, given hash reference with file name as key, and
# error/status messages as a string.  Second optional argument can be given as a
# true value to skip any files with 'ok' as the message.
sub make_status {
    my ($status, $err_only) = @_;

    my $out = '';

    for my $file (sort keys %{$status}) {
        my $s = $status->{$file};
        my $format;

        if (! $err_only && lc $s eq 'ok') {
            $format = "%s : '%s'\n\n";
        }
        else {
            # Indent errors, assuming one error per line.
            $s =~ s/^(?=[^\s])/  /mg;
            $format = "Problem : '%s' ...\n%s\n\n";
        }

        $out .= sprintf $format, $file, $s;
    }

    return $out;
}

# Returns the instrument type, verbosity flag, and file names, given a string
# listing the defualt instrument.
sub get_opt {
    my ($type) = @_;

    my ($help, $verbose) = ('');
    GetOptions(
        'help'      => sub {$help = 'short'},
        'man'       => sub {$help = 'long'},
        'debug!'    => \$DEBUG,
        'verbose!'  => \$verbose,
        'acsis'     => sub {$type = 'acsis'},
        'scuba2'    => sub {$type = 'scuba2'}
    )
    or die pod2usage(1);

    pod2usage(1) if $help eq 'short';

    pod2usage('-exitstatus' => 1, '-verbose' => 2) if $help eq 'long';

    pod2usage('-message' => 'No files given.',
              '-exitstatus' => 1, '-verbose' => 1)
        unless scalar @ARGV;

    # If debug mode is here, set it for use elsewhere as appropriate.
    $verbose = !! $DEBUG if $DEBUG && ! defined $verbose;

    return ($type, $verbose, @ARGV);
}
