package OMP::CGIPage::NightRep;

=head1 NAME

OMP::CGIPage::NightRep - Disply complete observation log web pages

=head1 SYNOPSIS

    use OMP::CGIPage::NightRep;

=head1 DESCRIPTION

This module provides routines for displaying complete web pages
for viewing observation logs and submitting observation log
comments.

=cut

use strict;
use warnings;

use CGI;
use CGI::Carp qw/fatalsToBrowser/;
use Net::Domain qw/hostfqdn/;
use Time::Piece;
use Time::Seconds qw/ONE_DAY/;

use OMP::CGIComponent::NightRep;
use OMP::CGIComponent::IncludeFile;
use OMP::CGIComponent::ITCLink;
use OMP::CGIComponent::MSB;
use OMP::CGIComponent::Search;
use OMP::CGIComponent::ShiftLog;
use OMP::CGIComponent::Weather;
use OMP::Config;
use OMP::Constants;
use OMP::DateTools;
use OMP::DB::MSB;
use OMP::DB::MSBDone;
use OMP::DB::Sched;
use OMP::General;
use OMP::Info::Comment;
use OMP::Info::Obs;
use OMP::Info::Obs::TimeGap;
use OMP::Info::ObsGroup;
use OMP::NightRep;
use OMP::DB::Obslog;
use OMP::Query::Obslog;
use OMP::DB::Preview;
use OMP::Query::Preview;
use OMP::DB::Project;
use OMP::DB::Archive;
use OMP::Error qw/:try/;

use base qw/OMP::CGIPage/;

our $VERSION = '2.000';

=head1 Routines

=over 4

=item B<file_comment>

Creates a page with a form for filing a comment.

    $page->file_comment([$projectid]);

The parameter C<$projectid> is given from C<fbobscomment.pl>
but not C<staffobscomment.pl>.

=cut

sub file_comment {
    my $self = shift;
    my $projectid = shift;

    my $q = $self->cgi;

    my $comp = OMP::CGIComponent::NightRep->new(page => $self);

    my $messages;
    if ($q->param('submit_comment')) {
        # Insert the comment into the database.
        my $response = $comp->obs_add_comment();
        $messages = $response->{'messages'};

        # obs_add_comment always returns a fixed message.  Instead of showing
        # it, redirect to reload this page.
        return $self->_write_redirect($self->url_absolute());
    }

    # Get the Info::Obs object
    my $obs = $comp->cgi_to_obs();

    # Verify that we do have an Info::Obs object.
    if (! UNIVERSAL::isa($obs, "OMP::Info::Obs")) {
        throw OMP::Error::BadArgs("Must supply an Info::Obs object");
    }

    if (defined($projectid)
            && $obs->isScience
            && (lc($obs->projectid) ne lc($projectid))) {
        throw OMP::Error("Observation does not match project " . $projectid);
    }

    return {
        target => $self->url_absolute(),
        obs => $obs,
        is_time_gap => scalar eval {$obs->isa('OMP::Info::Obs::TimeGap')},
        status_class => \%OMP::Info::Obs::status_class,
        messages => $messages,
        %{$comp->obs_comment_form($obs, $projectid)},
    };
}

=item B<list_observations_txt>

Create a page containing only a text-based listing of observations.

=cut

sub list_observations_txt {
    my $self = shift;
    my $projectid = shift;

    my $proj;
    try {
        $proj = OMP::DB::Project->new(DB => $self->database, ProjectID => $projectid)->projectDetails();
    }
    otherwise {
        my $E = shift;
        croak "Unable to retrieve the details of this project:\n$E";
    };

    my $telescope = $proj->telescope;

    my $query = $self->cgi;

    my $comp = OMP::CGIComponent::NightRep->new(page => $self);

    print $query->header(-type => 'text/plain', -charset => 'utf-8');

    my $obsgroup;
    try {
        $obsgroup = $comp->cgi_to_obsgroup(
            projid => $projectid,
            inccal => 1,
            timegap => 0,
        );
    }
    catch OMP::Error with {
        my $Error = shift;
        my $errortext = $Error->{'-text'};
        print "Error: $errortext\n";
    }
    otherwise {
        my $Error = shift;
        my $errortext = $Error->{'-text'};
        print "Error: $errortext\n";
    };

    try {
        $comp->obs_table_text(
            $obsgroup,
            showcomments => 1,
            ascending => 1,
            projectid => $projectid,
            telescope => $telescope);
    }
    catch OMP::Error with {
        my $Error = shift;
        my $errortext = $Error->{'-text'};
        print "Error: $errortext<br>\n";
    }
    otherwise {
        my $Error = shift;
        my $errortext = $Error->{'-text'};
        print "Error: $errortext<br>\n";
    };
}

