package OMP::CGIPage::Fault;

=head1 NAME

OMP::CGIPage::Fault - Display dynamic fault web pages

=head1 SYNOPSIS

    use OMP::CGIPage::Fault;
    $q = CGI->new();
    $page = OMP::CGIPage::Fault->new(cgi => $q);

=head1 DESCRIPTION

Construct and display complete web pages for viewing faults
and interacting with the fault system in general.  This class
inherits from C<OMP::CGIPage>.

=cut

use 5.006;
use strict;
use warnings;
use Carp;
our $VERSION = '2.000';

use File::Path 2.10 qw/make_path/;
use GD::Image;
use Image::ExifTool;
use IO::File;
use List::Util qw/max/;
use Time::Piece;
use Time::Seconds qw/ONE_DAY/;

use OMP::CGIComponent::Fault;
use OMP::CGIComponent::Project;
use OMP::Config;
use OMP::Constants qw/:faultresponse/;
use OMP::DateTools;
use OMP::NetTools;
use OMP::General;
use OMP::Fault;
use OMP::DB::Fault;
use OMP::Fault::Util;
use OMP::Display;
use OMP::Query::Fault;
use OMP::Fault::Response;
use OMP::User;
use OMP::DB::User;
use OMP::Error qw/:try/;

use base qw/OMP::CGIPage/;

=head1 METHODS

=head2 Utility methods

=over 4

=item B<fault_component>

Create a fault component object.

    $comp = $page->fault_component()

=cut

sub fault_component {
    my $self = shift;

    return OMP::CGIComponent::Fault->new(page => $self);
}

=back

=head2 General methods

=over 4

=item B<file_fault>

Creates a page with a form for for filing a fault, or submit a fault.

    $page->file_fault($category, undef);

=cut

sub file_fault {
    my $self = shift;
    my $category = shift;
    # Should be undef: my $fault = shift;

    my $q = $self->cgi;

    my $comp = $self->fault_component;

    my $page_title = sprintf '%s: File %s',
        $comp->category_title($category),
        OMP::Fault->getCategoryEntryName($category);

    unless ($q->param('submit_file')) {
        return {
            title => $page_title,
            missing_fields => undef,
            %{$comp->file_fault_form($category)},
        };
    }

    # Make sure all the necessary params were provided
    my %params = (
        subject => 'Subject',
        message => 'Fault report',
        type => 'Type',
        system => OMP::Fault->getCategorySystemLabel($category),
    );

    $params{'location'} = 'Location'
        if OMP::Fault->faultHasLocation($category);

    my @error;
    for (keys %params) {
        if (length($q->param($_)) < 1) {
            push @error, $params{$_};
        }
    }

    # Put the form back up if params are missing
    my @title;
    if ($error[0]) {
        return {
            title => $page_title,
            missing_fields => \@error,
            %{$comp->file_fault_form($category)},
        };
    }

    # Get the fault details
    my %faultdetails = $comp->parse_file_fault_form($category);

    my $resp = OMP::Fault::Response->new(
        author => $self->auth->user,
        text => $faultdetails{text},
        shifttype => $faultdetails{shifttype},
        remote => $faultdetails{remote},
    );

    # Create the fault object
    my $fault = OMP::Fault->new(
        category => $category,
        subject => $faultdetails{subject},
        system => $faultdetails{system},
        type => $faultdetails{type},
        status => $faultdetails{status},
        location => $faultdetails{location},
        urgency => $faultdetails{urgency},
        fault => $resp,
    );

    # The following are not always present
    $fault->projects($faultdetails{projects}) if $faultdetails{projects};

    $resp->faultdate($faultdetails{faultdate}) if $faultdetails{faultdate};

    $resp->timelost($faultdetails{timelost}) if $faultdetails{timelost};

    # Submit the fault the the database
    my $faultid;
    my @message = ();
    try {
        my $fdb = OMP::DB::Fault->new(DB => $self->database);
        $faultid = $fdb->fileFault($fault);
    }
    catch OMP::Error::MailError with {
        my $E = shift;
        push @message,
            "Fault has been filed, but an error has prevented it from being mailed:",
            "$E";
    }
    catch OMP::Error::FatalError with {
        my $E = shift;
        push @message,
            "An error has prevented the fault from being filed:",
            "$E";
    }
    otherwise {
        my $E = shift;
        push @message,
            "An error has occurred:",
            "$E";
    };

    return $self->_write_error(@message) if @message;

    return $self->_write_error('Fault filed without exception but no fault ID returned.')
        unless $faultid;

    return $self->_write_redirect("/cgi-bin/viewfault.pl?fault=$faultid");
}

=item B<query_fault_output>

Display output of a fault query

    $page->query_fault_output($category, undef);

=cut

