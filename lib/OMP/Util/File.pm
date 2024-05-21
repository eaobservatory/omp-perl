package OMP::Util::File;

=head1 NAME

OMP::Util::File - File-related utilities for the OMP

=head1 SYNOPSIS

    use OMP::Util::File;

    $util = OMP::Util::File->new();
    @files = $util->files_on_disk(
        'instrument' => $inst, 'date' => $date);

=head1 DESCRIPTION

This class provides general purpose routines that are used for
handling files for the OMP system.

=cut

use 5.006;
use strict;
use warnings::register;

use File::Basename qw/fileparse/;
use File::Spec;
use Scalar::Util qw/blessed/;

use OMP::Error qw/:try/;
use OMP::Config;
# For logging.
use OMP::Constants qw/:logging/;
use OMP::General;

our $VERSION = '2.000';
our $DEBUG = 0;

my $MISS_CONFIG_KEY =
    qr{ \b
        Key .+? could \s+ not \s+ be \s+ found \s+ in \s+ OMP \s+ config
    }xi;

my $MISS_DIRECTORY =
    qr{ \b
        n[o']t \s+ open \s+ dir .+?
        \b
        No \s+ such \s+ file
        \b
    }xis;

=head1 METHODS

=head2 Constructor

Construct new C<OMP::Util::File> object.

    my $util = OMP::Util::File->new();

Any given hash options are passed to the corresponding methods.

=cut

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my %opt = @_;

    my $self = bless {
        recent_files => 0,
        file_time => {},
        file_raw => {},
    }, $class;

    foreach (keys %opt) {
        $self->$_($opt{$_});
    }

    return $self;
}

=head2 Instance methods

=over 4

=item B<recent_files>

Set/get "recent files" option.

=cut

sub recent_files {
    my $self = shift;

    if (@_) {
        $self->{'recent_files'} = shift;
    }

    return $self->{'recent_files'};
}

=item B<files_on_disk>

For a given instrument and UT date, this method returns a list of
observation files.

    @files = $util->files_on_disk(
        'instrument' => 'CGS4',
        'date' => $date);

    $files = $util->files_on_disk(
        'instrument' => 'CGS4',
        'date' => $date,
        'run' => $runnr);

    @files = $util->files_on_disk(
        'instrument' => 'SCUBA-2',
        'date' => $date,
        'subarray' => $subarray,
        'recent' => 2);

The instrument must be a string. The date must be a Time::Piece
object. If the date is not passed as a Time::Piece object then an
OMP::Error::BadArgs error will be thrown. The run number must be an
integer. If the run number is not passed or is zero, then no filtering
by run number will be done.

For SCUBA2 files, a subarray must be specified (from '4a' to '4d', or
'8a' to '8d').

Optionally specify number of files older than new ones on second &
later calls to be returned. On first call, all the files will be
returned.

If called in list context, returns a list of array references. Each
array reference points to a list of observation files for a single
observation. If called in scalar context, returns a reference to an
array of array references.

=cut

sub files_on_disk {
    my ($self, %arg) = @_;

    my ($instrument, $utdate, $runnr, $subarray, $old) =
        @arg{qw/instrument date run subarry old/};

    if (! UNIVERSAL::isa($utdate, "Time::Piece")) {
        throw OMP::Error::BadArgs(
            "Date parameter to OMP::General::files_on_disk must be a Time::Piece object");
    }

    if (! defined($runnr) || $runnr < 0) {
        $runnr = 0;
    }

    my $sys_config = OMP::Config->new;

    # Retrieve information from the configuration system.
    my $tel = $sys_config->inferTelescope('instruments', $instrument);

    my %config = (
        telescope => $tel,
        instrument => $instrument,
        utdate => $utdate,
        runnr => $runnr,
        subarray => $subarray,
    );

    my $directory = $sys_config->getData('rawdatadir', %config);
    my $flagfileregexp = $sys_config->getData('flagfileregexp', telescope => $tel,);

    # getData() throws an exception in the case of missing key.  No point in dying
    # then as default value will be used instead from earlier extraction.
    try {
        $directory = $sys_config->getData("${instrument}.rawdatadir", %config);

        $flagfileregexp = $sys_config->getData("${instrument}.flagfileregexp", %config);
    }
    catch OMP::Error::BadCfgKey with {
        my ($e) = @_;

        my $text = $e->text();
        _log_filtered($text, $MISS_CONFIG_KEY);
        throw $e unless $text =~ $MISS_CONFIG_KEY;
    };

    my $mute_miss_raw = 0;
    my $mute_miss_flag = 1;
    my ($use_meta, @return);

    if ($self->use_raw_meta_opt($sys_config, %config)) {
        @return = $self->get_raw_files_from_meta(
            'omp-config' => $sys_config,
            'search-config' => \%config,
            'flag-regex' => $flagfileregexp,
            'mute-miss-flag' => $mute_miss_flag,
            'mute-miss-raw' => $mute_miss_raw,
        );

        _track_file('returning: ' => @return);
    }
    else {
        @return = $self->get_raw_files(
            $directory,
            $self->get_flag_files(
                $directory, $flagfileregexp, $runnr, $mute_miss_flag
            ),
            $mute_miss_raw
        );
    }

    return wantarray ? @return : \@return;
}