=item B<night_report>

Create a page summarizing activity for a particular night.

    $page->night_report($self);

=cut

sub night_report {
    my $self = shift;
    my $q = $self->cgi();

    my $comp = OMP::CGIComponent::NightRep->new(page => $self);
    my $weathercomp = OMP::CGIComponent::Weather->new(page => $self);
    my $includecomp = OMP::CGIComponent::IncludeFile->new(page => $self);
    my $itclink = OMP::CGIComponent::ITCLink->new(page => $self);

    my $delta;
    my $utdate;
    my $utdate_end;

    if ($q->param('utdate_end')) {
        # Get delta and start UT date from multi night form
        $utdate = OMP::DateTools->parse_date(scalar $q->param('utdate'));
        $utdate_end = OMP::DateTools->parse_date(scalar $q->param('utdate_end'));

        # Croak if date format is wrong
        croak("The date string provided is invalid.  Please provide dates in the format of YYYY-MM-DD")
            if (! $utdate or ! $utdate_end);

        # Derive delta from start and end UT dates
        $delta = $utdate_end - $utdate;
        $delta = $delta->days + 1;    # Need to add 1 to our delta
                                      # to include last day
    }
    else {
        $utdate = $self->_get_utdate();

        # Get delta from URL
        if ($q->param('delta')) {
            my $deltastr = $q->param('delta');
            if ($deltastr =~ /^(\d+)$/a) {
                $delta = $1;
            }
            else {
                croak("Delta [$deltastr] does not match the expect format so we are not allowed to untaint it!");
            }

            # We need an end date for display purposes
            $utdate_end = $utdate;

            # Subtract delta (days) from date if we have a delta
            $utdate = $utdate_end - ($delta - 1) * ONE_DAY;
        }
    }

    # Get the telescope from the URL
    my $tel = $self->_get_telescope('tel')
        or return $self->_write_error('No telescope selected.');

    # Setup our arguments for retrieving night report
    my %args = (
        date => $utdate->ymd,
        telescope => $tel,
        include_private_comments => 1,
    );
    ($delta) and $args{delta_day} = $delta;

    # Get the night report
    my $arcdb = OMP::DB::Archive->new(
        DB => $self->database_archive,
        FileUtil => $self->fileutil);
    my $nr = OMP::NightRep->new(DB => $self->database, ADB => $arcdb, %args);

    return $self->_write_error(
            'No observing report available for ' . $utdate->ymd . ' at ' . $tel . '.')
        unless $nr;

    my $sched_night = undef;
    if (1 == $nr->delta_day) {
        my $pdb = OMP::DB::Preview->new(DB => $self->database);
        $nr->obs->attach_previews($pdb->queryPreviews(OMP::Query::Preview->new(HASH => {
            telescope => $tel,
            date => {value => $utdate->ymd(), delta => 1},
            size => 64,
        })));

        my $sdb = OMP::DB::Sched->new(DB => $self->database);
        my $sched = $sdb->get_schedule(
            tel => 'JCMT',
            date => $utdate);
        my $sched_nights = $sched->nights;
        if ((defined $sched_nights) and (1 == scalar @$sched_nights)) {
            $sched_night = $sched_nights->[0];
        }
    }

    # NOTE: disabled as we currently don't have fits in the OMP.
    # taufits: $weathercomp->tau_plot($utdate),
    # NOTE: also currently disabled?
    # wvm: $weathercomp->wvm_graph($utdate->ymd),
    # zeropoint: $weathercomp->zeropoint_plot($utdate),
    # NOTE: currently not working:
    # ['seeing', 'UKIRT K-band seeing', $weathercomp->seeing_plot($utdate)],
    # ['extinction', 'UKIRT extinction', $weathercomp->extinction_plot($utdate)],

    $self->_sidebar_night($tel, $utdate) unless $delta;

    return {
        target_base => $q->url(-absolute => 1),

        telescope => $tel,

        ut_date => $utdate,
        ut_date_end => $utdate_end,
        ut_date_delta => $delta,

        night_report => $nr,
        sched_night => $sched_night,

        dq_nightly_html => ($tel ne 'JCMT' || $delta
            ? undef
            : $includecomp->include_file_ut('dq-nightly', $utdate->ymd())
        ),

        weather_plots => ($delta ? undef : [
            grep {$_->[2]}
            ['meteogram', 'EAO meteogram', $weathercomp->meteogram_plot($utdate)],
            ['opacity', 'Maunakea opacity', $weathercomp->opacity_plot($utdate)],
            ['forecast', 'MKWC forecast', $weathercomp->forecast_plot($utdate)],
        ]),

        itclink => $itclink,
    };
}