sub query_fault_output {
    my $self = shift;
    my $category = shift;
    # Should be undef: my $fault = shift;

    my $q = $self->cgi;
    my $comp = $self->fault_component;

    my $title;
    my $t = gmtime;
    my %daterange;
    my $mindate;
    my $maxdate;
    my %hash;

    my %currenthash = (
        %{$comp->category_hash($category)},
        date => {delta => -14, value => $t->datetime},
    );

    # Setup an argument for use with the query_fault_form function
    my $hidefields = ($category ne 'ANYCAT' ? 0 : 1);

    my $is_initial_view = 0;
    my $is_preset_view = 0;
    my $entry_name = OMP::Fault->getCategoryEntryName($category);

    if ($q->param('search')) {
        # The 'Search' submit button was clicked
        %hash = %{$comp->category_hash($category)};

        if (defined $q->param('system')) {
            my $system = $q->param('system');
            $hash{'system'} = $system if $system !~ /any/;
        }

        if (defined $q->param('type')) {
            my $type = $q->param('type');
            $hash{'type'} = $type if $type !~ /any/;
        }

        # Return urgent or chronic faults only?
        if ($q->param('urgent')) {
            my %urgency = OMP::Fault->faultUrgency;
            $hash{'urgency'} = $urgency{'Urgent'};
        }

        if ($q->param('chronic')) {
            my %condition = OMP::Fault->faultCondition;
            $hash{'condition'} = $condition{'Chronic'};
        }

        if (defined $q->param('status')) {
            my $status = $q->param('status');
            my @cat_not_any = ($category eq 'ANYCAT') ? () : ($category);
            if ($status eq 'any') {
            }
            elsif ($status eq "all_closed") {
                # Do query on all closed statuses
                my %status = OMP::Fault->faultStatusClosed(@cat_not_any);
                $hash{'status'} = [values %status];
            }
            elsif ($status eq "all_open") {
                # Do a query on all open statuses
                my %status = OMP::Fault->faultStatusOpen(@cat_not_any);
                $hash{'status'} = [values %status];
            }
            elsif ($status eq 'non_duplicate') {
                $hash{'EXPR__STAT'} = {not => {status => OMP::Fault::DUPLICATE}};
            }
            else {
                # Do a query on just a single status
                $hash{'status'} = $status;
            }
        }

        if ($q->param('userid')) {
            die 'Invalid userid' unless $q->param('userid') =~ /^([A-Z]+[0-9]*)$/;

            $hash{'author'} = $1;
        }

        # Return either only faults filed, faults responded to, or occurring
        # on a particular date.
        my $datefield = 'date';
        if ($q->param('action') =~ /response/) {
            $hash{'isfault'} = {boolean => 0};
        }
        elsif ($q->param('action') =~ /file/) {
            $hash{'isfault'} = {boolean => 1};
        }
        elsif ($q->param('action') =~ /occurred/) {
            $datefield = 'faultdate';
        }

        # Generate the date portion of our query
        if ($q->param('period') eq 'arbitrary') {
            # Get our min and max dates
            my $mindatestr = $q->param('mindate');
            my $maxdatestr = $q->param('maxdate');

            # Check that we will understand the dates` formats
            # Maybe OMP::DateTools::parse_date method should be
            # catching these...
            for ($mindatestr, $maxdatestr) {
                if ($_) {
                    unless ($_ =~ /^\d{8}$/a
                            or $_ =~ /^\d\d\d\d-\d\d-\d\d$/a
                            or $_ =~ /^\d{4}-\d\d-\d\dT\d\d:\d\d$/a
                            or $_ =~ /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d$/a) {
                        croak "Date [$_] not understood. Please use either YYYYMMDD or YYYY-MM-DDTHH:MM format.";
                    }
                }
            }

            my $timezone = $q->param('timezone');
            my $islocal = ((defined $timezone) and ($timezone ne 'UT'));

            # Convert dates to UT
            $mindate = OMP::DateTools->parse_date($mindatestr, $islocal);
            $maxdate = OMP::DateTools->parse_date($maxdatestr, $islocal);

            # Imply end of day (23:59) for max date if no time was specified
            ($maxdate and $maxdatestr !~ /T/) and $maxdate += ONE_DAY - 1;

            # Do a min/max date query
            if ($mindate or $maxdate) {
                my %datehash = ();
                $datehash{'min'} = $mindate->datetime if $mindate;
                $datehash{'max'} = $maxdate->datetime if $maxdate;
                $hash{$datefield} = \%datehash;
            }

            # Convert dates back to localtime
            ($mindate) and $mindate = localtime($mindate->epoch);
            ($maxdate) and $maxdate = localtime($maxdate->epoch);
        }
        elsif ($q->param('period') eq 'days') {
            my $days = $q->param('days');
            $days = 14 unless $days;

            $maxdate = localtime($t->epoch);
            $mindate = localtime($maxdate->epoch - $days * ONE_DAY);

            $hash{$datefield} = {delta => - $days, value => $t->datetime};
        }
        elsif ($q->param('period') eq 'last_month') {
            # Get results for the period between the first
            # and last days of the last month
            my $year;
            my $month;
            if ($t->strftime("%Y%m") =~ /^(\d{4})(\d{2})$/a) {
                $year = $1;
                $month = $2;
            }

            $month -= 1;
            if ($month eq 0) {
                $month = 12;
                $year -= 1;
            }

            # Zero pad the month number
            $month = sprintf("%02d", $month);

            my $tempdate = Time::Piece->strptime($year . $month . "01", "%Y%m%d");
            $mindate = gmtime($tempdate->epoch);
            my $tempdate2 = Time::Piece->strptime($year . $month . $tempdate->month_last_day . "T23:59:59", "%Y%m%dT%H:%M:%S");
            $maxdate = gmtime($tempdate2->epoch);

            $hash{$datefield} = {
                min => $mindate->datetime,
                max => $maxdate->datetime,
            };

            # Convert dates to localtime
            $mindate = localtime($mindate->epoch);
            $maxdate = localtime($maxdate->epoch);
        }
        else {
            $hash{$datefield} = {delta => -7, value => $t->ymd};
        }

        # Get the text param and unescape things like &amp; &quot;
        my $text = $q->param('text');
        if ($text) {
            my $text_boolean = $q->param('text_boolean');
            my $text_spec = $text_boolean ? {mode => 'boolean', value => $text} : $text;

            $text = OMP::Display::escape_entity($text);
            my $text_search = $q->param('text_search');
            if ($text_search eq 'text') {
                $hash{'text'} = $text_spec;
            }
            elsif ($text_search eq 'subject') {
                $hash{'subject'} = $text_spec;
            }
            else {
                $hash{'EXPR__TS'} = {or => {
                    text => $text_spec,
                    subject => $text_spec,
                }};
            }
        }

        if ($q->param('timelost')) {
            $hash{'timelost'} = {min => 0.001};
        }
    }
    elsif ($q->param('major')) {
        # Faults within the last 14 days with 2 or more hours lost
        %hash = (
            %{$comp->category_hash($category)},
            date => {delta => -14, value => $t->datetime},
            timelost => {min => 2},
        );
        $title = sprintf 'Displaying major %ss from the last 14 days', lc $entry_name;
        $is_preset_view = 1;
    }
    elsif ($q->param('recent')) {
        # Faults active in the last 36 hours
        %hash = (
            %{$comp->category_hash($category)},
            date => {delta => -2, value => $t->datetime},
        );
        $title = sprintf 'Displaying %ss with any activity in the last 2 days', lc $entry_name;
        $is_preset_view = 1;
    }
    elsif ($q->param('current')) {
        # Faults within the last 14 days
        %hash = %currenthash;
        $title = sprintf 'Displaying %ss with any activity in the last 14 days', lc $entry_name;
        $is_preset_view = 1;
    }
    else {
        # Initial display of query page
        %hash = (
            %{$comp->category_hash($category)},
            date => {delta => -7, value => $t->datetime},
        );
        $title = sprintf 'Displaying %ss with any activity in the last 7 days', lc $entry_name;
        $is_initial_view = 1;
    }

    my $show_affected = $q->param('show_affected');

    my $faultgrp;
    my $search_error = undef;
    my %queryopt = (no_text => 1, no_projects => ! $show_affected);
    my $fdb = OMP::DB::Fault->new(DB => $self->database);
    try {
        $faultgrp = $fdb->queryFaults(OMP::Query::Fault->new(HASH => \%hash), %queryopt);

        # If this is the initial display of faults and no recent faults were
        # returned, display faults for the last 14 days.
        if ($is_initial_view and not $faultgrp->numfaults) {
            $title = sprintf
                'No active %ss in the last 7 days, displaying %ss for the last 14 days',
                lc $entry_name, lc $entry_name;

            $faultgrp = $fdb->queryFaults(OMP::Query::Fault->new(HASH => \%currenthash), %queryopt);
        }
    }
    otherwise {
        $search_error = shift;
    };

    return $self->_write_error('Failed to query fault database: ' . $search_error)
        if defined $search_error;

    # Generate a title based on the results returned
    my $nfaults = $faultgrp->numfaults;
    unless ($is_initial_view or $is_preset_view) {
        if ($nfaults > 1) {
            $title = sprintf '%i %ss returned matching your query', $nfaults, lc $entry_name;
        }
        elsif ($nfaults == 1) {
            $title = sprintf '1 %s returned matching your query', lc $entry_name;
        }
        else {
            $title = sprintf 'No %ss found matching your query', lc $entry_name;
        }
    }

    my $total_loss = 0.0;
    my $fault_summary = undef;
    my $fault_info = undef;
    my $sort_order = $self->decoded_url_param('sort_order') // 'descending';
    my $orderby = $self->decoded_url_param('orderby') // 'response';

    unless ($nfaults) {
        # No faults found - nothing to do.
    }
    elsif ($q->param('summary')) {
        # Show results as a summary if that option was checked

        $fault_summary = $self->fault_summary_content(
            $category, $faultgrp, $mindate, $maxdate,
            show_affected => $show_affected);
    }
    else {
        $total_loss = $faultgrp->timelost->hours;

        my %showfaultargs = (
            category => $category,
            faults => $faultgrp,
            show_affected => $show_affected,
        );

        for my $opt (qw/response filedate faulttime timelost relevance/) {
            if ($orderby eq $opt) {
                $showfaultargs{'orderby'} = $opt;
                last;
            }
        }

        unless ($sort_order eq "ascending") {
            $showfaultargs{descending} = 1;
        }

        $fault_info = $comp->show_faults(%showfaultargs);
    }

    return {
        title => (sprintf '%s: View %ss',
            $comp->category_title($category),
            $entry_name),
        message => $title,
        form_info => $comp->query_fault_form($category, $hidefields),
        fault_list => $fault_info,
        fault_summary => $fault_summary,
        total_loss => $total_loss,
        selected_order_by => $orderby,
        order_bys => [map {[$_->[0], $_->[1], $self->url_absolute('orderby', $_->[0])]}
            [filedate => 'file date'],
            [faulttime => 'time occurred'],
            [response => 'date of last response'],
            [timelost => 'time lost'],
            [relevance => 'relevance'],
        ],
        selected_sort_order => $sort_order,
        sort_orders => [map {[$_->[0], $_->[1], $self->url_absolute('sort_order', $_->[0])]}
            [ascending => 'oldest/lowest first'],
            [descending => 'most recent/highest first'],
        ],
    };
}

