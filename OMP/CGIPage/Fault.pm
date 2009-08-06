package OMP::CGIPage::Fault;

=head1 NAME

OMP::CGIPage::Fault - Display dynamic fault web pages

=head1 SYNOPSIS

  use OMP::CGIPage::Fault;
  $q = new CGI;
  $page = new OMP::CGIPage::Fault(CGI=> $q);

=head1 DESCRIPTION

Construct and display complete web pages for viewing faults
and interacting with the fault system in general.  This class
inherits from C<OMP::CGIPage>.

=cut

use 5.006;
use strict;
use warnings;
use Carp;
our $VERSION = (qw$ Revision: 1.2 $ )[1];

use Time::Piece;
use Time::Seconds qw(ONE_DAY);

use OMP::CGIComponent::Fault;
use OMP::CGIComponent::Project;
use OMP::Config;
use OMP::DBServer;
use OMP::General;
use OMP::Fault;
use OMP::FaultDB;
use OMP::FaultUtil;
use OMP::Display;
use OMP::FaultServer;
use OMP::Fault::Response;
use OMP::User;
use OMP::UserServer;
use OMP::KeyServer;
use OMP::Error qw(:try);

use base qw(OMP::CGIPage);

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

Create a new instance of an C<OMP::CGIPage::Fault> object.

  $page = new OMP::CGIPage::Fault( CGI => $q );

=cut

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;

  # Read the arguments
  my %args;
  %args = @_ if @_;

  # Call our parent class's constructor
  my $self = $class->SUPER::new();

  # Add a fault component attribute
  $self->{FaultComponent} = undef;

  my $object = bless $self, $class; # Reconsecrate

  # Populate object
  $self->rss_feed({title=>'OMP Fault System (last 24 hours)',
                   href=>'faultrss.pl',});

  for my $key (keys %args) {
    my $method = lc($key);
    $object->$method($args{$key});
  }

  return $object;
}

=back

=head2 Accessor methods

=over 4

=item B<fault_component>

The fault component object.  An attempt is made to set the component's
'category' attribute when this method is called.

  $comp = $page->fault_component()
  $page->fault_component($comp)

Argument is an C<OMP::CGIComponent::Fault> object.

=cut

sub fault_component {
  my $self = shift;
  if (@_) {
    throw OMP::Error::BadArgs("Must be an OMP::CGIComponent::Fault object")
      unless UNIVERSAL::isa($_[0], 'OMP::CGIComponent::Fault');
    $self->{FaultComponent} = $_[0];
  } elsif (! defined $self->{FaultComponent}) {
    $self->{FaultComponent} = new OMP::CGIComponent::Fault(CGI=>$self->cgi,);
  }
  my $comp = $self->{FaultComponent};
  $comp->category($self->_get_param('cat'))
    unless (defined $comp->category);
  return $comp;
}

=back

=head2 General methods

=over 4

=item B<file_fault>

Creates a page with a form for for filing a fault.

  $fp->file_fault();

=cut

sub file_fault {
  my $self = shift;
  my $comp = $self->fault_component;

  $comp->titlebar(["File Fault"]);
  $comp->file_fault_form();
}

=item B<file_fault_output>

Submit a fault and create a page that shows the status of the submission.

  $fp->file_fault_output();

=cut

sub file_fault_output {
  my $self = shift;
  my $q = $self->cgi;
  my $comp = $self->fault_component;

  # Get the form key
  my $formkey = $q->param('formkey');

  # Croak if key is invalid
  my $verifykey = OMP::KeyServer->verifyKey($formkey);
  croak "Key is invalid [perhaps you already submitted this form?]"
    unless ($verifykey);

  # Make sure all the necessary params were provided
  my %params = (User => "user",
                Subject => "subject",
                "Fault report" => "message",
                Type => "type",
                System => "system",);

  # Adjust for "Safety" category.
  if ( 'safety' eq lc $self->_get_param( 'cat' ) ) {

    delete $params{'System'};
    $params{'Location'} = 'location';
    $params{'Severity'} = 'severity';
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
    push @title, "The following fields were not filled in:";
    $comp->titlebar(["File Fault", join('<br>',@title)]);
    print "<ul>";
    print map {"<li>$_"} @error;
    print "</ul>";
    $comp->file_fault_form();
    return;
  }

  # Make sure user is valid
  my $user = OMP::UserServer->getUser($q->param('user'));
  if (! $user) {
    push @title, "The user ID you entered does not exist.  Please enter another and submit again";
    $comp->titlebar(["File Fault", join('<br>',@title)]);
    $comp->file_fault_form()
  }

  my %status = OMP::Fault->faultStatus;

  # Get the fault details
  my %faultdetails = $comp->parse_file_fault_form();

  my $resp = OMP::Fault::Response->new( author=>$faultdetails{author},
                                        text=>$faultdetails{text},);

  # Create the fault object
  my $category = $q->param('category');
  my $fault = OMP::Fault->new( category => $category,
                                subject  => $faultdetails{subject},
                                system   => $faultdetails{system},
                                severity => $faultdetails{severity},
                                type     => $faultdetails{type},
                                status   => $faultdetails{status},
                                location => $faultdetails{location},
                                urgency  => $faultdetails{urgency},
                                fault    => $resp
                              );

  # The following are not always present
  ($faultdetails{projects}) and $fault->projects($faultdetails{projects});

  ($faultdetails{faultdate}) and $fault->faultdate($faultdetails{faultdate});

  ($faultdetails{timelost}) and $fault->timelost($faultdetails{timelost});

  # Submit the fault the the database
  my $faultid;
  my $E;
  try {
    $faultid = OMP::FaultServer->fileFault($fault);
  } catch OMP::Error::MailError with {
    $E = shift;
    print $q->h2("Fault has been filed, but an error has prevented it from being mailed:");
    print "$E";
  } catch OMP::Error::FatalError with {
    $E = shift;
    print $q->h2("An error has prevented the fault from being filed:");
    print "$E";
  } otherwise {
    $E = shift;
    print $q->h2("An error has occurred");
    print "$E";
  };

  # Show the fault if it was successfully filed
  if ($faultid) {

    # Remove the key
    OMP::KeyServer->removeKey($formkey);

    my $f = OMP::FaultServer->getFault($faultid);
    $comp->titlebar(["File Fault", "Fault $faultid has been filed"]);

    $comp->fault_table($f, 'nostatus');
  }
}

