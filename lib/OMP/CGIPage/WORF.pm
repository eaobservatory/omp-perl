package OMP::CGIPage::WORF;

=head1 NAME

OMP::CGIPage::WORF - Display WORF web pages

=head1 SYNOPSIS

    use OMP::CGIPage::WORF;

=head1 DESCRIPTION

This module provides routines for the display of complete
WORF web pages.

=cut

use strict;
use warnings;

use CGI;
use CGI::Carp qw/fatalsToBrowser/;
use Digest::MD5 qw/md5_hex/;
use File::Spec;

use OMP::DB::Archive;
use OMP::Config;
use OMP::CGIComponent::NightRep;
use OMP::DateTools;
use OMP::Error qw/:try/;
use OMP::General;
use OMP::Info::Obs;
use OMP::NightRep;
use OMP::DB::Preview;
use OMP::Query::Preview;

use base qw/OMP::CGIPage/;

=head1 Routines

=cut

sub display_page {
    my $self = shift;
    my $projectid = shift;

    die 'Invalid telescope'
        unless $self->decoded_url_param('telescope') =~ /^([\w]+)$/a;
    my $telescope = $1;

    my $utdate_str = $self->decoded_url_param('ut');
    my $utdate = OMP::DateTools->parse_date($utdate_str);
    die 'Invalid date' unless defined $utdate;

    die 'Invalid instrument'
        unless $self->decoded_url_param('inst') =~ /^([\-\w\d]+)$/a;
    my $inst = $1;

    die 'Invalid runnr' unless $self->decoded_url_param('runnr') =~ /^(\d+)$/a;
    my $runnr = $1;

    my $utdate_ymd = $utdate->ymd('-');
    my $worfimage;
    if (defined $projectid) {
        $worfimage = "fbworfimage.pl?project=${projectid}&telescope=${telescope}&ut=${utdate_ymd}&";
    }
    else {
        $self->_sidebar_night($telescope, $utdate);

        $worfimage = "staffworfimage.pl?telescope=${telescope}&ut=${utdate_ymd}&";
    }

    my $adb = OMP::DB::Archive->new(
        DB => $self->database_archive,
        FileUtil => $self->fileutil);
    my $obs = $adb->getObs(
        telescope => $telescope,
        instrument => $inst,
        ut => $utdate_ymd,
        runnr => $runnr,
        retainhdr => 0
    );

    die 'No matching observation found' unless defined $obs;

    if ((defined $projectid)
            and (lc $obs->projectid ne lc $projectid)
            and $obs->isScience) {
        die "Observation does not match project $projectid.\n";
    }

    my $grp = OMP::Info::ObsGroup->new(obs => [$obs]);
    $grp->commentScan;

    my $pdb = OMP::DB::Preview->new(DB => $self->database);
    my $previews = $pdb->queryPreviews(OMP::Query::Preview->new(HASH => {
        telescope => $telescope,
        instrument => $inst,
        date => {value => $utdate->ymd(), delta => 1},
        runnr => $runnr,
        size => 256,
    }));

    $grp->attach_previews($previews);

    my $nr = OMP::NightRep->new(DB => $self->database);

    return {
        projectid => $projectid,
        obs_summary => $nr->get_obs_summary(obsgroup => $grp),
        observations => [
            sort {$a->startobs->epoch <=> $b->startobs->epoch}
            $grp->obs()],
        target_image => $worfimage,
    };
}