=item B<view_fault>

Display a page showing a fault and providing a form for responding
to the fault, or process the view_fault_content "respond" and "close fault"
forms.

    $page->view_fault($category, $fault);

=cut

sub view_fault {
    my $self = shift;
    my $category = shift;
    my $fault = shift;

    return $self->_write_error('Fault ID not specified.')
        unless defined $fault;

    my $q = $self->cgi;
    my $comp = $self->fault_component;

    my $faultid = $fault->id;
    my $fdb = OMP::DB::Fault->new(DB => $self->database);

    my $show = $self->decoded_url_param('show') // 'nonhidden';
    my $order = $self->decoded_url_param('order') // 'asc';
    my %filter_info = (
        show => $show,
        order => $order,
    );

    my $page_title = sprintf '%s: View %s: %s',
        $comp->category_title($category),
        OMP::Fault->getCategoryEntryName($category),
        $faultid;

    if ($q->param('respond')) {
        # Make sure all the necessary params were provided
        my %params = (
            text => 'Response',
        );
        my @error;
        for (keys %params) {
            if (length($q->param($_)) < 1) {
                push @error, $params{$_};
            }
        }

        # Put the form back up if params are missing
        if ($error[0]) {
            return {
                title => $page_title,
                fault_info => $comp->fault_table($fault),
                response_info => $comp->response_form(fault => $fault),
                missing_fields => \@error,
                target_base => $q->url(-absolute => 1),
                filter_info => \%filter_info,
            };
        }

        # Get the status (possibly changed)
        my $status = $q->param('status');

        # Now update the status if necessary
        if ($status != $fault->status) {
            # Change status in fault object
            $fault->status($status);

            my $E;
            try {
                # Resubmit fault with new status
                $fdb->updateFault($fault);
            }
            otherwise {
                $E = shift;
            };
            return $self->_write_error("An error prevented the fault status from being updated: $E")
                if defined $E;
        }

        # The text.
        my $text = $q->param('text');

        # Strip out ^M
        $text = OMP::Display->remove_cr($text);

        my %common = $comp->parse_file_fault_form($category);

        my $E;
        try {
            my $resp = OMP::Fault::Response->new(
                author => $self->auth->user,
                text => $text,
                timelost => $common{'timelost'},
                faultdate => $common{'faultdate'},
                shifttype => $common{'shifttype'},
                remote => $common{'remote'},
            );
            $fdb->respondFault($fault->id, $resp);
        }
        otherwise {
            $E = shift;
        };
        return $self->_write_error("An error has prevented your response from being filed: $E")
            if defined $E;

    }
    elsif ($q->param('change_status')) {
        my $status = $q->param('status');

        if ($status != $fault->status) {
            my $E;
            try {
                # Right now we'll just do an update by resubmitting the fault
                # with the new status parameter.  But in principal we should
                # have a method for doing an explicit status update.

                # Change the status parameter
                $fault->status(scalar $q->param('status'));

                # Resubmit the fault
                $fdb->updateFault($fault, $self->auth->user);
            }
            otherwise {
                $E = shift;
            };
            return $self->_write_error("An error has prevented the fault status from being updated: $E")
                if defined $E;

        }
        else {
            return $self->_write_error("This fault already has a status of \"" . $fault->statusText . "\"");
        }
    }
    elsif ($q->param('submit_flag_up') or $q->param('submit_flag_down')) {
        my $respid = $q->param('respid');
        my $response = $fault->getResponse($respid);
        my $redirect = sprintf '%s#response%i', $self->url_absolute(), $response->respnum;

        my $flag = $response->flag();
        if ($q->param('submit_flag_up') and $flag < OMP__FR_INVALUABLE) {
            $response->flag($flag + 1);
        }
        elsif ($q->param('submit_flag_down') and $flag > OMP__FR_HIDDEN) {
            $response->flag($flag - 1);
        }
        else {
            return $self->_write_redirect($redirect);
        }

        my $E;
        try {
            $fdb->updateResponse($faultid, $response);
        }
        otherwise {
            $E = shift;
        };

        return $self->_write_error("Unable to update response", "$E")
            if defined $E;

        return $self->_write_redirect($redirect);
    }
    else {
        # Ensure $faultid is untainted, then look for fault images.
        die 'Invalid fault ID' unless $faultid =~ /^(\d+\.\d+)$/; $faultid = $1;
        my $images = $self->_list_fault_images($self->_get_fault_image_directory($faultid));

        if ($order !~ /asc/ or $show !~ /all/) {
            my @responses = $fault->responses;
            my $original = shift @responses;

            if ($show =~ /nonhidden/) {
                @responses = grep {$_->flag != OMP__FR_HIDDEN} @responses;
            }
            elsif ($show =~ /timeloss/) {
                @responses = grep {$_->timelost > 0.001} @responses;
            }
            elsif ($show =~ /automatic/) {
                my $num_start = 12;
                my $num_end = 12;
                my @start = ();
                my @middle = ();
                my @end = ();

                # Look for the desired number of non-hidden responses
                # at the end of the thread.
                while ((scalar @responses) and ($num_end > scalar @end)) {
                    my $response = pop @responses;
                    push @end, $response unless $response->flag == OMP__FR_HIDDEN;
                }

                # Look for the desired number of non-hidden respones
                # at the start of the thread.
                while ((scalar @responses) and ($num_start > scalar @start)) {
                    my $response = shift @responses;
                    push @start, $response unless $response->flag == OMP__FR_HIDDEN;
                }

                # Routine to add a message saying how many messages were hidden
                # automatically.  It is easiest if this can go into @responses so
                # that it keeps the correct position if the ordering is reversed.
                # However currently this means that we need an OMP::Fault::Response
                # object -- construct one with a dummy user ID which the template
                # can recognize.
                my $n_hidden = 0;
                my $show_hidden = sub {
                    push @middle, OMP::Fault::Response->new(
                        text => (sprintf '%d %s hidden.',
                            $n_hidden, $n_hidden > 1 ? 'responses' : 'response'),
                        author => OMP::User->new(userid => '_HIDDEN'),
                    );
                    $n_hidden = 0;
                };

                # Include any message flagged above "normal" in the middle
                # of the thread.
                foreach my $response (@responses) {
                    unless ($response->flag > OMP__FR_NORMAL) {
                        $n_hidden ++;
                        next;
                    }
                    $show_hidden->() if $n_hidden;
                    push @middle, $response;
                }
                $show_hidden->() if $n_hidden;

                @responses = (@start, @middle, reverse @end);
            }

            @responses = reverse @responses if $order =~ /desc/;

            $fault->responses([map {
                $_->images($images->{$_->id}) if exists $images->{$_->id}; $_;
            } $original, @responses]);
        }

        return {
            title => $page_title,
            fault_info => $comp->fault_table($fault),
            response_info => $comp->response_form(fault => $fault),
            missing_fields => undef,
            target_base => $q->url(-absolute => 1),
            filter_info => \%filter_info,
        };
    }

    return $self->_write_redirect("/cgi-bin/viewfault.pl?fault=$faultid");
}