=item B<query_fault_output>

Display output of a fault query

  query_fault_output();

=cut

sub query_fault_output {
  my $self = shift;
  my $q = $self->cgi;
  my $comp = $self->fault_component;

  my $title;
  my $t = gmtime;
  my %daterange;
  my $mindate;
  my $maxdate;
  my $xml;
  my $category = $self->_get_param('cat');

  # XML query to return faults from the last 14 days
  my %faultstatus =
    'safety' eq lc $category
    ? OMP::Fault->faultStatus_Safety
    : 'jcmt_events' eq lc $category
      ? OMP::Fault->faultStatus_JCMTEvents
      : OMP::Fault->faultStatus
      ;

  my $currentxml = "<FaultQuery>".
    $comp->category_xml().
      "<date delta='-14'>" . $t->datetime . "</date>".
        "</FaultQuery>";

  # Setup an argument for use with the query_fault_form function
  my $hidefields = ($category ne 'ANYCAT' ? 0 : 1);

  # Print faults if print button was clicked
  if ($q->param('print')) {
    my $printer = $q->param('printer');
    my @fprint = split(',',$q->param('faults'));

    my $separate = 0;  # Argument governs whether faults are printed combined
    if ($q->param('print_method') eq "separate") {
      $separate = 1;
    }

    OMP::FaultUtil->print_faults($printer, $separate, @fprint);

    $comp->titlebar(["View Faults", "Sent faults to printer $printer"]);
    return;
  }

  if ($q->param('search')) {
    # The 'Search' submit button was clicked
    my @xml;

    push (@xml, $comp->category_xml());

    if ($q->param('system') !~ /any/) {
      my $system = $q->param('system');
      push (@xml, "<system>$system</system>");
    }

    if ($q->param('type') !~ /any/) {
      my $type = $q->param('type');
      push (@xml, "<type>$type</type>");
    }

    # Return chronic faults only?
    if ($q->param('chronic')) {
      my %condition = OMP::Fault->faultCondition;
      push (@xml, "<condition>$condition{Chronic}</condition>");
    }

    if ($q->param('status') ne "any") {

      my $status = $q->param('status');
      if ($status eq "all_closed") {

        # Do query on all closed statuses
        my %status = ( OMP::Fault->faultStatusClosed,
                        OMP::Fault->faultStatusClosed_Safety,
                        OMP::Fault->faultStatusClosed_JCMTEvents
                      );

        push (@xml, join("",map {"<status>$status{$_}</status>"} %status));
      } elsif ($status eq "all_open") {

        # Do a query on all open statuses
        my %status = ( OMP::Fault->faultStatusOpen,
                        OMP::Fault->faultStatusOpen_Safety,
                        OMP::Fault->faultStatus_JCMTEvents
                      );

        push (@xml, join("",map {"<status>$status{$_}</status>"} %status));
      } else {

        # Do a query on just a single status
        my %status = ( OMP::Fault->faultStatus,
                        OMP::Fault->faultStatus_Safety,
                        OMP::Fault->faultStatus_JCMTEvents
                      );

        push (@xml, "<status>$status</status>");
      }
    }

    if ($q->param('author')) {
      my $author = uc($q->param('author'));

      # Get the user object (this will automatically
      # map the an alias to a user ID)
      my $user = OMP::UserServer->getUser($author);

      push (@xml, "<author>".$user->userid."</author>");
    }

    # Generate the date portion of our query
    my $queryDateStr;
    if ($q->param('period') eq 'arbitrary') {

      # Get our min and max dates
      my $mindatestr = $q->param('mindate');
      my $maxdatestr = $q->param('maxdate');

      # Check that we will understand the dates` formats
      # Maybe OMP::General parse_date method should be
      # catching these...
      for ($mindatestr, $maxdatestr) {
        if ($_) {
          unless ($_ =~ /^\d{8}$/ or
                  $_ =~ /^\d\d\d\d-\d\d-\d\d$/ or
                  $_ =~ /^\d{4}-\d\d-\d\dT\d\d:\d\d$/ or
                  $_ =~ /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d$/) {

            croak "Date [$_] not understood. Please use either YYYYMMDD or YYYY-MM-DDTHH:MM format.";
          }
        }
      }

      # Convert dates to UT
      $mindate = OMP::General->parse_date($mindatestr, 1);
      $maxdate = OMP::General->parse_date($maxdatestr, 1);

      # Imply end of day (23:59) for max date if no time was specified
      ($maxdate and $maxdatestr !~ /T/) and $maxdate += ONE_DAY - 1;

      # Do a min/max date query
      if ($mindate or $maxdate) {
        push (@xml, "<date>");
        ($mindate) and push (@xml, "<min>" . $mindate->datetime . "</min>");
        ($maxdate) and push (@xml, "<max>" . $maxdate->datetime . "</max>");
        push (@xml, "</date>");
      }

      # Convert dates back to localtime
      ($mindate) and $mindate = localtime($mindate->epoch);
      ($maxdate) and $maxdate = localtime($maxdate->epoch);

    } elsif ($q->param('period') eq 'days') {
      my $days = $q->param('days');
      (! $days) and $days = 14;

      $maxdate = localtime($t->epoch);
      $mindate = localtime($maxdate->epoch - $days * ONE_DAY);

      push (@xml, "<date delta='-$days'>". $t->datetime ."</date>");
    } elsif ($q->param('period') eq 'last_month') {
      # Get results for the period between the first
      # and last days of the last month
      my $year;
      my $month;
      if ($t->strftime("%Y%m") =~ /^(\d{4})(\d{2})$/) {
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

      push (@xml, "<date><min>".$mindate->datetime."</min><max>".$maxdate->datetime."</max></date>");

      # Convert dates to localtime
      $mindate = localtime($mindate->epoch);
      $maxdate = localtime($maxdate->epoch);
    } else {
      push (@xml, "<date delta='-7'>". $t->ymd ."</date>");
    }

    # Get the text param and unescape things like &amp; &quot;
    my $text = $q->param('text');
    if (defined $text) {
      push (@xml, "<text>$text</text>");
    }

    # Return either only faults filed or only faults responded to
    if ($q->param('action') =~ /response/) {
      push (@xml, "<isfault>0</isfault>");
    } elsif ($q->param('action') =~ /file/) {
      push (@xml, "<isfault>1</isfault>");
    }

    if ($q->param('timelost')) {
      push (@xml, "<timelost><min>.001</min></timelost>");
    }

    # Our query XML
    $xml = "<FaultQuery>" . join('',@xml) . "</FaultQuery>";

  } elsif ($q->param('major')) {
    # Faults within the last 14 days with 2 or more hours lost
    $xml = "<FaultQuery>".
      $comp->category_xml().
        "<date delta='-14'>" . $t->datetime . "</date><timelost><min>2</min></timelost></FaultQuery>";
  } elsif ($q->param('recent')) {
    # Faults active in the last 36 hours
    $xml = "<FaultQuery>".
      $comp->category_xml().
        "<date delta='-2'>" . $t->datetime . "</date></FaultQuery>";
  } elsif ($q->param('current')) {
    # Faults within the last 14 days
    $xml = $currentxml;
    $title = "Displaying faults with any activity in the last 14 days";
  } else {
    # Initial display of query page
    $xml = "<FaultQuery>".
      $comp->category_xml().
        "<date delta='-7'>" . $t->datetime . "</date></FaultQuery>";
    $title = "Displaying faults with any activity in the last 7 days";
  }

  my $faults;
  try {
    $faults = OMP::FaultServer->queryFaults($xml, "object");

    # If this is the initial display of faults and no recent faults were
    # returned, display faults for the last 14 days.
    if (! $q->param('faultsearch') and ! $faults->[0]) {
      $title = "No active faults in the last 7 days, displaying faults for the last 14 days";

      $faults = OMP::FaultServer->queryFaults($currentxml, "object");
    }

    return $faults;

  } otherwise {
    my $E = shift;
    print "$E";
  };

  # Generate a title based on the results returned
  if ($q->param('faultsearch')) {
    if ($faults->[1]) {
      $title = scalar(@$faults) . " faults returned matching your query";
    } elsif ($faults->[0]) {
      $title = "1 fault returned matching your query";
    } else {
      $title = "No faults found matching your query";
    }
  }

  # Show results as a summary if that option was checked
  if ($q->param('summary') and $faults->[0]) {
    $self->fault_summary_content($faults, $mindate, $maxdate);
  } elsif ($faults->[0]) {
    $comp->titlebar(["View Faults", $title]);

    $comp->query_fault_form($hidefields);
    print "<p>";

    # Total up and display time lost
    my $total_loss;
    for (@$faults) {
      $total_loss += $_->timelost;
    }

    print "<strong>Total time lost: $total_loss hours</strong>";

    print "<p>";

    # Make a link to this script with an argument to alter sort order
    my $sort_order = $self->_get_param('sort_order');
    if ($sort_order eq "ascending") {
      my $sort_url = $comp->url_args("sort_order", "ascending", "descending");
      print "Showing oldest/lowest first | <a href='$sort_url'>Show most recent/highest first</a>";
    } else {
      my $sort_url = $comp->url_args("sort_order", "descending", "ascending");
      print "<a href='$sort_url'>Show oldest/lowest first</a> | Showing most recent/highest first";
    }
    print "<br>";

    # Link to this script with an argument to alter sort criteria
    my $orderby = $self->_get_param('orderby');
    if ($orderby eq "filedate") {
      my $url = $comp->url_args("orderby", "filedate", "response");
      my $url2 = $comp->url_args("orderby", "filedate", "timelost");
      print "Sorted by date filed | <a href='$url'>Sort by date of latest response</a> | <a href='$url2'>Sort by time lost</a>";
    } elsif ($orderby eq "timelost") {
      my $url = $comp->url_args("orderby", "timelost", "filedate");
      my $url2 = $comp->url_args("orderby", "timelost", "response");
      print "<a href='$url'>Sort by file date</a> | <a href='$url2'>Sort by date of latest response</a> | Sorted by time lost</a>";
    } else {
      my $url = $comp->url_args("orderby", "response", "filedate");
      my $url2 = $comp->url_args("orderby", "response", "timelost");
      print "<a href='$url'>Sort by file date</a> | Sorted by date of latest response | <a href='$url2'>Sort by time lost</a>";
    }

    print "<p>";

    my $category = $self->_get_param('cat');
    my %showfaultargs = (
                         faults => $faults,
                         showcat => ($category ne 'ANYCAT' ? 0 : 1),
                        );

    if ($orderby eq 'response' or ! defined $orderby) {
      $showfaultargs{orderby} = 'response';
    } elsif ($q->param('orderby') eq 'filedate') {
      $showfaultargs{orderby} = 'filedate';
    } elsif ($q->param('orderby') eq 'timelost') {
      $showfaultargs{orderby} = 'timelost';
    }

    if ($faults->[0]) {
      unless ($sort_order eq "ascending") {
        $showfaultargs{descending} = 1;
      }

      $comp->show_faults(%showfaultargs);

      # Faults to print
      my @faultids = map{$_->id} @$faults;

      $comp->print_form(1, @faultids);

      # Put up the query form again if there are lots of faults displayed
      if ($faults->[15]) {
        print "<P>";
        $comp->query_fault_form($hidefields);
      }
    }
  } else {
    $comp->titlebar(["View Faults", $title]);
    $comp->query_fault_form($hidefields);
  }
}

=item B<view_fault_content>

Display a page showing a fault and providing a form for responding
to the fault.

  $fp->view_fault_content();

=cut

sub view_fault_content {
  my $self = shift;
  my $q = $self->cgi;
  my $comp = $self->fault_component;

  # First try and get the fault ID from the sidebar form param, then
  # try and get it from the URL or from the regular form param
  my $faultid;
  if ($q->param('goto_fault')) {
    $faultid = $q->param('goto_fault');
  } else {
    $faultid = $q->param('id');
    (! $faultid) and $faultid = $q->url_param('id');
  }

  # If we still havent gotten the fault ID, put up a form and ask for it
  if (!$faultid) {
    $comp->view_fault_form();
  } else {
    # Got the fault ID, so display the fault
    my $fault = OMP::FaultServer->getFault($faultid);

    # Don't go any further if we got undef back instead of a fault
    if (! $fault) {
      print "No fault with ID of [$faultid] exists.";
      $comp->view_fault_form();
      return;
    }

    # Send the fault to a printer if print button was clicked
    if ($q->param('print')) {
      my $printer = $q->param('printer');
      my @fprint = split(',',$q->param('faults'));

      OMP::FaultUtil->print_faults($printer, 0, @fprint);
      $comp->titlebar(["View Fault: $faultid", "Fault sent to printer $printer"]);
      return;
    }

    $comp->titlebar(["View Fault: $faultid", $fault->subject]);
    $comp->fault_table($fault);

    print "<br>";

    # Show form for printing this fault
    my @faults = ($fault->id);
    $comp->print_form(0, @faults);

    # Response form
    print "<p><b><font size=+1>Respond to this fault</font></b>";
    $comp->response_form(fault => $fault);

  }
}

=item B<view_fault_output>

Process the view_fault_content "respond" and "close fault" forms

  $fp->view_fault_output();

=cut

sub view_fault_output {
  my $self = shift;
  my $q = $self->cgi;
  my $comp = $self->fault_component;

  my @title;

  my $faultid = $q->param('faultid');
  my $fault = OMP::FaultServer->getFault($faultid);

  if ($q->param('respond')) {
    # Get the form key
    my $formkey = $q->param('formkey');

    # Croak if key is invalid
    my $verifykey = OMP::KeyServer->verifyKey($formkey);
    croak "Key is invalid [perhaps you already submitted this form?]"
      unless ($verifykey);

    # Make sure all the necessary params were provided
    my %params = (User => "user",
                  Response => "text",);
    my @error;
    for (keys %params) {
      if (length($q->param($params{$_})) < 1) {
        push @error, $_;
      }
    }

    # Put the form back up if params are missing
    if ($error[0]) {
      push @title, "The following fields were not filled in:";
      $comp->titlebar(["View Fault ID: $faultid", join('<br>',@title)]);
      print "<ul>";
      print map {"<li>$_"} @error;
      print "</ul>";
      $comp->response_form(fault => $fault);
      $comp->fault_table($fault);
      return;
    }

    # Response author
    my $user = new OMP::User(userid => $q->param('user'));

    # Get the status (possibly changed)
    my $status = $q->param('status');

    # Now update the status if necessary
    if ($status != $fault->status) {
      # Lookup table for status
      my %status =
        ( OMP::Fault->faultStatus(),
          OMP::Fault->faultStatus_Safety,
          OMP::Fault->faultStatus_JCMTEvents
        );

      # Change status in fault object
      $fault->status($status);

      my $E;
      try {
        # Resubmit fault with new status
        OMP::FaultServer->updateFault($fault);
        push @title, "Fault status changed to \"" . $fault->statusText . "\"";
      } otherwise {
        $E = shift;
        push @title, "An error prevented the fault status from being updated: $E";
      };

    }

    # The text.  Put it in <pre> tags if there isn't an <html>
    # tag present
    my $text = $q->param('text');
    if ($text =~ /<html>/i) {

      # Strip out the <html> and </html> tags
      $text =~ s!</*html>!!ig;
    } else {
      $text = OMP::General->preify_text($text);
    }

    # Strip out ^M
    $text =~ s/\015//g;

    my $E;
    try {
      my $resp = new OMP::Fault::Response(author => $user,
                                          text => $text);
      OMP::FaultServer->respondFault($fault->id, $resp);

      push @title, "Fault response successfully submitted";
    } otherwise {
      $E = shift;
      push @title, "An error has prevented your response from being filed: $E";

    };

    # Encountered an error, redisplay form
    if ($E) {
      $comp->titlebar(["View Fault ID: $faultid", join('<br>',@title)]);
      $comp->response_form(fault => $fault,);
      $comp->fault_table($fault);
      return;
    }

    # Remove key
    OMP::KeyServer->removeKey($formkey);

  } elsif ($q->param('change_status')) {

    # Lookup table for status
    my %status = OMP::Fault->faultStatus();

    my $status = $q->param('status');

    if ($status != $fault->status) {
      # Get host (and user maybe) info
      my @user = OMP::General->determine_host;
      my $author;

      # Make author either an email address or "user on [machine name]"
      if ($user[2] =~ /@/) {
        $author = $user[0];
      } else {
        $author = "user on $user[2]";
      }

     try {
        # Right now we'll just do an update by resubmitting the fault
        # with the new status parameter.  But in principal we should
        # have a method for doing an explicit status update.

        # Change the status parameter
        $fault->status($q->param('status'));

        # Resubmit the fault
        OMP::FaultServer->updateFault($fault, $author);

        push @title, "Fault status changed to \"" . $fault->statusText . "\"";
      } otherwise {
        my $E = shift;
        push @title, "An error has prevented the fault status from being updated: $E";
      };
    } else {
      # Status is the same, dont update
      push @title, "This fault already has a status of \"" . $fault->statusText . "\"";
    }
  }

  $fault = OMP::FaultServer->getFault($faultid);

  $comp->titlebar(["View Fault ID: $faultid", join('<br>',@title)]);

  $comp->fault_table($fault);
  print "<br>";

  # Form for printing
  my @faults = ($fault->id);
  $comp->print_form(0, @faults);
}

=item B<update_fault_content>

Display a page with a form for updating fault details

  $fp->update_fault_content();

=cut

sub update_fault_content {
  my $self = shift;
  my $q = $self->cgi;
  my $comp = $self->fault_component;
  my $faultid = $self->_get_param('id');

  # Try to get the fault ID from the URL first.
  # If we didn't get it, try and get it from our form
  (! $faultid) and $faultid = $q->param('id');

  # Still didn't get the fault ID so put this form up
  if (!$faultid) {
    print $q->h2("Update a fault");
    print "<table border=0><tr><td>";
    print $q->startform;
    print "<b>Enter a fault ID: </b></td><td>";
    print $q->textfield(-name=>'id',
                        -size=>15,
                        -maxlength=>32);
    print "</td><tr><td colspan=2 align=right>";
    print $q->submit(-name=>'Submit');
    print $q->endform;
    print "</td></table>";
  } else {

    $comp->titlebar(["Update Fault [$faultid]"]);

    # Get the fault
    my $fault = OMP::FaultServer->getFault($faultid);

    # Form for taking new details.  Displays current values.
    $comp->file_fault_form(fault => $fault);
  }
}

=item B<update_fault_output>

Take parameters from the fault update content page and update
the fault.

  $fp->update_fault_output();

=cut

sub update_fault_output {
  my $self = shift;
  my $q = $self->cgi;
  my $comp = $self->fault_component;

  # For the titlebar
  my @title;

  my $faultid = $q->param('faultid');

  # Get host (and user maybe) info of the user who is modifying the fault
  my @user = OMP::General->determine_host;
  my $author;

  # Make author either an email address or "user on [machine name]"
  if ($user[2] =~ /@/) {
    $author = $user[0];
  } else {
    $author = "user on $user[2]";
  }

  # Get the original fault
  my $fault = OMP::FaultServer->getFault($faultid);

  # Get new properties
  my %newdetails = $comp->parse_file_fault_form();

  # Store details in a fault object for comparison
  my $category = $self->_get_param('cat');
  my $new_f = new OMP::Fault(category=>$category,
                             fault=>$fault->responses->[0],
                             %newdetails);

  my @details_changed = OMP::FaultUtil->compare($new_f, $fault);

  # Store details in a fault response object for comparison
  my $new_r = new OMP::Fault::Response(%newdetails);

  # Our original response
  my $response = $fault->responses->[0];

  # "Preify" the text before we compare responses
  my $newtext = $newdetails{text};
  $newtext =~ s!</*html>!!ig;
  $newtext = OMP::General->preify_text($newtext);

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
        OMP::FaultServer->updateFault($fault, $author);
      }

      if ($response_changed[0]) {

        # Apply changes to response
        for (@response_changed) {
          $response->$_($newdetails{$_});
        }

        OMP::FaultServer->updateResponse($fault->id, $response);
      }

      push @title, "This fault has been updated";

      # Get the fault in it's new form
      $fault = OMP::FaultServer->getFault($faultid);

    } otherwise {
      $E = shift;
      push @title, "An error has occurred which prevented the fault from being updated";
      push @title, "$E";
    };
  } else {
    push @title, "No changes were made";
  }

  $comp->titlebar(["Update Fault [". $fault-> id ."]", join('<br>',@title)]);

  # Display the fault
  $comp->fault_table($fault);
}

=item B<update_resp_content>

Create a form for updating fault details

  $fp->update_resp_content();

=cut

sub update_resp_content {
  my $self = shift;
  my $q = $self->cgi;
  my $comp = $self->fault_component;

  my $faultid = $q->url_param('id');
  my $respid = $q->url_param('respid');

  if ($faultid and $respid) {
    $comp->titlebar(["Update Response [$faultid]"]);

    # Get the fault
    my $fault = OMP::FaultServer->getFault($faultid);

    (! $fault) and croak "Unable to retrieve fault with ID [$faultid]\n";

    # Form for taking new details.  Displays current values.
    $comp->response_form(fault => $fault,
                         respid => $respid,);
  } else {
    croak "A fault ID and response ID must be provided in the URL\n";
  }
}

=item B<update_resp_output>

Submit changes to a fault response.

  $fp->update_resp_output();

=cut

sub update_resp_output {
  my $self = shift;
  my $q = $self->cgi;
  my $comp = $self->fault_component;

  my $faultid = $q->param('faultid');
  my $respid = $q->param('respid');
  my $text = $q->param('text');
  my $author = $q->param('user');

  # User may be a hidden param
  (! $author) and $author = $q->param('user_hidden');

  # Convert author to OMP::User object
  $author = OMP::UserServer->getUser($author);

  # Prepare the text
  if ($text =~ /<html>/i) {
    # Strip out the <html> and </html> tags
    $text =~ s!</*html>!!ig;
  } else {
    $text = OMP::General->preify_text($text);
  }

  # Strip out ^M
  $text =~ s/\015//g;

  # Get the fault
  my $fault = OMP::FaultServer->getFault($faultid);

  # Get the response object
  my $response = OMP::FaultUtil->getResponse($respid, $fault);

  # Make changes to the response object
  $response->author($author);
  $response->text($text);

  # SHOULD DO A COMPARISON TO SEE IF CHANGES WERE ACTUALLY MADE

  # Submit the changes
  my @title = ("Update Response");
  try {
    OMP::FaultServer->updateResponse($faultid, $response);
    push @title, "Response has been updated"
  } otherwise {
    my $E = shift;
    push @title, "Unable to update response";
    print "<pre>$E</pre>";
  };

  $comp->titlebar(\@title);

  # Redisplay fault
  $fault = OMP::FaultServer->getFault($faultid);

  $comp->fault_table($fault);
}

=item B<fault_summary_content>

Create a page summarizing faults for a particular category, or all categories.

  fault_summary_content( [ $faults | $mindate , $maxdate ] );

First optional argument is an array of C<OMP::Fault> objects.  If the first
argument is not provided, a query will be done for faults within the
current month.  The second and third arguments, each a C<Time::Piece> object,
can be provided to display the date range used for the query that returned
the faults provided as the first argument.

=cut

sub fault_summary_content {
  my $self = shift;
  my $faults = shift;
  my $mindate = shift;
  my $maxdate = shift;
  my $q = $self->cgi;
  my $category = $q->param('category');
  my $ompurl = OMP::Config->getData('omp-url');
  my $iconurl = $ompurl . OMP::Config->getData('iconsdir');
  my %status = OMP::Fault->faultStatus;
  my %statusOpen = OMP::Fault->faultStatusOpen;

  if (! $faults) {
    # Generate the date portion of our XML query
    my $queryDateStr;
    my $today = localtime;
    my $period;
    if ($q->param('period') eq 'last_month') {
      # Get results for the period between the first
      # and last days of the last month
      my $today = localtime;
      my $year;
      my $month;
      if ($today->strftime("%Y%m") =~ /^(\d{4})(\d{2})$/) {
        $year = $1;
        $month = $2;
      }

      $month -= 1;
      if ($month eq 0) {
        $month = 12;
        $year -= 1;
      }

      my $beginDate = Time::Piece->strptime($year . $month . "01", "%Y%m%d");
      my $endDate = $year . "-" . $month . "-" . $beginDate->month_last_day . "T23:59:59";
      $queryDateStr = "<date><min>".$beginDate->datetime."</min><max>$endDate</max></date>";
      $period = $beginDate->monname ." ". $beginDate->year;
    } else {
      # Get results between today and N days ago
      my $days = $q->param('days');
      (! $days) and $days = 7;

      $queryDateStr = "<date delta='-".$days."'>" . $today->datetime . "</date>";
      $period = "the past $days days";
    }


    # Construct our fault query
    my $xml = "<FaultQuery>".
      "<category>$category</category>".
        $queryDateStr.
          "<isfault>1</isfault>".
            "</FaultQuery>";

    # Run the query
    $faults = OMP::FaultServer->queryFaults($xml, 'object');

    # Title
    print "<h2>$category fault summary for $period</h2>";
  }

  # Check that we got some faults back
  if (! $faults->[0]) {
    print "<h3>No faults were filed during this period</h3>";
    return;
  }

  # Store faults by system and type
  my %faults;
  my %totals;
  my %timelost;
  my %sysID; # IDs used to identify table rows that belong to a particular system
  my %typeID; # IDs used to identify table rows that belong to a particular type
  my $timelost = 0;
  my $totalfiled = 0;
  $totals{open} = 0;

  for (@$faults) {

    $totals{$_->systemText}++;
    $timelost += $_->timelost;

    # Keep track of number of faults that were filed during the query period
    my $filedate = $_->responses->[0]->date;
    if ($mindate and $maxdate) {
      ($filedate->epoch >= $mindate->epoch and $filedate->epoch <= $maxdate->epoch) and $totalfiled++;
    }

    # Store open faults and closed major faults
    my $status;
    if (exists $statusOpen{$_->statusText}) {
      $status = 'open';
    } else {
      $status = 'closed';
      $sysID{$_->systemText} = sprintf("%08d",$_->system) . "sys";
    }

    $typeID{$_->typeText} = sprintf("%08d",$_->type) . "type";
    push (@{$faults{$_->systemText}{$status}{$_->typeText}}, $_);
    $totals{$status}++;

    $timelost{$status}{$_->systemText} += $_->timelost;
  }

  # Totals
  print "<table cellspacing=1><td>";

  print "<strong>Faults returned by query: </strong>".scalar(@$faults);
  if ($mindate and $maxdate) {
    print "<br><strong>Query period: </strong>".$mindate->strftime("%Y%m%d %H:%M") ." - ". $maxdate->strftime("%Y%m%d %H:%M %Z");
    print "<br><strong>Matching faults filed in period: </strong>$totalfiled";
  }

  print "<br><strong>Total time lost:</strong> $timelost hours";
  print "<br><strong>Open faults:</strong> $totals{open}";
  print "</td></table><br>";

  # First show all open, then all major closed
  print "<table bgcolor=#afafe0 cellspacing=1><td>";
  print "<table width=100% cellspacing=0 cellpadding=2 border=0><td colspan=7><font size=+1><strong>";

  print "All faults";

  print "</strong></font>";

  # Don't hide closed faults if we only have closed faults
  my $toggleDef;
  my $toggleText;
  my $class;
  if ($totals{open} > 0) {
    $toggleDef = 'show';
    $class = 'hide';
    $toggleText = "Show closed faults";
  } else {
    $toggleDef = 'hide';
    $class = 'show';
    $toggleText = "Hide closed faults";
  }

  # Create argument list for calling toggle script
  my $argumentStr = join(",", map {"'$sysID{$_}'"} keys %sysID);
  $argumentStr = "'function__toggleClosed'," . $argumentStr;

  # Create link for toggling display of all closed faults
  if ($totals{closed} > 0 and $totals{open} > 0) {
    print "&nbsp;<a href=\"#\" class=\"link_option\" onclick=\"toggle($argumentStr); return false\"><img border=\"0\" src=\"$iconurl/$toggleDef.gif\" width=\"10\" height=\"10\" id=\"imgfunction__toggleClosed\"></a>";
    print "&nbsp;<a href=\"#\" class=\"link_option\" onclick=\"toggle($argumentStr); return false\"><span id=\"function__toggleClosed\" function=\"$toggleDef\">$toggleText</span></a>";
    print "</td>";
  }

  # Display faults by system
  for my $system (sort keys %faults) {
    print "<tr><td colspan=2 class='row_system_title'>$system <span class='misc_info'>(total: $totals{$system})</span></td>";
    print "<td class='row_system'>Filed by</td>";
    print "<td class='row_system'>Last response by</td>";
    print "<td class='row_system'>Time lost</td>";
    print "<td class='row_system'>Responses</td>";
    print "<td class='row_system'>Days idle</td>";

    my $systemTimeLost = 0;

    for my $status (qw/open closed/) {

      next if (! $faults{$system}{$status});

      # Use different background colors for different statuses
      my $bgcolor;
      ($status eq 'open') and $bgcolor = '#8080cc'
        or $bgcolor = '#6767af';

      # Make a button for toggling view of closed faults
      if ($status eq 'closed') {
        print "<tr>";
        print "<td class='row_closed_title' colspan=4>";
        print "<a class=\"link_option\" href=\"#\" onclick=\"toggle('$sysID{$system}'); return false\"><img border=\"0\" src=\"$iconurl/$toggleDef.gif\" width=\"10\" height=\"10\" id=\"img$sysID{$system}\"></a>";
        print "&nbsp;<a class=\"link_option\" href=\"#\" onclick=\"toggle('$sysID{$system}'); return false\">Closed faults</a></td>";
        print "<td class='row_closed'><span id=\"info$sysID{$system}\" value=\"$timelost{$status}{$system}\">";
        ($class eq 'hide') and print $timelost{$status}{$system};
        print "</span>&nbsp;</td><td colspan=2 class='row_closed'>&nbsp;</td>";
        print "</tr>";
      }

      for my $type (sort keys %{$faults{$system}{$status}}) {

        my $rowID = $sysID{$system} . "_" . $typeID{$type};

        ($status eq 'closed') and print "<tr id=\"$rowID\" class=\"$class\">"
          or print "<tr>";

        print "<td bgcolor=$bgcolor colspan=7><font color=$bgcolor>----</font><strong><span class=\"fault_summary_misc\">$type</span></strong></td>";

        my $count = 0;

        for my $fault (@{$faults{$system}{$status}{$type}}) {

          $count++;

          # Find out how long since the last response
          my $localtime = localtime;
          my $locallast = localtime($fault->responses->[-1]->date->epoch);
          my $lastresponse = $localtime - $locallast;
          $lastresponse = sprintf("%d", $lastresponse->days);
          $systemTimeLost += $fault->timelost;

          # Setup the preview
          my $preview = substr($fault->responses->[0]->text, 0, 87);
          $preview = OMP::General->html_to_plain($preview);
          $preview =~ s/\"/\'\'/gi;
          $preview =~ s/\s+/ /gi;

          my $subject = ($fault->subject) ? $fault->subject : "No subject";

          my $author = OMP::Display->userhtml($fault->responses->[0]->author, $q);
          my $respAuthor;
          ($fault->responses->[1]) and
            $respAuthor = OMP::Display->userhtml($fault->responses->[-1]->author, $q);

          my $faultRowID = $rowID . "_" . $count;

          ($status eq 'closed') and print "<tr id=\"$faultRowID\" class=\"$class\""
            or print "<tr ";

          print "bgcolor=$bgcolor><td><font color=$bgcolor>------</font>";
          ($fault->timelost > 0) and print "<img src=$iconurl/timelost.gif alt=\"Fault lost time\">"
            or print "<img src=$iconurl/spacer.gif height=13 width=10>";
          print " <a href=\"viewfault.pl?id=".$fault->id."\" class=\"link_fault_id\" title=\"$preview\">". $fault->id ."</td>";
          print "<td><a href=\"viewfault.pl?id=".$fault->id."\" class=\"link_fault_subject\" title=\"$preview\">". $subject ."</a>";

          # Show affected projects?
          if ($q->param('show_affected') and $fault->projects) {
            print "<br><span class='proj_fault_link'>";
            my @projlinks = map {"<a href='projecthome.pl?urlprojid=$_'>$_</a>"} $fault->projects;
            print join (" | ", @projlinks);
            print "</span>";
          }

          print "</td>";
          print "<td align=right class='fault_summary_userid'>". $fault->responses->[0]->author->html . "</td>";
          print "<td align=right class='fault_summary_userid'>";
          ($respAuthor) and print $respAuthor
            or print "n/a";
          print "</td>";
          print "<td align=right><span class='fault_numbers'>". $fault->timelost ."</span></td>";
          print "<td align=right><span class='fault_numbers'>". $#{$fault->responses} ."</span></td>";
          print "<td align=right><span class='fault_numbers'>". $lastresponse ."</span></td>";
        }
      }
    }
    # Total time lost for system
    print "<tr bgcolor=#afafe0><td colspan=4 align=right>Total time lost</td><td align=right><span class='fault_total'>$systemTimeLost</span></td><td colspan=2></td>";

  }
  print "</tr></table>";
  print "</table>";
}

=item B<write_page>

Creates a fault system web page.  See documentation for the write_page method
in C<OMP::CGI> for more details.

=cut

sub write_page {
  my $self = shift;
  my @args = @_;
  my $q = $self->cgi;

  if ($q->param('goto_fault')) {
    my $gfaultid = $q->param('goto_fault');

    # Create redirect header
    print $q->redirect($q->url(-base=>1) . "/cgi-bin/viewfault.pl?id=$gfaultid");
    print "Redirecting...";
    print $self->_write_footer();
    return;
  }

  $self->SUPER::write_page(@args);
}

=back

=head2 Internal methods

=over 4

=item B<_get_default_cookie_params>

Return a hash containing key/value pairs of parameters to store to the
default cookie.

  %params = $cgi->_get_default_cookie_params()

=cut

sub _get_default_cookie_params {
  my $self = shift;
  my $q = $self->cgi;
  my %params;

  # If a 'user' field has been filled in store that value in the cookie
  if ($q->param('user')) {
    $params{user} = $q->param('user');
  }

  if ($q->param('sort_order')) {
    $params{sort_order} = $q->param('sort_order');
  }

  if ($q->url_param('id')) {
    # If there is a fault ID in the URL get the fault and set the
    # cookie category to whatever category the fault is
    my $fault;
    my $faultid = $q->url_param('id');
    my $E;
    try {
      $fault = OMP::FaultServer->getFault($faultid);
    } otherwise {
      $E = shift;
      croak "Unable to retrieve fault $faultid [$E]";
    };

    croak ("Unable to retrieve fault with id [$faultid]")
      unless (defined $fault);

    $params{cat} = $fault->category;
  } elsif ($q->param('cat')) {
    # Otherwise, store the 'cat' url parameter
    my %categories = map {uc($_), undef} OMP::Fault->faultCategories;
    my $cat = uc($q->param('cat'));
    $params{cat} = $cat
      if (exists $categories{$cat} or $cat eq 'ANYCAT');
  }

  return %params;
}

=item B<_sidebar>

Create and display fault system sidebar.

  $fcgi->_sidebar()

=cut

sub _sidebar {
  my $self = shift;
  my $theme = $self->theme;
  my $q = $self->cgi;
  my $cat = $self->_get_param('cat');

  my $suffix =
    $cat =~ /events/i
    ? ''
    : 'safety' eq lc $cat
      ? 'Reporting'
      : 'Faults'
      ;

  my $title =
    defined $cat && uc $cat ne 'ANYCAT'
    ? "$cat $suffix"
    : 'Select a fault system';

  if ( $title =~ /_log/i ) {

    $title =~ tr/_/ /;
  }

   $title = qq[<font color="#ffffff">$title</font>];

  $theme->SetMoreLinksTitle($title);

  # Construct our HTML for the sidebar fault form
  my $sidebarform =
    "<br><font color=#ffffff>Fault ID:</font><br>".
      $q->start_form .
      $q->textfield(-name=>'goto_fault',
                    -size=>14,
                    -maxlength=>20,) .
                      "<br><br>" .
                        $q->submit("View Fault") .
                          $q->end_form ;

  my @sidebarlinks;
  my %query_link = $self->_fault_sys_links;
  for my $c ( $self->_fault_sys_links_order ) {

    next if 'anycat' eq lc $c;

    push @sidebarlinks,
      $self->_make_side_link( map { $query_link{ $c }->{ $_ } } qw[ url text ] );
  }

  push @sidebarlinks,
    $self->_make_side_link( $query_link{'ANYCAT'}->{'url'}, 'All Faults', '<br><br>' ),
    $self->_make_side_link( OMP::Config->getData('omp-url'), 'OMP home' ),
    $sidebarform . '</font>'
    ;

  if (defined $cat and uc $cat ne "ANYCAT") {

    my ( $text, $prop ) = ( 'fault', 'a' );
    if ( $cat =~ /event/i ) {

      $text = 'event';
      $prop = 'an';
    }

    unshift @sidebarlinks,
      $self->_make_side_link( qq[filefault.pl?cat=$cat], qq[File $prop $text] ),
      $self->_make_side_link( $query_link{ uc $cat }->{'url'}, qq[View ${text}s], '<br><br>' )
      ;
  }

  $theme->SetInfoLinks(\@sidebarlinks);
}

sub _make_side_link {

  my ( $self, $url, $text, $suffix, $prefix ) = @_;

  for ( $prefix, $suffix ) {

    $_ or $_ = '';
  }

  return
    sprintf q[%s<a class="sidemain" href="%s">%s</a>%s],
      $prefix,
      $url,
      $text,
      $suffix
      ;
}


=item B<_verify_login>

Return 1 if login details are correct.  This does not check for
correct passwords but rather that a category for browsing is defined
and valid.

  $verify = $fcgi->_verify_login()

=cut

sub _verify_login {
  my $self = shift;
  my $q = $self->cgi;
  my $category = $self->_get_param('cat');

  my %validcat = map {uc($_), undef} OMP::Fault->faultCategories;
  $validcat{ANYCAT} = undef;

  if (exists $validcat{$category}) {
    return 1;
  } else {
    return 0;
  }
}

=item B<_write_login>

Create and display a page for choosing a fault category to browse
and interact with.

  $fcgi->_write_login()

=cut

sub _write_login {
  my $self = shift;
  my $q = $self->cgi;

  # Set up the sidebar, otherwise the default sidebar will appear
  $self->_sidebar();

  $self->_write_header();

  # Create a page body with some links to fault categories
  print $q->h2("You may search for and file faults in the following categories:");
  print "<ul>";

  my %query = $self->_fault_sys_links;
  my $format = qq[<li><h3><a href="%s">%s<a/> for %s</h3>\n];

  for my $cat ( $self->_fault_sys_links_order ) {

    next if 'anycat' eq lc $cat;

    printf $format, map { $query{ $cat }->{ $_ } } qw[ url text extra ];
  }

  print "</ul>";
  print $q->h2("Or");
  print "<ul>";

  printf $format,
    $query{'ANYCAT'}->{'url'},
    'Search',
    $query{'ANYCAT'}->{'extra'}
    ;

  print "</ul>";

  $self->_write_footer();
  return;
}

BEGIN {

  my @order = qw[ CSG OMP UKIRT JCMT JCMT_EVENTS DR FACILITY SAFETY ];
  push @order, 'ANYCAT';

  my %long_text =
    ( 'CSG'      => 'JAC computer services',
      'OMP'      => 'Observation Management Project',
      'UKIRT'    => 'UKIRT',
      'JCMT'     => 'JCMT',
      'JCMT_EVENTS' => 'JCMT events',
      'DR'       => 'data reduction systems',
      'FACILITY' => 'facilities',
      'SAFETY'   => 'safety',
      'ANYCAT'   => 'all categories',
    );

  sub _fault_sys_links {

    my %links;
    for my $type ( @order ) {

      next if grep { $type eq $_ } ( 'SAFETY', 'JCMT_EVENTS' );

      $links{ $type } =
        { 'url'   => "queryfault.pl?cat=$type",
          'text'  => "$type Faults",
          'extra' => 'faults relating to ' . $long_text{ $type }
        };
    }

    $links{'SAFETY'} =
      { 'url'   => 'queryfault.pl?cat=SAFETY',
        'text'  => 'Safety Reporting',
        'extra' => 'issues relating to safety'
      };

    $links{'JCMT_EVENTS'} =
      { 'url'   => 'queryfault.pl?cat=JCMT_EVENTS',
        'text'  => 'JCMT Events',
        'extra' => 'event logging for JCMT'
      };

    #  Fine tune 'ANYCAT' description.
    $links{'ANYCAT'}->{'extra'} = 'faults in all categories';

    return %links;
  }

  sub _fault_sys_links_order {

    my ( $self ) = @_;
    return @order;
  }
}

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
along with this program (see SLA_CONDITIONS); if not, write to the
Free Software Foundation, Inc., 59 Temple Place, Suite 330,
Boston, MA  02111-1307  USA

=cut

1;
