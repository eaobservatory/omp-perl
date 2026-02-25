package OMP::CGIComponent::Fault;

=head1 NAME

OMP::CGIComponent::Fault - Components for fault system web pages

=head1 SYNOPSIS

    use OMP::CGIComponent::Fault;

    $comp = OMP::CGIComponent::Fault->new(page => $fault_page);

=head1 DESCRIPTION

Provide methods to generate and display components of fault system web pages.
Methods are also provided for parsing input taken forms displayed on the
web pages.  This class inherits from C<OMP::CGIComponent>.

=cut

use 5.006;
use strict;
use warnings;
use Carp;

use OMP::Config;
use OMP::Constants qw/:faultresponse/;
use OMP::DB::MSBDone;
use OMP::Display;
use OMP::DateTools;
use OMP::General;
use OMP::Error qw/:try/;
use OMP::Fault;

use base qw/OMP::CGIComponent/;

our $VERSION = '2.000';

=head1 METHODS

=head2 Content Creation and Display Methods

=over 4

=item B<fault_table>

Put a fault into a an HTML table

    $comp->fault_table($fault, no_edit => 1)

Takes an C<OMP::Fault> object as the first argument and optional
arguments which may contain "no_edit".  "no_edit"
displays the fault without links for updating the text and details,
and without the status update form.

=cut

sub fault_table {
    my $self = shift;
    my $fault = shift;
    my %opt = @_;

    my $q = $self->cgi;

    my $noedit;
    if (defined $opt{'no_edit'}) {
        $noedit = $opt{'no_edit'};
    }

    # Get available statuses
    my @statuses;
    unless ($noedit) {
        @statuses = $self->get_status_labels($fault);
    }

    my %shifts = $fault->shiftTypes();

    return {
        fault => $fault,
        display_date_local => sub {
            my $epoch = $_[0]->epoch;
            my $date = localtime($epoch);
            return OMP::DateTools->display_date($date);
        },
        system_label => $fault->getCategorySystemLabel(),
        entry_name => $fault->getCategoryEntryName(),
        allow_edit => ! $noedit,
        target => $self->page->url_absolute(),
        statuses => \@statuses,
        has_shift_type => !!%shifts,
        category_is_telescope => $fault->faultIsTelescope(),
    };
}

=item B<query_fault_form>

Create and display a form for querying faults.

    $comp->query_fault_form($category, [$hidesystype]);

If the optional argument is true, no fields are provided for selecting
system/type (useful for non-category specific fault queries).

=cut