=item B<update_fault_content>

Display a page with a form for updating fault details, or
Take parameters from the fault update page and update
the fault.

    $page->update_fault_content($category, $fault);

=cut

sub update_fault {
    my $self = shift;
    my $category = shift;
    my $fault = shift;

    my $q = $self->cgi;
    my $comp = $self->fault_component;

    return $self->_write_error('Fault ID not specified.')
        unless defined $fault;

    my $faultid = $fault->id;
    my $fdb = OMP::DB::Fault->new(DB => $self->database);

    unless ($q->param('submit_update')) {
        return {
            title => (sprintf '%s: Update %s: %s',
                $comp->category_title($category),
                OMP::Fault->getCategoryEntryName($category),
                $faultid),
            missing_fields => undef,
            %{$comp->file_fault_form($fault->category, fault => $fault)},
        };
    }

    # Get new properties
    my %newdetails = $comp->parse_file_fault_form($category);

    # Store details in a fault object for comparison
    my $new_f = OMP::Fault->new(
        category => $category,
        fault => $fault->responses->[0],
        %newdetails);

    my @details_changed = OMP::Fault::Util->compare($new_f, $fault);

    # Our original response
    my $response = $fault->responses->[0];

    # Store details in a fault response object for comparison
    my $new_r = OMP::Fault::Response->new(author => $response->author, %newdetails);

    my @response_changed = OMP::Fault::Util->compare($new_r, $fault->responses->[0]);

    if ($details_changed[0] or $response_changed[0]) {
        # Changes have been made so we'll do an update
        my $E;
        try {
            if ($details_changed[0]) {
                # Apply changes to fault
                for (@details_changed) {
                    $fault->$_($newdetails{$_});
                }

                # Store changes to DB
                $fdb->updateFault($fault, $self->auth->user);
            }

            if ($response_changed[0]) {
                # Apply changes to response
                for (@response_changed) {
                    $response->$_($newdetails{$_});
                }

                $fdb->updateResponse($fault->id, $response);
            }
        }
        otherwise {
            $E = shift;
        };
        return $self->_write_error(
            "An error has occurred which prevented the fault from being updated",
            "$E")
            if defined $E;

        return $self->_write_redirect("/cgi-bin/viewfault.pl?fault=$faultid");
    }

    $self->_write_error("No changes were made");
}