=item B<projlog_content>

Display information about observations for a project on a particular
night.

    $page->projlog_content($projectid);

=cut

sub projlog_content {
    my $self = shift;
    my $projectid = shift;

    my $q = $self->cgi;

    my $comp = OMP::CGIComponent::NightRep->new(page => $self);
    my $msbcomp = OMP::CGIComponent::MSB->new(page => $self);
    my $shiftcomp = OMP::CGIComponent::ShiftLog->new(page => $self);
    my $weathercomp = OMP::CGIComponent::Weather->new(page => $self);
    my $includecomp = OMP::CGIComponent::IncludeFile->new(page => $self);

    my $utdatestr = $self->decoded_url_param('utdate');
    my $no_retrieve = $self->decoded_url_param('noretrv');

    my $inccal = $q->param('inccal') // 0;

    my $utdate;

    # Untaint the date string
    if ($utdatestr =~ /^(\d{4}-\d{2}-\d{2})$/a) {
        $utdate = $1;
    }
    else {
        croak("UT date string [$utdate] does not match the expect format so we are not allowed to untaint it!");
    }

    # Get a project object for this project
    my $proj;
    try {
        $proj = OMP::DB::Project->new(DB => $self->database, ProjectID => $projectid)->projectDetails();
    }
    otherwise {
        my $E = shift;
        croak "Unable to retrieve the details of this project:\n$E";
    };

    my $telescope = $proj->telescope;

    # Perform any actions on the MSB.
    my $response = $msbcomp->msb_action(projectid => $projectid);
    my $errors = $response->{'errors'};
    my $messages = $response->{'messages'};
    return $self->_write_error(@$errors) if scalar @$errors;

    my $comment_msb_id_fields = undef;

    # Make a form for submitting MSB comments if an 'Add Comment'
    # button was clicked
    if ($q->param("submit_add_comment")) {
        $comment_msb_id_fields = {
            checksum => scalar $q->param('checksum'),
            transaction => scalar $q->param('transaction'),
        };
    }

    # Get code for tau plot display
    # NOTE: disabled as we currently don't have fits in the OMP.
    # my $plot_html = $weathercomp->tau_plot($utdate);

    # Make links for retrieving data
    # To keep people from following the links before the data are available
    # for download gray out the links if the current UT date is the same as the
    # UT date of the observations
    my $today = OMP::DateTools->today(1);
    my $retrieve_date = undef;
    unless ($no_retrieve) {
        if ($today->ymd =~ $utdate) {
            $retrieve_date = $today + ONE_DAY;
        }
        else {
            $retrieve_date = 'now';
        }
    }

    # Display MSBs observed on this date
    my $observed = OMP::DB::MSBDone->new(
        DB => $self->database,
        ProjectID => $projectid,
    )->observedMSBs(
        date => $utdate,
        comments => 0,
        transactions => 1,
    );

    my $msbdb = OMP::DB::MSB->new(DB => $self->database, ProjectID => $projectid);
    my $sp = $msbdb->getSciProgInfo();
    my $msb_info = $msbcomp->msb_comments($observed, $sp);

    # Display observation log
    my $obs_summary = undef;
    try {
        # Want to go to files on disk
        my $arcdb = OMP::DB::Archive->new(
            DB => $self->database_archive,
            FileUtil => $self->fileutil);
        $arcdb->search_files();

        my $grp = OMP::Info::ObsGroup->new(
            DB => $self->database,
            ADB => $arcdb,
            projectid => $projectid,
            date => $utdate,
            inccal => $inccal,
        );

        if ($grp->numobs > 0) {
            my $pdb = OMP::DB::Preview->new(DB => $self->database);
            $grp->attach_previews($pdb->queryPreviews(OMP::Query::Preview->new(HASH => {
                telescope => $telescope,
                date => {value => $utdate, delta => 1},
                size => 64,
            })));

            my $nr = OMP::NightRep->new(
                DB => $self->database,
                telescope => $telescope);
            $obs_summary = $nr->get_obs_summary(obsgroup => $grp);
        }
    }
    otherwise {
    };

    return {
        target => $self->url_absolute(),
        project => $proj,
        utdate => $utdate,
        telescope => $telescope,
        retrieve_date => $retrieve_date,
        inccal => $inccal,

        obs_summary => $obs_summary,

        shift_log_comments => $shiftcomp->get_shift_comments({
            date => $utdate,
            telescope => $telescope,
        }),

        dq_nightly_html => $includecomp->include_file_ut(
            'dq-nightly', $utdate, projectid => $projectid),

        msb_info => $msb_info,
        comment_msb_id_fields => $comment_msb_id_fields,
        comment_msb_messages => $messages,

        weather_plots => [
            grep {$_->[2]}
            ['wvm', 'WVM graph', $weathercomp->wvm_graph($utdate)],
        ],
        };
}