sub thumbnails_page {
    my $self = shift;
    my $projectid = shift;

    die 'Invalid telescope'
        unless $self->decoded_url_param('telescope') =~ /^([\w]+)$/a;
    my $telescope = $1;

    my $utdate_str = $self->decoded_url_param('ut');
    my $utdate = OMP::DateTools->parse_date($utdate_str);
    die 'Invalid date' unless defined $utdate;

    my %query = (
        telescope => $telescope,
        date => $utdate->ymd(),
    );

    my $utdate_ymd = $utdate->ymd('-');
    my $worflink;
    my $worfimage;
    if (defined $projectid) {
        $query{'projectid'} = $projectid;
        $query{'inccal'} = 1;

        $worflink = "fbworf.pl?project=${projectid}&telescope=${telescope}&ut=${utdate_ymd}&";
        $worfimage = "fbworfimage.pl?project=${projectid}&telescope=${telescope}&ut=${utdate_ymd}&";
    }
    else {
        $self->_sidebar_night($telescope, $utdate);

        $worflink = "staffworf.pl?telescope=${telescope}&ut=${utdate_ymd}&";
        $worfimage = "staffworfimage.pl?telescope=${telescope}&ut=${utdate_ymd}&";
    }

    my $arcdb = OMP::DB::Archive->new(
        DB => $self->database_archive,
        FileUtil => $self->fileutil);
    my $grp = OMP::Info::ObsGroup->new(ADB => $arcdb, %query);

    return $self->_write_error('No observations for this project and night')
        if (defined $projectid) and not $grp->numobs;

    my $pdb = OMP::DB::Preview->new(DB => $self->database);
    my $previews = $pdb->queryPreviews(OMP::Query::Preview->new(HASH => {
        telescope => $telescope,
        size => 64,
        date => {value => $utdate->ymd(), delta => 1},
    }));

    $grp->attach_previews($previews);

    return {
        projectid => $projectid,
        ut_date => $utdate,
        observations => [
            sort {$a->startobs->epoch <=> $b->startobs->epoch}
            $grp->obs()],
        target_obs => $worflink,
        target_image => $worfimage,
    };
}

sub display_graphic {
    my $self = shift;
    my $projectid = shift;

    my $q = $self->cgi;

    die 'Invalid telescope'
        unless $self->decoded_url_param('telescope') =~ /^([\w]+)$/a;
    my $telescope = $1;

    my $utdate_str = $self->decoded_url_param('ut');
    my $utdate = OMP::DateTools->parse_date($utdate_str);
    die 'Invalid date' unless defined $utdate;

    die 'Invalid filename'
        unless $self->decoded_url_param('filename') =~ /^([-_0-9A-Za-z]+\.png)$/;
    my $filename = $1;

    die 'Invalid md5sum'
        unless $self->decoded_url_param('md5sum') =~ /^([0-9a-f]+)$/;
    my $md5sum_request = $1;

    # NOTE: Permission check disabled because we currently check the md5sum in
    # the request -- the user could not request an image without knowing this.
    # if (defined $projectid) {
    #     # Fetch the list of previews available to the project and check
    #     # for the requested file.
    #     my $grp = OMP::Info::ObsGroup->new(
    #         telescope => $telescope,
    #         date => $utdate->ymd(),
    #         projectid => $projectid,
    #         inccal => 1,
    #     );
    #     my $pdb = OMP::DB::Preview->new(DB => $self->database);
    #     my $previews = $pdb->queryPreviews(OMP::Query::Preview->new(HASH => {
    #         telescope => $telescope,
    #         date => {value => $utdate->ymd(), delta => 1},
    #     }));
    #     $grp->attach_previews($previews);
    #
    #     my $found = 0;
    #     OBSLOOP: foreach my $obs (@{$grp->obs}) {
    #         foreach my $preview ($obs->previews) {
    #             if ($preview->filename eq $filename) {
    #                 $found = 1;
    #                 last OBSLOOP;
    #             }
    #         }
    #     }
    #
    #     return $self->_write_forbidden() unless $found;
    # }

    my $basedir = OMP::Config->getData('preview.cachedir', telescope => $telescope);
    die 'Base ouput directory does not exist'
        unless -d $basedir;
    my $utdir = File::Spec->catdir(
        $basedir,
        $utdate->strftime('%Y'),
        $utdate->strftime('%m'),
        $utdate->strftime('%d'));
    return $self->_write_not_found()
        unless -d $utdir;

    my $pathname = File::Spec->catfile($utdir, $filename);
    return $self->_write_not_found() unless -e $pathname;

    my $fh = IO::File->new($pathname, 'r');
    die 'Failed to open image file' unless defined $fh;
    $fh->read(my $buff, 10000000);
    $fh->close();

    # Check the MD5 sum is as requested, so that we can specify a long
    # cache expiry time.
    my $md5sum_file = md5_hex($buff);
    return $self->_write_not_found()
        unless ($md5sum_request eq $md5sum_file);

    print $q->header(
        -type => 'image/png',
        -expires => '+1d',
    );

    print $buff;
}

1;

__END__

=head1 SEE ALSO

C<OMP::CGIComponent::NightRep>

=head1 AUTHOR

Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2004 Particle Physics and Astronomy Research Council.
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