sub use_raw_meta_opt {
    my ($self, $omp_config, %config) = @_;

    my $meta;
    try {
        $meta = $omp_config->getData(qq[$config{'instrument'}.raw_meta_opt], %config);
    }
    catch OMP::Error::BadCfgKey with {
        # "raw_meta_opt" may be missing entirely, considered same as a false value.
        my ($e) = @_;

        my $text = $e->text();
        _log_filtered($text, $MISS_CONFIG_KEY);
        throw $e unless $text =~ $MISS_CONFIG_KEY;
    };

    return !! $meta;
}

sub get_raw_files_from_meta {
    my ($self, %arg) = @_;

    my ($sys_config, $config, $flag_re, $mute_flag, $mute_raw) =
        @arg{qw/omp-config search-config flag-regex mute-miss-flag mute-miss-raw/};

    $mute_raw = defined $mute_raw ? $mute_raw : 1;
    $mute_flag = defined $mute_flag ? $mute_flag : 0;

    my $inst = $config->{'instrument'};
    my $meta_dir = $sys_config->getData("${inst}.metafiledir", %{$config});

    my @meta = get_meta_files($sys_config, $config, $flag_re);

    my (@flag);
    for my $file (@meta) {
        # Get flag file list by reading meta files.
        my $flags = OMP::General->get_file_contents(
            'file' => $file,
            'filter' => $flag_re,
        );

        next unless $flags && scalar @{$flags};

        _track_file('flag files: ', @{$flags});

        push @flag, $self->_get_updated_files(
            [map {File::Spec->catfile($meta_dir, $_)} @{$flags}],
            $mute_flag);
    }

    return $self->get_raw_files($meta_dir, [@flag], $mute_raw);
}