=item B<obslog_search>

Creates a page for searching obslog entries.

=cut

sub obslog_search {
    my $self = shift;

    my $q = $self->cgi;
    my $search = OMP::CGIComponent::Search->new(page => $self);

    # To allow us to characterize log entries, note the lowest status
    # constant corresponding to a type of time gap.
    my $min_status_timegap = OMP__TIMEGAP_INSTRUMENT;

    my $telescope = 'JCMT';
    my $message = undef;
    my $result = undef;
    my %values = (
        type => '',
        active => 1,
        text => '',
        text_boolean => 0,
        period => 'arbitrary',
        userid => '',
        mindate => '',
        maxdate => '',
        days => '',
    );

    if ($q->param('search')) {
        %values = (
            %values,
            $search->read_search_common(),
            $search->read_search_sort(),
        );

        ($message, my $hash) = $search->common_search_hash(\%values, 'commentauthor');

        my $active = $values{'active'} = ($q->param('active') ? 1 : 0);
        if ($active) {
            $hash->{'obsactive'} = {boolean => 1};
        }

        my $type = $values{'type'} = $q->param('type');
        if ($type) {
            if ($type eq 'gap') {
                $hash->{'commentstatus'} = {min => $min_status_timegap};
            }
            else {
                $hash->{'EXPR__CS'} = {not => {commentstatus => {min => $min_status_timegap}}};
            }
        }

        unless (defined $message) {
            $hash->{'telescope'} = $telescope;
            my $query = OMP::Query::Obslog->new(HASH => $hash);

            my $odb = OMP::DB::Obslog->new(DB => $self->database);
            $result = $search->sort_search_results(
                \%values,
                'startobs',
                [map {
                    $_->is_time_gap($_->status >= $min_status_timegap);
                    $_
                } $odb->queryComments($query, {allow_dateless => 1})]);

            $message = 'No matching observation log entries found.'
                unless scalar @$result;
        }
    }

    return {
        message => $message,
        form_info => {
            target => $self->url_absolute(),
            values => \%values,
        },
        log_entries => $result,
        telescope => $telescope,
    };
}

=item B<time_accounting>

Creates a page for confirming nightly time accounting.

=cut