sub query_fault_form {
    my $self = shift;
    my $category = shift;
    my $hidefields = shift;

    my $q = $self->cgi;

    my @systems;
    my @types;
    my @locations;
    my $has_location = 0;

    if (! $hidefields) {
        my $sort = (OMP::Fault->getCategorySystemLabel($category) eq 'Vehicle')
            ? (sub {$a->[1] <=> $b->[1]})
            : (sub {$a->[1] cmp $b->[1]});

        my $systems = OMP::Fault->faultSystems($category);
        @systems = sort $sort map {[$_, $systems->{$_}]} keys %$systems;

        my $hidden_systems = OMP::Fault->faultSystems($category, only_hidden => 1);
        if (scalar %$hidden_systems) {
            push @systems, [];
            push @systems, sort $sort map {[$_, $hidden_systems->{$_}]} keys $hidden_systems;
        }

        my $types = OMP::Fault->faultTypes($category);
        @types = sort {$a->[1] cmp $b->[1]} map {[$_, $types->{$_}]} keys %$types;

        $has_location = OMP::Fault->faultHasLocation($category);
        if ($has_location) {
            my $locations = OMP::Fault->faultLocation($category);
            @locations = sort {$a->[1] cmp $b->[1]}
                map {[$_, $locations->{$_}]} keys %$locations;
        }
    }

    my @status = (
        [all_open => 'All open'],
        [all_closed => 'All closed'],
        [non_duplicate => 'Non-duplicate'],
        [],
        _get_status_labels_by_name($category),
    );

    return {
        category => $category,
        target => $q->url(-absolute => 1, -query => 0),
        show_id_fields => ! $hidefields,
        show_timelost => OMP::Fault->faultCanLoseTime($category),
        show_show_affected => OMP::Fault->faultCanAssocProjects($category),
        actions => [
            [response => 'responded to'],
            [file => 'filed'],
            [activity => 'with any activity'],
            [occurred => 'which occurred'],
        ],
        text_searches => [
            'text',
            'subject',
            'both',
        ],
        system_label => OMP::Fault->getCategorySystemLabel($category),
        entry_name => OMP::Fault->getCategoryEntryName($category),
        systems => \@systems,
        types => \@types,
        has_location => $has_location,
        locations => \@locations,
        statuses => \@status,
        values => {
            action => (scalar $q->param('action') // 'activity'),
            period => (scalar $q->param('period') // 'arbitrary'),
            timezone => (scalar $q->param('timezone') // 'HST'),
            text_search => (scalar $q->param('text_search') // 'both'),
            map {$_ => scalar $q->param($_)}
                qw/userid mindate maxdate days system type status location
                timelost show_affected urgent chronic summary
                text text_boolean/,
        },
    };
}

=item B<file_fault_form>

Create a form for submitting fault details.  This subroutine takes its arguments in
the form of a hash containing the following keys:

=over 4

=item fault

An C<OMP::Fault> object

=back

The fault key is optional.  If present, the details of the fault object will
be used to provide defaults for all of the fields This allows this form to be
used for editing the details of an existing fault.

    $comp->file_fault_form($category, fault => $fault_object);

=cut

sub file_fault_form {
    my $self = shift;
    my $category = shift;
    my %args = @_;
    my $fault = $args{fault};
    my $q = $self->cgi;

    my $has_location = OMP::Fault->faultHasLocation($category);

    # Create values and labels for the popup_menus
    my @systems;
    {
        # TODO: have OMP::Fault return an ordered structure instead?
        my $systems = OMP::Fault->faultSystems($category);

        my $sort = (OMP::Fault->getCategorySystemLabel($category) eq 'Vehicle')
            ? (sub {$a->[1] <=> $b->[1]})
            : (sub {$a->[1] cmp $b->[1]});

        @systems = sort $sort
            map {[$_, $systems->{$_}]}
            keys %$systems;
    }

    my $types = OMP::Fault->faultTypes($category);
    my @types = sort {$a->[1] cmp $b->[1]} map {[$_, $types->{$_}]} keys %$types;

    my @statuses = _get_status_labels_by_name($category);

    # Location (for "Safety" category).
    my @locations;
    if ($has_location) {
        my $locations = OMP::Fault->faultLocation($category);
        @locations = sort {$a->[1] cmp $b->[1]}
            map {[$_, $locations->{$_}]} keys %$locations;
    }

    # Set defaults.  There's probably a better way of doing what I'm about
    # to do...
    my %defaults;
    my @projects = ();
    my @warnings = ();

    unless (defined $fault) {
        %defaults = (
            system => undef,
            type => undef,
            location => undef,
            status => OMP::Fault->faultInitialStatus($category),
            loss => undef,
            loss_unit => 'min',
            time => undef,
            tz => 'HST',
            subject => undef,
            message => undef,
            assoc2 => undef,
            urgency => undef,
            condition => undef,
            shifttype => undef,
            remote => undef,
        );

        # If we're in a category that allows project association create a
        # checkbox group for specifying an association with projects.
        # We don't want this checkbox group if this form is being used for editing a fault.
        if (OMP::Fault->faultCanAssocProjects($category)) {
            # Values for checkbox group will be tonights projects
            my $aref = OMP::DB::MSBDone->new(DB => $self->database)->observedMSBs(
                usenow => 1,
                comments => 0,
            );

            if (@$aref[0]) {
                my %projects;
                my %badproj;    # used to limit error message noise
                for (@$aref) {
                # Make sure to only include projects associated with the current
                    # telescope category
                    my @instruments = split(/\W/, $_->instrument);
                    # this may fail if an unexpected instrument turns up
                    my $tel;
                    try {
                        $tel = OMP::Config->inferTelescope('instruments', @instruments);
                    }
                    catch OMP::Error::BadCfgKey with {
                        my $key = $_->{projectid} . join("", @instruments);
                        unless (exists $badproj{$key}) {
                            push @warnings,
                                  "Project $_->{projectid} used an instrument "
                                . join(",", @instruments)
                                . " that has no associated telescope.";
                            $badproj{$key} ++;
                        }
                    };
                    next unless defined $tel;

                    $projects{$_->projectid} = $_->projectid
                        unless ($tel !~ /$category/i);
                }

                my %assoc = map {$_ => 1} $q->multi_param('assoc');
                @projects = map {[$_, exists $assoc{$_} ? 1 : 0]} sort keys %projects;
            }
        }
    }
    else {
        # We have a fault object so use it's details as our defaults
        my $response = $fault->responses->[0];

        # Get the fault date (if any)
        my $faultdate = $response->faultdate;

        # Convert faultdate to local time
        if ($faultdate) {
            my $epoch = $faultdate->epoch;
            $faultdate = localtime($epoch);
            $faultdate = $faultdate->strftime('%Y-%m-%dT%T');
        }

        # Is this fault marked urgent?
        my $urgent = ($fault->isUrgent ? "urgent" : undef);

        # Is this fault marked chronic?
        my $chronic = ($fault->isChronic ? "chronic" : undef);

        # Projects associated with this fault
        my @assoc = $fault->projects;

        my $message = OMP::Display->prepare_edit_text($response);

        %defaults = (
            system => $fault->system,
            status => $fault->status,
            location => $fault->location,
            type => $fault->type,
            loss => $response->timelost * 60.0,
            loss_unit => 'min',
            time => $faultdate,
            tz => 'HST',
            subject => $fault->subject,
            message => $message,
            assoc2 => join(' ', @assoc),
            urgency => $urgent,
            condition => $chronic,
            shifttype => $response->shifttype,
            remote => $response->remote,
        );
    }

    # Fields in the query param stack will override normal defaults
    my %condition_checked = map {$_ => 1} $q->multi_param('condition');
    for (keys %defaults) {
        if ($_ eq 'urgency') {
            $defaults{$_} = 1 if exists $condition_checked{'urgent'};
        }
        elsif ($_ eq 'condition') {
            $defaults{$_} = 1 if exists $condition_checked{'chronic'};
        }
        elsif ($q->param($_)) {
            $defaults{$_} = $q->param($_);
        }
    }

    my %shifts = OMP::Fault->shiftTypes($category);
    my @shifts = map {[$_ => $shifts{$_}]} sort keys %shifts;

    my %remotes = OMP::Fault->remoteTypes($category);
    my @remotes = map {[$_ => $remotes{$_}]} sort keys %remotes;

    my @conditions = (['urgent', 'Urgent', 'urgency']);
    push @conditions, (['chronic', 'Chronic', 'condition'])
        if defined $fault;

    # TODO: use OMP::Fault for the "severity level" logic?
    my $sys_label = OMP::Fault->getCategorySystemLabel($category);
    my $sys_text = lc $sys_label;
    $sys_text .= ' level' if $sys_text eq 'severity';

    return {
        target => $self->page->url_absolute(),
        fault => $fault,
        has_location => $has_location,
        has_time_loss => OMP::Fault->faultCanLoseTime($category),
        has_time_occurred => OMP::Fault->faultHasTimeOccurred($category),
        has_project_assoc => OMP::Fault->faultCanAssocProjects($category),
        entry_name => OMP::Fault->getCategoryEntryName($category),
        category_is_telescope => OMP::Fault->faultIsTelescope($category),
        system_label => $sys_label,
        system_description => $sys_text,
        systems => \@systems,
        types => \@types,
        locations => \@locations,
        statuses => \@statuses,
        shifts => \@shifts,
        remotes => \@remotes,
        conditions => \@conditions,
        projects => \@projects,
        values => \%defaults,
        warnings => \@warnings,
    };
}

=item B<response_form>

Create and display a form for submitting or editing a response.

    $comp->response_form(
        respid => $respid,
        fault => $fault_obj,
    );

Accepts arguments in hash format.  The following keys will be used:

=over 4

=item fault

An C<OMP::Fault> object.  This key is always required.

=item respid

The ID of a response to edit.  This key is optional.

=back

If the response key is present, the form will be set up for editing
the response object with the id provided by the key, otherwise the
form is set up for creating a new response.

=cut

sub response_form {
    my $self = shift;
    my %args = @_;
    my $fault = $args{fault};
    my $respid = $args{respid};
    my $q = $self->cgi;

    # Croak if we didn't get a fault object
    croak "Must provide a fault object\n"
        unless UNIVERSAL::isa($fault, "OMP::Fault");

    my @statuses = $self->get_status_labels($fault);

    # Set defaults.
    my %defaults;
    my $resp = undef;
    if ($respid) {
        # Setup defaults for response editing
        $resp = $fault->getResponse($respid);

        my $text = OMP::Display->prepare_edit_text($resp);

        my $faultdate = $resp->faultdate;
        if ($faultdate) {
            my $epoch = $faultdate->epoch;
            $faultdate = localtime($epoch);
            $faultdate = $faultdate->strftime('%Y-%m-%dT%T');
        }

        my $timelost = $resp->timelost;
        $timelost *= 60.0 if defined $timelost;

        %defaults = (
            text => $text,
            flag => $resp->flag,
            loss => $timelost,
            loss_unit => 'min',
            time => $faultdate,
            tz => 'HST',
            shifttype => $resp->shifttype,
            remote => $resp->remote,
            submitlabel => "Submit changes",
        );
    }
    else {
        %defaults = (
            text => '',
            status => $fault->status,
            submitlabel => "Submit response",
        );
    }

    # Param list values take precedence
    for (qw/text status flag loss loss_unit time tz shifttype remote/) {
        if ($q->param($_)) {
            $defaults{$_} = $q->param($_);
        }
    }

    my %shifts = $fault->shiftTypes();
    my %remotes = $fault->remoteTypes();

    return {
        target => $self->page->url_absolute(),
        statuses => \@statuses,
        response => $resp,
        values => \%defaults,
        flags => [
            [OMP__FR_INVALUABLE, 'Invaluable'],
            [OMP__FR_VALUABLE, 'Valuable'],
            [OMP__FR_NORMAL, 'Normal'],
            [OMP__FR_REDUNDANT, 'Redundant'],
            [OMP__FR_HIDDEN, 'Hidden'],
        ],
        has_time_loss => $fault->faultCanLoseTime(),
        has_time_occurred => $fault->faultHasTimeOccurred(),
        shifts => [map {[$_ => $shifts{$_}]} sort keys %shifts],
        remotes => [map {[$_ => $remotes{$_}]} sort keys %remotes],
    };
}

=item B<show_faults>

Show a list of faults.

    $comp->show_faults(
        faults => $faultgroup,
        orderby => 'response',
        descending => 1,
        url => "fbfault.pl",
        category => $category,
    );

Takes the following key/value pairs as arguments:

=over 4

=item faults

An C<OMP::Fault::Group> object containing the faults to show.

=item descending

If true faults are listed in descending order.

=item url

The absolute or relative path to the script to be
used for the view/respond link.

=item orderby

Should be either 'response' (to sort by date of
latest response) 'filedate', 'timelost' (by amount
of time lost) or 'relevance'.

=item category

The category name, if a search has been performed for a particular
category of faults.  If "ANYCAT" then a category column should be displayed.

=back

Only the B<faults> key is required.

=cut

sub show_faults {
    my $self = shift;
    my %args = @_;

    my $stats = $args{faults};
    my $descending = $args{descending};
    my $url = $args{url} || 'viewfault.pl';
    my $category = $args{'category'};

    my $q = $self->cgi;

    # Generate stats so we can decide to show fields like "time lost"
    # only if any faults have lost time
    my @faults = $stats->faults;

    my $order = $args{'orderby'};

    if ($order && lc $order eq 'faulttime') {
        @faults = @{_sort_by_fault_time(\@faults, $descending)};
    }
    else {
        my %sort = (
            'response' => sub {
                $a->responses->[-1]->date->epoch
                <=>
                $b->responses->[-1]->date->epoch
            },
            'timelost' => sub {
                $a->timelost <=> $b->timelost
            },
            'relevance' => sub {
                $a->relevance() <=> $b->relevance()
            },
        );

        my $sort;
        $sort = $sort{$order}
            if exists $sort{$order};

        @faults = sort $sort @faults
            if $sort;

        @faults = reverse @faults
            if $descending;
    }

    return {
        show_cat => ($category eq 'ANYCAT'),
        show_location => (
            ($category ne 'ANYCAT')
            and OMP::Fault->faultHasLocation($category)),
        show_time_lost => ($stats->timelost > 0),
        show_projects => $args{'show_affected'},
        faults => \@faults,
        view_url => ($url . (($url =~ /\?/) ? '&' : '?') . 'fault='),
        system_label => OMP::Fault->getCategorySystemLabel($category),
    };
}

=item B<category_title>

Return the name of a category, suitable for including in a page title.

=cut

sub category_title {
    my $self = shift;
    my $cat = shift;

    return 'All Faults' if 'ANYCAT' eq uc $cat;

    return OMP::Fault->getCategoryFullName($cat);
}

=item B<parse_file_fault_form>

Take the arguments from the fault filing form and parse them so they
can be used to create the fault and fault response objects.

    $comp->parse_file_fault_form($category);

Returns the following keys:

    subject, faultdate, timelost, system, type, status, urgency,
    projects, text, remote, shifttype

=cut

sub parse_file_fault_form {
    my $self = shift;
    my $category = shift;

    my $q = $self->cgi;

    my %parsed = (
        subject => scalar $q->param('subject'),
        type => scalar $q->param('type'),
        status => scalar $q->param('status'),
        $self->parse_form_common($category),
    );

    if (OMP::Fault->faultHasLocation($category)) {
        $parsed{'location'} = $q->param('location');
    }
    $parsed{'system'} = $q->param('system');

    # Determine urgency and condition
    my @checked = $q->multi_param('condition');
    $parsed{urgency} = OMP::Fault::URGENCY_NORMAL();
    $parsed{condition} = OMP::Fault::CONDITION_NORMAL();

    for (@checked) {
        $parsed{urgency} = OMP::Fault::URGENCY_URGENT() if $_ =~ /urgent/i;
        $parsed{condition} = OMP::Fault::CONDITION_CHRONIC() if $_ =~ /chronic/i;
    }

    # Get the associated projects
    if ($q->param('assoc') or $q->param('assoc2')) {
        my @assoc = $q->multi_param('assoc');

        # Strip out commas and seperate on spaces
        my $assoc2 = $q->param('assoc2');
        $assoc2 =~ s/,/ /g;
        my @assoc2 = split(/\s+/, $assoc2);

        # Use a hash to eliminate duplicates
        my %projects = map {uc($_), undef} @assoc, @assoc2;
        $parsed{'projects'} = [sort keys %projects];
    }

    # The text.
    my $text = $q->param('message');

    $parsed{text} = OMP::Display->remove_cr($text);

    return %parsed;
}

=item B<parse_form_common>

Parse common elements of fault forms (for fault and response).

=cut

sub parse_form_common {
    my $self = shift;
    my $category = shift;

    my $q = $self->cgi;

    my %parsed = ();

    # Store time lost if defined (convert to hours)
    $parsed{timelost} = $q->param('loss')
        / (($q->param('loss_unit') eq 'hour') ? 1.0 : 60.0)
        if length($q->param('loss')) > 0;

    # If the time of fault was provided use it otherwise
    # do nothing
    if ($q->param('time')) {
        my $t;
        my $time = $q->param('time');

        # Define whether or not we have a local time
        my $islocal = ($q->param('tz') =~ /HST/ ? 1 : 0);
        my $utdate;

        if ($time =~ /^(\d\d*?)\W*(\d{2})$/a) {
            # Just the time (something like HH:MM)
            my $hh = $1;
            my $mm = $2;
            if ($islocal) {
                # Time is local
                # Using Time::Piece localtime() method until OMP::DateTools::today()
                # method supports local time
                my $today = localtime;
                $utdate = OMP::DateTools->parse_date($today->ymd . "T$hh:$mm", 1);
            }
            else {
                my $today = OMP::DateTools->today;
                $utdate = OMP::DateTools->parse_date("$today" . "T$hh:$mm");
            }
        }
        else {
            $utdate = OMP::DateTools->parse_date($time, $islocal);
        }

        # Store the faultdate
        if ($utdate) {
            my $gmtime = gmtime();

            # Subtract a day if date is in the future.
            ($gmtime->epoch < $utdate->epoch) and $utdate -= 86400;

            $parsed{faultdate} = $utdate;
        }
    }

    if (scalar $q->param('shifttype')) {
        $parsed{'shifttype'} = $q->param('shifttype');
    }
    else {
        $parsed{'shifttype'} = undef;
    }

    if (scalar $q->param('remote')) {
        $parsed{'remote'} = $q->param('remote');
    }
    else {
        $parsed{'remote'} = undef;
    }

    return %parsed;
}

=item B<category_hash>

Return a hash reference containing the name of the given category.

    \%hash = $comp->category_hash($category);

Returns an empty hash if the given category is 'ANYCAT' or if the only
argument is undef.

=cut

sub category_hash {
    my $self = shift;
    my $cat = shift;

    my %hash = ();

    if (defined $cat and $cat ne "ANYCAT") {
        $hash{'category'} = $cat;
    }

    return \%hash;
}

=item B<get_status_labels>

Given a L<OMP::Fault> object, return a list of [value, name]
pairs for use in an HTML selection menu.

    @statuses = $comp->get_status_labels($fault);

=cut

sub get_status_labels {
    my ($self, $fault) = @_;

    my $status = $fault->faultStatus;

    return sort {$a->[1] cmp $b->[1]} map {[$_, $status->{$_}]} keys %$status;
}

=back

=head2 Internal Methods

=over 4

=item B<_get_status_labels_by_name>

Given a fault category name, return a list of [value, name] pairs
for an HTML selection list).

All of the status types are returned for category of
C<ANYCAT>.  (It is somehwhat similar to I<get_status_labels>.)

    @statuses = _get_status_labels_by_name('OMP');

=cut

sub _get_status_labels_by_name {
    my ($cat) = @_;

    $cat = uc $cat;

    my $status;
    if ($cat =~ /^ANY/) {
        $status = OMP::Fault->faultStatus;
    }
    else {
        $status = OMP::Fault->faultStatus($cat);
    }

    return sort {$a->[1] cmp $b->[1]} map {[$_, $status->{$_}]} keys %$status;
}

=item B<_sort_by_fault_time>

Returns an array reference of faults sorted by fault times & file
dates, given an array reference of faults & optional truth value if to
sort in descending order.

    $faults = _sort_by_fault_time(\@fault, my $descending = 1);

Faults are first sorted by fault time, when available.  All the
remaining faults (without a fault date) are then sorted by the filing
date.

=cut

sub _sort_by_fault_time {
    my ($faults, $descend) = @_;

    my (@fault, @file);
    for my $f (@{$faults}) {
        if ($f->faultdate) {
            push @fault, $f;
        }
        else {
            push @file, $f;
        }
    }

    return [
        (sort {
            $b->faultdate <=> $a->faultdate
            ||
            $b->filedate <=> $a->filedate
        } @fault),
        (sort {
            $b->filedate <=> $a->filedate
        } @file)
    ] if $descend;

    return [
        (sort {
            $a->faultdate <=> $b->faultdate
            ||
            $a->filedate <=> $b->filedate
        } @fault),
        (sort {
            $a->filedate <=> $b->filedate
        } @file)
    ];
}

1;

__END__

=back

=head1 AUTHOR

Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>,

=head1 COPYRIGHT

Copyright (C) 2001-2004 Particle Physics and Astronomy Research Council.
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