=item B<update_resp>

Create a form for updating fault details, or submit changes
to a fault response.

    $page->update_resp($category, $fault);

=cut

sub update_resp {
    my $self = shift;
    my $category = shift;
    my $fault = shift;

    my $q = $self->cgi;
    my $comp = $self->fault_component;

    my $respid = $self->decoded_url_param('respid');

    return $self->_write_error("A fault ID and response ID must be provided.")
        unless ($respid and defined $fault);

    my $faultid = $fault->id;
    my $fdb = OMP::DB::Fault->new(DB => $self->database);

    unless ($q->param('respond')) {
        return {
            title => (sprintf '%s: Update Response: %s',
                $comp->category_title($category),
                $faultid),
            response_info => $comp->response_form(fault => $fault, respid => $respid),
        };
    }

    my $text = $q->param('text');

    # Strip out ^M
    $text = OMP::Display->remove_cr($text);

    return $self->_write_error('Fault response text cannot be blank.')
        unless $text;

    my $flag = undef;
    if (defined $q->param('flag')) {
        if ($q->param('flag') =~ /^(-?\d)$/a) {
            $flag = $1;
        }
    }

    my %common = $comp->parse_form_common($category);

    # Get the response object
    my $response = $fault->getResponse($respid);

    # Make changes to the response object
    $response->text($text);
    $response->preformatted(0);
    $response->flag($flag) if defined $flag;
    $response->timelost($common{'timelost'});
    $response->faultdate($common{'faultdate'});
    $response->shifttype($common{'shifttype'});
    $response->remote($common{'remote'});

    # SHOULD DO A COMPARISON TO SEE IF CHANGES WERE ACTUALLY MADE

    # Submit the changes
    my $E;
    try {
        $fdb->updateResponse($faultid, $response);
    }
    otherwise {
        $E = shift;
    };

    return $self->_write_error("Unable to update response", "$E")
        if defined $E;

    return $self->_write_redirect("/cgi-bin/viewfault.pl?fault=$faultid");
}