sub get_meta_files {
    my ($sys_config, $config, $flag_re) = @_;

    $flag_re = qr{$flag_re};

    # Get meta file list.
    my $inst = $config->{'instrument'};
    my ($meta_dir, $meta_re) =
        map {$sys_config->getData("${inst}.${_}", %$config)} (
        'metafiledir',
        ($config->{'runnr'}
            ? 'metafiledaterunregexp'
            : 'metafiledateregexp'));

    my $metas;
    try {
        $metas = OMP::General->get_directory_contents(
            'dir' => $meta_dir,
            'filter' => qr/$meta_re/,
            'sort' => 1
        );
    }
    catch OMP::Error::FatalError with {
        my ($err) = @_;

        my $text = $err->text();
        _log_filtered($text, $MISS_DIRECTORY);

        return
            if $text =~ /n[o']t open directory/i;
    };

    _track_file('meta files: ', $metas && ref $metas ? @{$metas} : ());

    return unless $metas;
    return @{$metas};
}

sub get_flag_files {
    my ($self, $dir, $filter, $runnr, $mute_err) = @_;

    my $flags;
    try {
        $flags = OMP::General->get_directory_contents(
            'dir' => $dir,
            'filter' => $filter);
    }
    catch OMP::Error::FatalError with {
        my ($err) = @_;

        my $text = $err->text();
        _log_filtered($text, $MISS_DIRECTORY);

        return
            if $text =~ /n[o']t open directory/i;
    };

    # Purge the list if runnr is not zero.
    if ($runnr && $runnr != 0) {
        foreach my $f (@{$flags}) {
            my $basename = fileparse($f);
            if ($basename =~ /$filter/) {
                if (int($1) == $runnr) {
                    $flags = [$f];
                    last;
                }
            }
        }
    }

    return $flags
        unless $self->recent_files;

    my @updated = $self->_get_updated_files($flags, $mute_err);

    return [] unless scalar @updated;
    return [@updated];
}

sub _get_updated_files {
    my $self = shift;
    my ($list, $mute) = @_;

    my $file_time = $self->{'file_time'};

    return unless $list && scalar @{$list};

    return @{$list}
        unless $self->recent_files;

    # Skip filtering to narrow down temporary time gap problem.
    return @{$list}
        if $list->[0] =~ /[.](?:meta|ok)\b/;

    my @send;
    my %mod = _get_mod_epoch($list, $mute);

    while (my ($f, $t) = each %mod) {
        next
            if exists $file_time->{$f}
            && $file_time->{$f}
            && $t <= $file_time->{$f};

        $file_time->{$f} = $t;
        push @send, $f;
    }

    return unless scalar @send;

    # Sort files by ascending modification times.
    return
        map {$_->[0]}
        sort {$a->[1] <=> $b->[1]}
        map {[$_, $mod{$_}]}
        @send;
}

# Go through each flag file, open it, and retrieve the list of files within it.
sub get_raw_files {
    my ($self, $dir, $flags, $mute_err) = @_;

    my $file_raw = $self->{'file_raw'};

    return
        unless $flags && scalar @{$flags};

    my @raw;

    foreach my $file (@{$flags}) {
        # RxH3 writes FITS files but no flag files -- temporary work around
        # is to have the FITS files themselves be the flags.
        if ($file =~ /.fits$/) {
            push @raw, [$file];
            next;
        }

        # If the flag file size is 0 bytes, then we assume that the observation file
        # associated with that flag file is of the same naming convention, removing
        # the dot from the front and replacing the .ok on the end with .sdf.
        if (-z $file) {
            my $raw = $self->make_raw_name_from_flag($file);

            next unless _sanity_check_file($raw);

            push @raw, [$raw];
            next;
        }

        my ($lines, $err);
        try {
            $lines = OMP::General->get_file_contents('file' => $file);
        }
        catch OMP::Error::FatalError with {
            ($err) = @_;

            OMP::General->log_message($err->text(), OMP__LOG_WARNING);

            unless ($mute_err) {
                throw $err
                    unless $err =~ /^Cannot open file/i;
            }
        };

        my @checked;
        for my $file (@{$lines}) {
            my $f = File::Spec->catfile($dir, $file);

            next
                if $self->recent_files
                && exists $file_raw->{$f};

            next unless _sanity_check_file($f);

            undef $file_raw->{$f} if $self->recent_files;
            push @checked, $f;
        }
        push @raw, [@checked];
    }

    return @raw;
}

sub make_raw_name_from_flag {
    my ($self, $flag) = @_;

    my $suffix = '.sdf';

    my ($raw, $dir) = fileparse($flag, '.ok');
    $raw =~ s/^[.]//;

    return File::Spec->catfile($dir, $raw . $suffix);
}

sub _sanity_check_file {
    my ($file, $no_warn) = @_;

    my $read = -r $file;
    my $exist = -e _;
    my $non_empty = -s _;

    return 1 if $read && $non_empty;

    return if $no_warn;

    my $text = ! $exist
        ? 'does not exist'
        : ! $read
            ? 'is not readable'
            : ! $non_empty
                ? 'is empty'
                : 'has some UNCLASSIFIED PROBLEM';

    OMP::General->log_message("$file $text (listed in flag file), skipped\n",
        OMP__LOG_WARNING);

    return;
}

sub _get_mod_epoch {
    my ($files, $mute) = @_;

    my %time;
    for my $f (map {ref $_ ? @{$_} : $_} @{$files}) {
        my ($mod) = (stat $f)[9]
            or do {
                $mute or warn "Could not get modification time of '$f': $!\n";
                next;
            };

        $time{$f} = $mod;
    }

    return %time;
}

sub _track_file {
    return unless $DEBUG;

    my ($label, @descr) = @_;

    OMP::General->log_message(
        join("\n  ", $label, scalar @descr ? @descr : '<none>'),
        OMP__LOG_INFO);
    return;
}

sub _log_filtered {
    my ($err, $skip_re) = @_;

    return
        unless defined $err
        && $skip_re;

    my $text = _extract_err_text($err) or return;

    blessed $skip_re or $skip_re = qr{$skip_re};
    return if $text =~ $skip_re;

    OMP::General->log_message($text, OMP__LOG_WARNING);
    return;
}

sub _extract_err_text {
    my ($err) = @_;

    return unless defined $err;
    return $err unless blessed $err;

    for my $class (
            'OMP::Error',
            'JSA::Error',
            'Error::Simple') {
        next unless $err->isa($class);

        return $err->text()
            if $err->can('text');
    }

    return;
}

1;

__END__

=back

=head1 AUTHORS

=over 4

=item *

Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>

=item *

Anubhav E<lt>a.agarwal@jach.hawaii.eduE<gt>

=back

=head1 COPYRIGHT

Copyright (C) 2006-2009 Science and Technology Facilities Council.
All Rights Reserved.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or (at
your option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307
USA

=cut
