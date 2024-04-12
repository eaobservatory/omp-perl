#!/local/perl/bin/perl

=head1 NAME

collect-summit-previews - Collect preview images from summit pipelines

=head1 SYNOPSIS

    collect-summit-previews --ut YYYYMMDD

=head1 DESCRIPTION

Search for preview images generated by summit pipelines for the
given UT date.  Suitable previews will be copied into the OMP's
preview cache directory and summarized in the C<omppreview>
database table.

=head1 OPTIONS

=over 4

=item B<--ut>

UT date.

=item B<--dry-run>, B<-n>

Skip coping and database entry, instead listing found previews.

=back

=cut

use strict;

use Digest::MD5;
use File::Basename qw/fileparse/;
use File::Path qw/mkpath/;
use File::Spec;
use FindBin;
use Getopt::Long;
use Image::ExifTool;
use IO::File;
use Pod::Usage;
use Time::Piece;

use constant OMPLIB => File::Spec->catdir(
    "$FindBin::RealBin", File::Spec->updir, 'lib');
use lib OMPLIB;

BEGIN {
    $ENV{'OMP_CFG_DIR'} = File::Spec->catdir(OMPLIB, '../cfg')
        unless exists $ENV{'OMP_CFG_DIR'};
}

use OMP::Config;
use OMP::DB::Backend;
use OMP::DateTools;
use OMP::General;
use OMP::Info::Preview;
use OMP::DB::Preview;
use OMP::PreviewQuery;

main();

sub main {
    my ($help, $utdate_str, $dry_run);
    GetOptions(
        help => \$help,
        'n|dry-run' => \$dry_run,
        'ut=s' => \$utdate_str,
    ) or pod2usage(1);
    pod2usage(-exitstatus => 0) if $help;

    my $telescope = 'JCMT';

    die 'Date not specified' unless defined $utdate_str;
    my $date = OMP::DateTools->parse_date($utdate_str);
    die 'Date could not be parsed' unless defined $date;
    my $date_ymd = $date->ymd('');

    my $basedir = OMP::Config->getData('preview.cachedir', telescope => $telescope);
    die 'Base ouput directory does not exist'
        unless -d $basedir;
    my $outdir = File::Spec->catdir(
        $basedir,
        $date->strftime('%Y'),
        $date->strftime('%m'),
        $date->strftime('%d'));
    unless ($dry_run) {
        mkpath($outdir);
    }

    my @pipelinedirs = OMP::Config->getData('preview.pipelinedirs', telescope => $telescope);

    my $db = OMP::DB::Preview->new(DB => OMP::DB::Backend->new());
    my %existing = map {$_->{'filename'} => $_} @{$db->queryPreviews(
        OMP::PreviewQuery->new(HASH => {
            telescope => $telescope,
            date => {value => $date->ymd(''), delta => 1},
    }))};

    my $exiftool = Image::ExifTool->new();

    my @all_previews = ();
    foreach my $pipelinedir (@pipelinedirs) {
        next unless -d $pipelinedir;

        # There should be subdirectories by pipeline name.
        my $subdirectories = OMP::General->get_directory_contents(
            dir => $pipelinedir,
        );

        foreach my $subdirectory (@$subdirectories) {
            # Inside there should be further directories by UT date.
            my $dirname = File::Spec->catdir($subdirectory, $date_ymd);
            next unless -d $dirname;

            push @all_previews, @{collect_previews(
                $exiftool, $telescope, $dirname, $outdir, \%existing, 0, $dry_run)};
        }
    }

    if ($dry_run) {
        print "$_\n" foreach @all_previews;
    }
    else {
        $db->setPreviews(\@all_previews);
    }
}

sub collect_previews {
    my $exiftool = shift;
    my $telescope = shift;
    my $dirname = shift;
    my $outdir = shift;
    my $existing = shift;
    my $compare_quick = shift;
    my $dry_run = shift;

    my $pathnames = OMP::General->get_directory_contents(
        dir => $dirname,
        filter => qr/\.png$/,
    );

    my @previews;
    foreach my $pathname (@$pathnames) {
        my $info = eval {
            collect_preview(
                $exiftool, $telescope, $pathname, $outdir, $existing, $compare_quick, $dry_run)
        };
        if (defined $info) {
            push @previews, $info;
        }
        elsif ($@ ne '') {
            print 'Error reading ' . $pathname . ': ' . $@ . "\n";
        }
    }

    return \@previews;
}

sub collect_preview {
    my $exiftool = shift;
    my $telescope = shift;
    my $pathname = shift;
    my $outdir = shift;
    my $existing = shift;
    my $compare_quick = shift;
    my $dry_run = shift;

    my $preview = fileparse($pathname);
    die "Preview file name pattern match failed for: $preview"
        unless $preview =~ /^(g)?(s|a)(\d{8})_(\d+)(?:_(\d+))?_(\d+)_([-_0-9a-zA-Z]+)_(\d+)\.png$/a;

    my $group = defined $1 ? 1 : 0;
    my $runnr = 0 + $4;
    my $size = 0 + $8;
    my $subscan = defined $5 ? 0 + $5 : undef;
    my $subsystem = 0 + $6;
    my $suffix = $7;
    my $date_filename = $3;

    # Only process the smaller sizes (64, 256) -- ignore size 1024 previews?
    return undef unless $size == 256 or $size == 64;

    my $previous = (exists $existing->{$preview}) ? $existing->{$preview} : undef;

    my @s = stat $pathname;
    my $filesize = $s[7];
    my $epoch = $s[9];

    # If doing a quick comparison, skip this preview image if the
    # size and timestamp both match.
    if ($compare_quick and defined $previous) {
        return undef if $previous->date_modified->epoch == $epoch
            and $previous->filesize == $filesize;
    }

    my $ctx = Digest::MD5->new();
    my $fh = IO::File->new($pathname, 'r');
    my $start = $fh->getpos();
    $ctx->addfile($fh);
    my $md5sum = $ctx->hexdigest();

    # Detailed comparison based on MD5 sum: skip this preview on match.
    if (defined $previous) {
        if ($previous->md5sum eq $md5sum) {
            $fh->close();
            return undef;
        }
    }

    $fh->setpos($start);
    $fh->read(my $buff, 10000000);
    $fh->close();

    unless ($dry_run) {
        my $outfile = File::Spec->catfile($outdir, $preview);
        $fh = IO::File->new($outfile, 'w');
        $fh->write($buff);
        $fh->close();
    }

    $exiftool->ExtractInfo(\$buff);
    my %keywords = map {split '=', $_, 2} $exiftool->GetValue('Keywords');
    die 'Header lacks date-obs' unless exists $keywords{'jsa:date-obs'};
    my $date = OMP::DateTools->parse_date($keywords{'jsa:date-obs'});
    die 'Could not parse date-obs' unless defined $date;
    die 'Filename date does not match date-obs'
        unless $date->ymd('') == $date_filename;
    die 'Header lacks instrume' unless exists $keywords{'jsa:instrume'};
    die 'Instrument invalid' unless $keywords{'jsa:instrume'} =~ /^([-_A-Za-z0-9]+)$/;
    my $instrument = $1;

    return OMP::Info::Preview->new(
        date => $date,
        date_modified => (scalar Time::Piece->gmtime($epoch)),
        group => $group,
        filename => $preview,
        filesize => $filesize,
        instrument => $instrument,
        md5sum => $md5sum,
        runnr => $runnr,
        size => $size,
        subscan_number => $subscan,
        subsystem_number => $subsystem,
        suffix => $suffix,
        telescope => $telescope);
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