=item B<response_image>

Create a form for uploading an image to a fault response.

    $page->response_image($category, $fault);

=cut

sub response_image {
    my $self = shift;
    my $category = shift;
    my $fault = shift;

    my $q = $self->cgi;
    my $comp = $self->fault_component;

    my $faultid = $fault->id;
    my $respid = $self->decoded_url_param('respid');

    return $self->_write_error('A fault ID and response ID must be provided.')
        unless ($respid and defined $fault);

    die 'Invalid fault ID' unless $faultid =~ /^(\d+\.\d+)$/; $faultid = $1;
    die 'Invalid response ID' unless $respid =~ /^(\d+)$/; $respid = $1;

    my $response = $fault->getResponse($respid);
    return $self->_write_error("Given response ID not found.")
        unless defined $response;

    if ($q->param('submit_upload')) {
        my ($max_filesize, $max_width, $max_height) = OMP::Config->getData('response-image-max');

        # Get the directory, find the existing images, then add this
        # response ID as a subdirectory.
        my $directory = $self->_get_fault_image_directory($faultid);
        my $images = $self->_list_fault_images($directory);
        $directory = join '/', $directory, $respid;

        # Select the next available image number.
        my $number = 1;
        if (exists $images->{$respid}) {
            $number = 1 + max(map {$_->{'number'}} @{$images->{$respid}});
        }

        if (my $fh = $q->upload('file')) {
            my $info = $q->uploadInfo($fh);
            my $type = $info->{'Content-Type'};
            my $is_jpeg = ($type =~ /image\/jpe?g/) ? 1 : 0;
            my $suffix = $is_jpeg ? 'jpeg' : 'png';

            my $buffer;
            my $n_read = $fh->read($buffer, $max_filesize);
            return $self->_write_error('Could not load given file.')
                unless $n_read;
            return $self->_write_error('Given file exceeds maximum file size.')
                unless $n_read < $max_filesize;

            my $image = GD::Image->new($buffer);
            $fh->close;

            return $self->_write_error('Could not read image.')
                unless defined $image;

            # Create directory in which to write the image if needed.
            make_path($directory, {chmod => 0777});

            # Check whether the image is a rotated photograph.
            my $tool = Image::ExifTool->new;
            $tool->ExtractInfo(\$buffer);
            my $orientation = $tool->GetValue('Orientation', 'ValueConv') || 1;

            if ($orientation == 3) {
                $image = $image->copyRotate180();
            }
            elsif ($orientation == 6) {
                $image = $image->copyRotate90();
            }
            elsif ($orientation == 8) {
                $image = $image->copyRotate270();
            }

            # Check whether the image needs to be scaled.
            my ($width, $height) = $image->getBounds();

            my $scale = max($width / $max_width, $height / $max_height);

            if ($scale > 1) {
                my $scaled_width = int($width / $scale);
                my $scaled_height = int($height / $scale);

                my $scaled = GD::Image->new($scaled_width, $scaled_height);
                $scaled->copyResized(
                    $image, 0, 0, 0, 0,
                    $scaled_width, $scaled_height,
                    $width, $height);

                my $outscaled = join '/', $directory, sprintf '%04d_scaled.%s', $number, $suffix;
                my $outh = IO::File->new($outscaled, 'w');
                if ($is_jpeg) {
                    # If a JPEG was uploaded, presumably it is a photograph,
                    # so JPEG may also be best for the scaled version?
                    print $outh $scaled->jpeg;
                }
                else {
                    print $outh $scaled->png;
                }
                $outh->close;
            }

            my $outfile = join '/', $directory, sprintf '%04d.%s', $number, $suffix;
            my $outh = IO::File->new($outfile, 'w');
            if ($is_jpeg) {
                # Write JPEG as recieved.
                print $outh $buffer;
            }
            else {
                # Export non-JPEG as PNG.
                print $outh $image->png;
            }
            $outh->close;
        }
        else {
            return $self->_write_error('No file was received.');
        }

        return $self->_write_redirect(
            sprintf '/cgi-bin/viewfault.pl?fault=%s#response%s',
            $faultid, $response->respnum);
    }

    return {
        title => (sprintf '%s: Upload Image: %s',
            $comp->category_title($category),
            $faultid),
        fault => $fault,
        response => $response,
        info => {
            target => $self->url_absolute(),
        },
    };
}

