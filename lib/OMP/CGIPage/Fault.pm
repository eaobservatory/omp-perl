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

use Time::Piece;
use Time::Seconds qw/ONE_DAY/;

use OMP::CGIComponent::Fault;
use OMP::CGIComponent::Project;
use OMP::Config;
use OMP::Constants qw/:faultresponse/;
use OMP::DBServer;
use OMP::Display;
use OMP::DateTools;
use OMP::NetTools;
use OMP::General;
use OMP::Fault;
use OMP::FaultDB;
use OMP::FaultUtil;
use OMP::Display;
use OMP::FaultServer;
use OMP::Fault::Response;
use OMP::User;
use OMP::UserServer;
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
    my $faultid = shift;

    my $q = $self->cgi;

    my $comp = $self->fault_component;

    unless ($q->param('submit_file')) {
        return {
            title => $comp->category_title($category) . ': File Fault',
            missing_fields => undef,
            %{$comp->file_fault_form($category)},
        };
    }

    # Make sure all the necessary params were provided
    my %params = (
        Subject => "subject",
        "Fault report" => "message",
        Type => "type",
        System => "system",
    );

    # Adjust for "Safety" category.
    if ('safety' eq lc $category) {
        delete $params{'System'};
        $params{'Location'} = 'location';
        $params{'Severity'} = 'system';
    }
    elsif ('vehicle_incident' eq lc $category) {
        delete $params{'System'};
        $params{'Vehicle'} = 'system';
    }

    my @error;
    for (keys %params) {
        if (length($q->param($params{$_})) < 1) {
            push @error, $_;
        }
    }

    # Put the form back up if params are missing
    my @title;
    if ($error[0]) {
        return {
            title => $comp->category_title($category) . ': File Fault',
            missing_fields => \@error,
            %{$comp->file_fault_form($category)},
        };
    }

    my %status = OMP::Fault->faultStatus;

    # Get the fault details
    my %faultdetails = $comp->parse_file_fault_form($category);

    my $resp = OMP::Fault::Response->new(
        author => $self->auth->user,
        text => $faultdetails{text},
    );

    # Create the fault object
    my $fault = OMP::Fault->new(
        category => $category,
        subject => $faultdetails{subject},
        system => $faultdetails{system},
        severity => $faultdetails{severity},
        type => $faultdetails{type},
        status => $faultdetails{status},
        location => $faultdetails{location},
        urgency => $faultdetails{urgency},
        shifttype => $faultdetails{shifttype},
        remote => $faultdetails{remote},
        fault => $resp,
    );

    # The following are not always present
    $fault->projects($faultdetails{projects}) if $faultdetails{projects};

    $fault->faultdate($faultdetails{faultdate}) if $faultdetails{faultdate};

    $fault->timelost($faultdetails{timelost}) if $faultdetails{timelost};

    # Submit the fault the the database
    my @message = ();
    try {
        $faultid = OMP::FaultServer->fileFault($fault);
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
    my $faultid = shift;

    my $q = $self->cgi;
    my $comp = $self->fault_component;

    my $title;
    my $t = gmtime;
    my %daterange;
    my $mindate;
    my $maxdate;
    my $xml;

    # XML query to return faults from the last 14 days
    my %faultstatus = 'safety' eq lc $category
        ? OMP::Fault->faultStatus_Safety
        : 'jcmt_events' eq lc $category
            ? OMP::Fault->faultStatus_JCMTEvents
            : 'vehicle_incident' eq lc $category
                ? OMP::Fault->faultStatus_VehicleIncident
                : OMP::Fault->faultStatus;

    my $currentxml = "<FaultQuery>"
        . $comp->category_xml($category)
        . "<date delta='-14'>" . $t->datetime . "</date>"
        . "</FaultQuery>";

    # Setup an argument for use with the query_fault_form function
    my $hidefields = ($category ne 'ANYCAT' ? 0 : 1);

    if ($q->param('search')) {
        # The 'Search' submit button was clicked
        my @xml;

        push @xml, $comp->category_xml($category);

        if ($q->param('system') !~ /any/) {
            my $system = $q->param('system');
            push @xml, "<system>$system</system>";
        }

        if ($q->param('type') !~ /any/) {
            my $type = $q->param('type');
            push @xml, "<type>$type</type>";
        }

        # Return chronic faults only?
        if ($q->param('chronic')) {
            my %condition = OMP::Fault->faultCondition;
            push @xml, "<condition>$condition{Chronic}</condition>";
        }

        if ($q->param('status') ne "any") {
            my $status = $q->param('status');
            if ($status eq "all_closed") {
                # Do query on all closed statuses
                my %status = (
                    OMP::Fault->faultStatusClosed,
                    OMP::Fault->faultStatusClosed_Safety,
                    OMP::Fault->faultStatusClosed_JCMTEvents,
                    OMP::Fault->faultStatusClosed_VehicleIncident,
                );

                push @xml, join '', map {"<status>$status{$_}</status>"} %status;
            }
            elsif ($status eq "all_open") {
                # Do a query on all open statuses
                my %status = (
                    OMP::Fault->faultStatusOpen,
                    OMP::Fault->faultStatusOpen_Safety,
                    OMP::Fault->faultStatusOpen_JCMTEvents,
                    OMP::Fault->faultStatusOpen_VehicleIncident,
                );

                push @xml, join '', map {"<status>$status{$_}</status>"} %status;
            }
            else {
                # Do a query on just a single status
                my %status = (
                    OMP::Fault->faultStatus,
                    OMP::Fault->faultStatus_Safety,
                    OMP::Fault->faultStatus_JCMTEvents,
                    OMP::Fault->faultStatus_VehicleIncident,
                );

                push @xml, "<status>$status</status>";
            }
        }

        if ($q->param('author')) {
            my $author = uc($q->param('author'));

            # Get the user object (this will automatically
            # map the an alias to a user ID)
            my $user = OMP::UserServer->getUser($author);

            croak "Could not find user '$author'"
                unless $user;

            push @xml, "<author>" . $user->userid . "</author>";
        }

        # Generate the date portion of our query
        my $queryDateStr;
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
                push @xml, "<date>";
                push @xml, "<min>" . $mindate->datetime . "</min>" if $mindate;
                push @xml, "<max>" . $maxdate->datetime . "</max>" if $maxdate;
                push @xml, "</date>";
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

            push @xml, "<date delta='-$days'>" . $t->datetime . "</date>";
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

            push @xml, "<date><min>" . $mindate->datetime . "</min><max>" . $maxdate->datetime . "</max></date>";

            # Convert dates to localtime
            $mindate = localtime($mindate->epoch);
            $maxdate = localtime($maxdate->epoch);
        }
        else {
            push @xml, '<date delta="-7">' . $t->ymd . '</date>';
        }

        # Get the text param and unescape things like &amp; &quot;
        my $text = $q->param('text');
        if (defined $text) {
            my $text_boolean = $q->param('text_boolean');
            my $modestr = $text_boolean ? ' mode="boolean"' : '';

            $text = OMP::Display::escape_entity($text);
            my $text_search = $q->param('text_search');
            if ($text_search eq 'text') {
                push @xml, "<text$modestr>$text</text>";
            }
            elsif ($text_search eq 'subject') {
                push @xml, "<subject$modestr>$text</subject>";
            }
            else {
                push @xml, '<or>',
                    "<text$modestr>$text</text>",
                    "<subject$modestr>$text</subject>",
                    '</or>';
            }
        }

        # Return either only faults filed or only faults responded to
        if ($q->param('action') =~ /response/) {
            push(@xml, "<isfault>0</isfault>");
        }
        elsif ($q->param('action') =~ /file/) {
            push(@xml, "<isfault>1</isfault>");
        }

        if ($q->param('timelost')) {
            push(@xml, "<timelost><min>.001</min></timelost>");
        }

        # Our query XML
        $xml = "<FaultQuery>" . join('', @xml) . "</FaultQuery>";
    }
    elsif ($q->param('major')) {
        # Faults within the last 14 days with 2 or more hours lost
        $xml = "<FaultQuery>"
            . $comp->category_xml($category)
            . "<date delta='-14'>"
            . $t->datetime
            . "</date><timelost><min>2</min></timelost></FaultQuery>";
    }
    elsif ($q->param('recent')) {
        # Faults active in the last 36 hours
        $xml = "<FaultQuery>"
            . $comp->category_xml($category)
            . "<date delta='-2'>"
            . $t->datetime
            . "</date></FaultQuery>";
    }
    elsif ($q->param('current')) {
        # Faults within the last 14 days
        $xml = $currentxml;
        $title = "Displaying faults with any activity in the last 14 days";
    }
    else {
        # Initial display of query page
        $xml = "<FaultQuery>"
            . $comp->category_xml($category)
            . "<date delta='-7'>"
            . $t->datetime
            . "</date></FaultQuery>";
        $title = "Displaying faults with any activity in the last 7 days";
    }

    my $show_affected = $q->param('show_affected');

    my $faults;
    my $search_error = undef;
    my %queryopt = (no_text => 1, no_projects => ! $show_affected);
    try {
        $faults = OMP::FaultServer->queryFaults($xml, "object", %queryopt);

        # If this is the initial display of faults and no recent faults were
        # returned, display faults for the last 14 days.
        if (! $q->param('faultsearch') and ! $faults->[0]) {
            $title = "No active faults in the last 7 days, displaying faults for the last 14 days";

            $faults = OMP::FaultServer->queryFaults($currentxml, "object", %queryopt);
        }
    }
    otherwise {
        $search_error = shift;
    };

    return $self->_write_error('Failed to query fault database: ' . $search_error)
        if defined $search_error;

    # Generate a title based on the results returned
    if ($q->param('faultsearch')) {
        if ($faults->[1]) {
            $title = scalar(@$faults) . " faults returned matching your query";
        }
        elsif ($faults->[0]) {
            $title = "1 fault returned matching your query";
        }
        else {
            $title = "No faults found matching your query";
        }
    }

    my $total_loss = 0.0;
    my $fault_summary = undef;
    my $fault_info = undef;
    my $sort_order = $self->decoded_url_param('sort_order') // 'descending';
    my $orderby = $self->decoded_url_param('orderby') // 'response';

    # Show results as a summary if that option was checked
    if ($q->param('summary') and $faults->[0]) {
        $fault_summary = $self->fault_summary_content(
            $category, $faults, $mindate, $maxdate,
            show_affected => $show_affected);
    }
    elsif ($faults->[0]) {
        # Total up and display time lost
        for (@$faults) {
            $total_loss += $_->timelost;
        }

        my %showfaultargs = (
            faults => $faults,
            showcat => ($category ne 'ANYCAT' ? 0 : 1),
            show_affected => $show_affected,
        );

        for my $opt (qw/response filedate faulttime timelost relevance/) {
            if ($orderby eq $opt) {
                $showfaultargs{'orderby'} = $opt;
                last;
            }
        }

        if ($faults->[0]) {
            unless ($sort_order eq "ascending") {
                $showfaultargs{descending} = 1;
            }

            $fault_info = $comp->show_faults(%showfaultargs);
        }
    }

    return {
        title => $comp->category_title($category) . ': ' . 'View Faults',
        message => $title,
        form_info => $comp->query_fault_form($category, $hidefields),
        fault_list => $fault_info,
        fault_summary => $fault_summary,
        total_loss => $total_loss,
        selected_order_by => $orderby,
        order_bys => [map {[$_->[0], $_->[1], $self->url_absolute('orderby', $_->[0])]}
            [filedate => 'file date'],
            [faulttime => 'fault time'],
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

    $page->view_fault($category, $faultid);

=cut

sub view_fault {
    my $self = shift;
    my $category = shift;
    my $faultid = shift;

    return $self->_write_error('Fault ID not specified.')
        unless $faultid;

    my $q = $self->cgi;
    my $comp = $self->fault_component;

    my $fault = OMP::FaultServer->getFault($faultid);
    return $self->_write_error("Fault [$faultid] not found.")
        unless $fault;

    my $show = $self->decoded_url_param('show') // 'nonhidden';
    my $order = $self->decoded_url_param('order') // 'asc';
    my %filter_info = (
        show => $show,
        order => $order,
    );

    if ($q->param('respond')) {
        # Make sure all the necessary params were provided
        my %params = (Response => "text",);
        my @error;
        for (keys %params) {
            if (length($q->param($params{$_})) < 1) {
                push @error, $_;
            }
        }

        # Put the form back up if params are missing
        if ($error[0]) {
            return {
                title => $comp->category_title($category) . ': View Fault: ' . $faultid,
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
            # Lookup table for status
            my %status = (
                OMP::Fault->faultStatus(),
                OMP::Fault->faultStatus_Safety,
                OMP::Fault->faultStatus_JCMTEvents,
                OMP::Fault->faultStatus_VehicleIncident,
            );

            # Change status in fault object
            $fault->status($status);

            my $E;
            try {
                # Resubmit fault with new status
                OMP::FaultServer->updateFault($fault);
            }
            otherwise {
                $E = shift;
            };
            return $self->_write_error("An error prevented the fault status from being updated: $E")
                if defined $E;
        }

        # The text.  Put it in <pre> tags if there isn't an <html>
        # tag present
        my $text = $q->param('text');
        if ($text =~ /<html>/i) {
            # Strip out the <html> and </html> tags
            $text =~ s!</*html>!!ig;
        }
        else {
            $text = OMP::Display->preify_text($text);
        }

        # Strip out ^M
        $text =~ s/\015//g;

        my $E;
        try {
            my $resp = OMP::Fault::Response->new(
                author => $self->auth->user,
                text => $text,
            );
            OMP::FaultServer->respondFault($fault->id, $resp);
        }
        otherwise {
            $E = shift;
        };
        return $self->_write_error("An error has prevented your response from being filed: $E")
            if defined $E;

    }
    elsif ($q->param('change_status')) {
        # Lookup table for status
        my %status = OMP::Fault->faultStatus();

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
                OMP::FaultServer->updateFault($fault, $self->auth->user);
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
        my $response = OMP::FaultUtil->getResponse($respid, $fault);
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
            OMP::FaultServer->updateResponse($faultid, $response);
        }
        otherwise {
            $E = shift;
        };

        return $self->_write_error("Unable to update response", "$E")
            if defined $E;

        return $self->_write_redirect($redirect);
    }
    else {
        if ($order !~ /asc/ or $show !~ /all/) {
            my @responses = $fault->responses;
            my $original = shift @responses;

            if ($show =~ /nonhidden/) {
                @responses = grep {$_->flag != OMP__FR_HIDDEN} @responses;
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

            $fault->responses([$original, @responses]);
        }

        return {
            title => $comp->category_title($category) . ': View Fault: ' . $faultid,
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

    $page->update_fault_content($category, $faultid);

=cut

sub update_fault {
    my $self = shift;
    my $category = shift;
    my $faultid = shift;

    my $q = $self->cgi;
    my $comp = $self->fault_component;

    return $self->_write_error('Fault ID not specified.')
        unless $faultid;

    # Get the fault
    my $fault = OMP::FaultServer->getFault($faultid);

    unless ($q->param('submit_update')) {
        return {
            title => $comp->category_title($category) . ': Update Fault [' . $faultid . ']',
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

    my @details_changed = OMP::FaultUtil->compare($new_f, $fault);

    # Our original response
    my $response = $fault->responses->[0];

    # Store details in a fault response object for comparison
    my $new_r = OMP::Fault::Response->new(author => $response->author, %newdetails);

    # "Preify" the text before we compare responses
    my $newtext = $newdetails{text};
    $newtext =~ s!</*html>!!ig;
    $newtext = OMP::Display->preify_text($newtext);

    my @response_changed = OMP::FaultUtil->compare($new_r, $fault->responses->[0]);

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
                OMP::FaultServer->updateFault($fault, $self->auth->user);
            }

            if ($response_changed[0]) {
                # Apply changes to response
                for (@response_changed) {
                    $response->$_($newdetails{$_});
                }

                OMP::FaultServer->updateResponse($fault->id, $response);
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

    $page->update_resp($category, $faultid);

=cut

sub update_resp {
    my $self = shift;
    my $category = shift;
    my $faultid = shift;

    my $q = $self->cgi;
    my $comp = $self->fault_component;

    my $respid = $self->decoded_url_param('respid');

    return $self->_write_error("A fault ID and response ID must be provided.")
        unless ($faultid and $respid);

    # Get the fault
    my $fault = OMP::FaultServer->getFault($faultid);

    return $self->_write_error("Unable to retrieve fault with ID [$faultid]")
        unless $fault;

    unless ($q->param('respond')) {
        return {
            title => $comp->category_title($category) . ': Update Response [' . $faultid . ']',
            response_info => $comp->response_form(fault => $fault, respid => $respid),
        };
    }

    my $text = $q->param('text');

    # Prepare the text
    if ($text =~ /<html>/i) {
        # Strip out the <html> and </html> tags
        $text =~ s!</*html>!!ig;
    }
    else {
        $text = OMP::Display->preify_text($text);
    }

    # Strip out ^M
    $text =~ s/\015//g;

    my $flag = undef;
    if (defined $q->param('flag')) {
        if ($q->param('flag') =~ /^(-?\d)$/a) {
            $flag = $1;
        }
    }

    # Get the response object
    my $response = OMP::FaultUtil->getResponse($respid, $fault);

    # Make changes to the response object
    $response->text($text);
    $response->flag($flag) if defined $flag;

    # SHOULD DO A COMPARISON TO SEE IF CHANGES WERE ACTUALLY MADE

    # Submit the changes
    my $E;
    try {
        OMP::FaultServer->updateResponse($faultid, $response);
    }
    otherwise {
        $E = shift;
    };

    return $self->_write_error("Unable to update response", "$E")
        if defined $E;

    return $self->_write_redirect("/cgi-bin/viewfault.pl?fault=$faultid");
}

=item B<fault_summary_content>

Create a page summarizing faults for a particular category, or all categories.

    fault_summary_content($category, $faults, $mindate, $maxdate, %args);

First argument is an array of C<OMP::Fault> objects.
The second and third arguments, each a C<Time::Piece> object,
can be provided to display the date range used for the query that returned
the faults provided as the first argument.

=cut

sub fault_summary_content {
    my $self = shift;
    my $category = shift;
    my $faults = shift;
    my $mindate = shift;
    my $maxdate = shift;
    my %args = @_;

    my %status = OMP::Fault->faultStatus;
    my %statusOpen = OMP::Fault->faultStatusOpen;

    # Store faults by system and type
    my %faults;
    my %totals;
    my %timelost;
    my %sysID;  # IDs used to identify table rows that belong to a particular system
    my %typeID;  # IDs used to identify table rows that belong to a particular type
    my $timelost = 0;
    my $totalfiled = 0;
    $totals{open} = 0;

    for (@$faults) {
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
        if (exists $statusOpen{$_->statusText}) {
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
        num_faults => (scalar @$faults),
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
    };
}

=back

=head2 Internal methods

=over 4

=item B<_write_page_extra>

Method to prepare extra information for the L<write_page> system.  For the
fault system, attempt to identify the category and fault ID.

=cut

sub _write_page_extra {
    my $self = shift;

    my $q = $self->cgi;

    my $cat;
    my $faultid = $self->decoded_url_param('fault');

    if (defined $faultid) {
        my $fault;

        $faultid = OMP::General->extract_faultid("[${faultid}]");
        croak 'Invalid fault ID' unless defined $faultid;

        try {
            $fault = OMP::FaultServer->getFault($faultid);
        }
        otherwise {
            my $E = shift;
            croak "Unable to retrieve fault $faultid [$E]";
        };

        croak "Unable to retrieve fault with id [$faultid]"
            unless (defined $fault);

        $self->html_title($faultid . ': ' . $self->html_title());
        $cat = $fault->category;
    }
    else {
        $cat = uc $self->decoded_url_param('cat');

        my %categories = map {uc($_), undef} OMP::Fault->faultCategories;
        undef $cat unless (exists $categories{$cat} or $cat eq 'ANYCAT');
    }

    $self->_sidebar_fault($cat);

    unless ((defined $cat)) {
        $self->_write_category_choice();

        return {abort => 1};
    }

    return {args => [$cat, $faultid]};
}

=item B<_sidebar_fault>

Create and display fault system sidebar.

    $page->_sidebar_fault($cat)

=cut

sub _sidebar_fault {
    my $self = shift;
    my $cat = shift;

    my $suffix = $cat =~ /events/i
        ? ''
        : 'safety' eq lc $cat || 'vehicle_incident' eq lc $cat
            ? 'Reporting'
            : 'Faults';

    my %query_link = $self->_fault_sys_links;

    if (defined $cat and uc $cat ne "ANYCAT") {
        my ($text, $prop) = ('fault', 'a');
        if ($cat =~ /event/i) {
            $text = 'event';
            $prop = 'an';
        }

        $self->side_bar(
            "$cat $suffix",
            [
                ["File $prop $text" => "filefault.pl?cat=$cat"],
                ["View ${text}s" => $query_link{uc $cat}->{'url'}],
            ]);
    }

    $self->side_bar(
        'Fault system',
        [
            (
                map {[$query_link{$_}->{'text'} => $query_link{$_}->{'url'}]}
                grep {$_ ne 'ANYCAT'}
                $self->_fault_sys_links_order()
            ),
            ['All Faults' => $query_link{'ANYCAT'}->{'url'}],
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

    my %query = $self->_fault_sys_links;

    $self->_write_http_header(undef, \%opt);
    $self->render_template(
        'fault_category_choice.html',
        {
            %{$self->_write_page_context_extra(\%opt)},
            categories => [
                map {
                    $query{$_}
                }
                grep {
                    'anycat' ne lc $_
                } $self->_fault_sys_links_order
            ],
            category_any => $query{'ANYCAT'},
        });
}

BEGIN {
    my @order = qw/
        CSG OMP UKIRT JCMT JCMT_EVENTS DR FACILITY SAFETY
        VEHICLE_INCIDENT
    /;

    push @order, 'ANYCAT';

    my %long_text = (
        'CSG' => 'EAO computer services',
        'OMP' => 'Observation Management Project',
        'UKIRT' => 'UKIRT',
        'JCMT' => 'JCMT',
        'JCMT_EVENTS' => 'JCMT events',
        'DR' => 'data reduction systems',
        'FACILITY' => 'facilities',
        'SAFETY' => 'safety',
        'VEHICLE_INCIDENT' => 'vehicle incident',
        'ANYCAT' => 'all categories',
    );

    sub _fault_sys_links {
        my %links;
        for my $type (@order) {
            next if grep {$type eq $_}
                ('SAFETY', 'JCMT_EVENTS', 'VEHICLE_INCIDENT');

            $links{$type} = {
                'url' => "/cgi-bin/queryfault.pl?cat=$type",
                'text' => "$type Faults",
                'extra' => 'faults relating to ' . $long_text{$type}
            };
        }

        $links{'SAFETY'} = {
            'url' => '/cgi-bin/queryfault.pl?cat=SAFETY',
            'text' => 'Safety Reporting',
            'extra' => 'issues relating to safety'
        };

        $links{'JCMT_EVENTS'} = {
            'url' => '/cgi-bin/queryfault.pl?cat=JCMT_EVENTS',
            'text' => 'JCMT Events',
            'extra' => 'event logging for JCMT'
        };

        $links{'VEHICLE_INCIDENT'} = {
            'url' => '/cgi-bin/queryfault.pl?cat=VEHICLE_INCIDENT',
            'text' => 'Vehicle Incident Reporting',
            'extra' => 'vehicle incident issues'
        };

        #  Fine tune 'ANYCAT' description.
        $links{'ANYCAT'}->{'extra'} = 'faults in all categories';

        return %links;
    }

    sub _fault_sys_links_order {
        my ($self) = @_;
        return @order;
    }
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
