package OMP::CGIPage::PkgData;

=head1 NAME

OMP::CGIPage::PkgData - Routines to help web serving of data packaging

=head1 SYNOPSIS

    use OMP::CGIPage::PkgData;

=head1 DESCRIPTION

General routines required to create a web page for packaging
OMP data files for the PI. Note that JCMT data retrieval requests
are optionally routed through CADC.

=cut

use 5.006;
use strict;
use warnings;
use OMP::Error qw/:try/;
use File::Basename;
our $VERSION = '0.03';

use OMP::ArchiveDB;
use OMP::ProjDB;
use OMP::PackageData;

use base qw/OMP::CGIPage/;

=head1 PUBLIC FUNCTIONS

These functions write the web page.

=over 4

=item B<request_data>

Request the UT date of interest and/or package the data
and serve it. Will use CADC if the configuration for this telescope
requests it.

If inccal is not specified it defaults to true.

=cut

sub request_data {
    my $self = shift;
    my $projectid = shift;

    my $q = $self->cgi;

    my $utdate = $q->param('utdate');
    my $inccal = $q->param('inccal') // 1;

    my %ctx = (
        projectid => $projectid,
        utdate => $utdate,
        inccal => $inccal,
    );

    # if we have a date, package up the data
    if ($utdate) {
        # Need to decide whether we are using CADC or OMP for data retrieval
        # To do that we need to know the telescope name
        my $tel = OMP::ProjDB->new(
            DB => $self->database, ProjectID => $projectid)->getTelescope();

        return $self->_write_error(
            "Error obtaining telescope name from project code.")
            unless defined $tel;

        # Now determine which retrieval scheme is in play (cadc vs omp)
        my $retrieve_scheme;
        try {
            $retrieve_scheme = OMP::Config->getData("retrieve_scheme", telescope => $tel);
        }
        otherwise {
            $retrieve_scheme = 'omp';
        };

        # Go through the package data object so that we do not need to worry about
        # inconsistencies with local retrieval

        my $arcdb = OMP::ArchiveDB->new(DB => $self->database_archive);

        my $pkg;
        my $error;
        try {
            $pkg = OMP::PackageData->new(
                ADB => $arcdb,
                utdate => $utdate,
                projectid => $projectid,
                inccal => $inccal,
                incjunk => 0,
            );
        }
        catch OMP::Error::UnknownProject with {
            my $E = shift;
            $error = "This project ID is not recognized by the OMP.";
        }
        otherwise {
            my $E = shift;
            $error = "Odd data retrieval error: $E";
        };

        return $self->_write_error($error)
            if defined $error;

        $ctx{'messages'} = $pkg->flush_messages();

        if ($tel eq 'JCMT' && $retrieve_scheme =~ /cadc/i) {
            $ctx{'result'} = $self->_package_data_cadc($pkg);
        }
        else {
            $ctx{'result'} = $self->_package_data($pkg);
        }
    }
    else {
        $ctx{'target'} = $self->url_absolute();
    }

    return \%ctx;
}

=back

=head2 Internal functions

=over 4

=item B<_package_data>

Write output HTML and package up the data.

    $page->_package_data($pkg);

=cut

sub _package_data {
    my $self = shift;
    my $pkg = shift;

    try {
        $pkg->pkgdata(user => $self->auth->user);
    }
    otherwise {
        my $E = shift;
        $pkg->_add_message("Could not create data package(s): $E");
    };

    return {
        method => 'omp',
        messages => $pkg->flush_messages,
        ftp_urls => [$pkg->ftpurl],
    };
}

=item B<_package_data_cadc>

Write output HTML and special form required for CADC retrieval

    $page->_package_data_cadc($pkg);

=cut

sub _package_data_cadc {
    my $self = shift;
    my $pkg = shift;

    # Write a feedback message even though we can not be sure the person
    # will click on the link
    $pkg->add_fb_comment("(via CADC)", $self->auth->user);

    # Get the obsGrp
    my $obsgrp = $pkg->obsGrp;

    # get the file names and strip path information if present
    my @obs = $obsgrp->obs();
    my @files =
        map {OMP::PackageData::cadc_file_uri($_)}
        map {$_->simple_filename} @obs;

    # The "runid" is to allow CADC to recognise which download requests came
    # from the OMP rather than their own systems.  CADC have indicated that
    # any common string will do -- and "omp" has been chosen.  We can add
    # additional parts to the end of the string (up to 16 characters total)
    # if we would like to add extra tracking for diagnostic purposes.  They
    # log the value in their transfer database.
    my $run_id = 'omp';

    return {
        method => 'cadc',
        file_urls => \@files,
        run_id => $run_id,
    };
}

1;

__END__

=back

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002,2007 Particle Physics and Astronomy Research Council.
All Rights Reserved.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the
Free Software Foundation, Inc., 59 Temple Place, Suite 330,
Boston, MA  02111-1307  USA

=cut