sub _get_fault_image_directory {
    my $self = shift;
    my $fault_id = shift;

    return join '/', OMP::Config->getData('directory-fault-image'), $fault_id,
}

sub _list_fault_images {
    my $self = shift;
    my $directory = shift;

    my %result;

    foreach my $filename (sort glob($directory . '/*/*.{png,jpeg}')) {
        next unless $filename =~ /\/(\d+)\/(\d+)(_scaled)?\.(png|jpeg)$/;
        my $respid = $1;
        my $filenum = $2;
        my $scaled = $3 ? 1 : 0;
        my $suffix = $4;

        unless (exists $result{$respid}->{$filenum}) {
            $result{$respid}->{$filenum} = {has_scaled => $scaled, suffix => $suffix};
        }
        else {
            $result{$respid}->{$filenum}->{'has_scaled'} = 1 if $scaled;
        }
    }

    return {map {
        my $r = $result{$_}; $_ => [map {{number => $_, %{$r->{$_}}}} sort {$a cmp $b} keys %$r]
    } keys %result};
}

=item B<fault_summary_content>

Create a page summarizing faults for a particular category, or all categories.

    fault_summary_content($category, $faults, $mindate, $maxdate, %args);

Second argument is an C<OMP::Fault::Group> object.
The third and forth arguments, each a C<Time::Piece> object,
can be provided to display the date range used for the query that returned
the faults provided as the first argument.

=cut

sub fault_summary_content {
    my $self = shift;
    my $category = shift;
    my $faultgrp = shift;
    my $mindate = shift;
    my $maxdate = shift;
    my %args = @_;

    # Store faults by system and type
    my %faults;
    my %totals;
    my %timelost;
    my %sysID;  # IDs used to identify table rows that belong to a particular system
    my %typeID;  # IDs used to identify table rows that belong to a particular type
    my $timelost = 0;
    my $totalfiled = 0;
    $totals{open} = 0;

    for ($faultgrp->faults) {
        $totals{$_->systemText} ++;
        $timelost += $_->timelost;

        # Keep track of number of faults that were filed during the query period
        my $filedate = $_->responses->[0]->date;
        if ($mindate and $maxdate) {
            $totalfiled ++
                if ($filedate->epoch >= $mindate->epoch
                and $filedate->epoch <= $maxdate->epoch);
        }

        # Store open faults and closed major faults
        my $status;
        if ($_->isOpen) {
            $status = 'open';
        }
        else {
            $status = 'closed';
            $sysID{$_->systemText} = sprintf("%08d", $_->system) . "sys";
        }

        $typeID{$_->typeText} = sprintf("%08d", $_->type) . "type";
        push(@{$faults{$_->systemText}{$status}{$_->typeText}}, $_);
        $totals{$status} ++;

        $timelost{$status}{$_->systemText} += $_->timelost;
    }

    return {
        show_projects => $args{'show_affected'},
        num_faults => $faultgrp->numfaults,
        num_faults_filed => $totalfiled,
        date_min => $mindate,
        date_max => $maxdate,
        time_lost => \%timelost,
        time_lost_total => $timelost,
        total => \%totals,
        system_ids => \%sysID,
        type_ids => \%typeID,
        faults => \%faults,
        days_since_date => sub {
            my $localtime = localtime;
            my $locallast = localtime($_[0]->epoch);
            my $lastresponse = $localtime - $locallast;
            return sprintf('%d', $lastresponse->days);
        },
        entry_name => OMP::Fault->getCategoryEntryName($category),
    };
}