sub time_accounting {
    my $self = shift;

    my $q = $self->cgi;
    my $comp = OMP::CGIComponent::NightRep->new(page => $self);

    my $tel = $self->_get_telescope()
        or return $self->_write_error('No telescope selected.');

    my $utdate = $self->_get_utdate();

    my $arcdb = OMP::DB::Archive->new(
        DB => $self->database_archive,
        FileUtil => $self->fileutil);
    my $nr = OMP::NightRep->new(
        DB => $self->database, ADB => $arcdb,
        date => $utdate, telescope => $tel,
        include_private_comments => 1);

    my $times = $nr->accounting(trace_observations => 1);
    my $warnings = delete $times->{$OMP::NightRep::WARNKEY} // [];

    my $timelostbyshift = $nr->timelostbyshift;

    my @all_shifts = qw/NIGHT EO DAY OTHER/;

    my %shift_added = map {$_ => 1} $q->multi_param('shift_extra');
    my $submitted = 0;
    foreach my $shift (@all_shifts) {
        $submitted = $shift_added{$shift} = 1 if $q->param('submit_add_' . $shift);
    }
    my @shifts = grep {
        $shift_added{$_}
        or exists $times->{$_}
        or (exists $timelostbyshift->{$_} and $timelostbyshift->{$_}->{'total'} > 0)
    } @all_shifts;

    # Add any additional shifts from the database.  (E.g. "UNKNOWN".)
    foreach my $shift (keys %$times, keys %$timelostbyshift) {
        push @shifts, $shift if defined $shift and $shift ne '' and not grep {$shift eq $_} @shifts;
    }

    my @result = map {
        $comp->time_accounting_shift(
            $nr->telescope,
            $_,
            $times->{$_},
            $timelostbyshift->{$_}->{'total'})
    } @shifts;

    my @errors = ();
    if ($submitted or $q->param('submit_confirm')) {
        push @errors, $comp->read_time_accounting_shift($_) foreach @result;
    }

    if ($q->param('submit_confirm')) {
        unless (scalar @errors) {
            push @errors, $comp->store_time_accounting($nr, \@result);
        }

        unless (scalar @errors) {
            $nr->mail_report if $q->param('send_mail');

            return $self->_write_redirect(
                sprintf '/cgi-bin/nightrep.pl?tel=%s&utdate=%s', $tel, $utdate->ymd);
        }
    }

    $self->_sidebar_night($tel, $utdate);

    return {
        telescope => $tel,
        ut_date => $utdate,
        target => $q->url(-absolute => 1, -query => 0),
        warnings => $warnings,
        errors => \@errors,
        shifts => \@result,
        shifts_extra => [keys %shift_added],
        shifts_other => [grep {my $x = $_; not grep {$_ eq $x} @shifts} @all_shifts],
        status_label => {
            %OMP::Info::Obs::status_label,
            %OMP::Info::Obs::TimeGap::status_label,
        },
    };
}

=item B<_get_telescope>

Read telescope CGI parameter.

=cut

sub _get_telescope {
    my $self = shift;
    my $param = shift // 'telescope';

    my $telstr = $self->cgi->param($param);

    # Untaint the telescope string
    if ($telstr) {
        if ($telstr =~ /^(UKIRT|JCMT)$/i) {
            return uc $1;
        }
        else {
            croak("Telescope string [$telstr] does not match the expect format so we are not allowed to untaint it!");
        }
    }

    return undef;
}

=item B<_get_utdate>

Read utdate CGI parameter.

=cut

sub _get_utdate {
    my $self = shift;
    my $param = shift // 'utdate';

    my $datestr = $self->cgi->param($param);

    my $utdate;
    if ($datestr) {
        $utdate = OMP::DateTools->parse_date($datestr);

        # Croak if date format is wrong
        croak("The date string provided is invalid.  Please provide dates in the format of YYYY-MM-DD")
            unless $utdate;
    }
    else {
        # No UT date in URL.  Use current date.
        $utdate = OMP::DateTools->today(1);
    }

    return $utdate;
}

1;

__END__

=back

=head1 SEE ALSO

C<OMP::CGIComponent::NightRep>, C<OMP::CGIComponent::MSB>,
C<OMP::CGIComponent::ShiftLog>, C<OMP::CGIComponent::Weather>

=head1 AUTHORS

Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>,
Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002-2004 Particle Physics and Astronomy Research Council.
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