=back

=head2 Internal methods

=over 4

=item B<_write_page_extra>

Method to prepare extra information for the L<write_page> system.  For the
fault system, attempt to identify the category and fault.  If a fault ID
was given, the fault is retrieved from the database, added to the handler
method arguments and used to determine the category.

=cut

sub _write_page_extra {
    my $self = shift;

    my $q = $self->cgi;

    my $cat;
    my $fault;
    my $faultid = $self->decoded_url_param('fault');

    if (defined $faultid) {
        $faultid = OMP::General->extract_faultid("[${faultid}]");
        croak 'Invalid fault ID' unless defined $faultid;

        my $fdb = OMP::DB::Fault->new(DB => $self->database);

        try {
            $fault = $fdb->getFault($faultid);
        }
        otherwise {
            my $E = shift;
            croak "Unable to retrieve fault $faultid [$E]";
        };

        unless (defined $fault) {
            $self->_write_not_found_page('Fault not found.');
            return {abort => 1};
        }

        $self->html_title($faultid . ': ' . $self->html_title());
        $cat = $fault->category;
    }
    else {
        $cat = $self->decoded_url_param('cat');

        if (defined $cat) {
            $cat = uc $cat;

            undef $cat unless $cat eq 'ANYCAT'
                or grep {$cat eq $_} OMP::Fault->faultCategories;
        }
    }

    $self->_sidebar_fault($cat);

    unless (defined $cat) {
        $self->_write_category_choice();

        return {abort => 1};
    }

    return {args => [$cat, $fault]};
}

=item B<_sidebar_fault>

Create and display fault system sidebar.

    $page->_sidebar_fault($cat)

=cut

sub _sidebar_fault {
    my $self = shift;
    my $cat = shift;

    if (defined $cat and $cat ne "ANYCAT") {
        $cat = uc $cat;

        my $text = lc OMP::Fault->getCategoryEntryName($cat);
        my $prop = ($text =~ /^[aeiou]/) ? 'an' : 'a';

        $self->side_bar(
            OMP::Fault->getCategoryFullName($cat),
            [
                ["File $prop $text" => "/cgi-bin/filefault.pl?cat=$cat"],
                ["View ${text}s" => "/cgi-bin/queryfault.pl?cat=$cat"],
            ]);
    }

    $self->side_bar(
        'Fault system',
        [
            map {[$_->{'text'} => $_->{'url'}]}
            $self->_fault_sys_links()
        ],
        fault_id_panel => 1);
}

=item B<_write_category_choice>

Create and display a page for choosing a fault category to browse
and interact with.

    $page->_write_category_choice()

=cut

sub _write_category_choice {
    my $self = shift;
    my %opt = ();

    my $q = $self->cgi;

    # Assume "ANYCAT" is last in order, so "pop" it from the list.
    my @links = $self->_fault_sys_links;
    my $link_any = pop @links;

    $self->_write_http_header(undef, \%opt);
    $self->render_template(
        'fault_category_choice.html',
        {
            %{$self->_write_page_context_extra(\%opt)},
            categories => \@links,
            category_any => $link_any,
        });
}

sub _fault_sys_links {
    my $self = shift;

    my @info = (
        {
            category => 'CSG',
            description => 'EAO computer services',
        },
        {
            category => 'OMP',
            description => 'the Observation Management Project',
        },
        {
            category => 'UKIRT',
            description => 'UKIRT',
        },
        {
            category => 'JCMT',
            description => 'JCMT',
        },
        {
            category => 'JCMT_EVENTS',
            full_description => 'event logging for JCMT',
        },
        {
            category => 'DR',
            description => 'data reduction systems',
        },
        {
            category => 'FACILITY',
            description => 'facilities',
        },
        {
            category => 'SAFETY',
            full_description => 'issues relating to safety',
        },
        {
            category => 'VEHICLE_INCIDENT',
            full_description => 'vehicle incident issues',
        },
        {
            category => 'ANYCAT',
            text => 'All Faults',
            full_description => 'faults in all categories',
        },
    );

    return map {
        my $cat = $_->{'category'};
        {
            'category' => $cat,
            'url' => "/cgi-bin/queryfault.pl?cat=$cat",
            'text' => (exists $_->{'text'}
                ? $_->{'text'}
                : OMP::Fault->getCategoryFullName($cat)),
            'extra' => (exists $_->{'full_description'}
                ? $_->{'full_description'}
                : 'faults relating to ' . $_->{'description'}),
        };
    } @info;
}

1;

__END__

=back

=head1 SEE ALSO

C<OMP::CGI>, C<OMP::CGI::Fault>, C<OMP::CGI::Project>

=head1 AUTHOR

Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>,

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
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
