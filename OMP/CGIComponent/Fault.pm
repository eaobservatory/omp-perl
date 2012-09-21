package OMP::CGIComponent::Fault;

=head1 NAME

OMP::CGIComponent::Fault - Components for fault system web pages

=head1 SYNOPSIS

  use OMP::CGIComponent::Fault;

  $query = new CGI;

  $comp = new OMP::CGIComponent::Fault(CGI => $query,
                                       category => $category,);

=head1 DESCRIPTION

Provide methods to generate and display components of fault system web pages.
Methods are also provided for parsing input taken forms displayed on the
web pages.  This class inherits from C<OMP::CGIComponent>.

=cut

use 5.006;
use strict;
use warnings;
use Carp;

use Text::Wrap;

use OMP::Config;
use OMP::Display;
use OMP::DateTools;
use OMP::General;
use OMP::Error qw(:try);
use OMP::Fault;
use OMP::FaultDB;
use OMP::FaultServer;
use OMP::FaultGroup;
use OMP::FaultUtil;
use OMP::KeyServer;
use OMP::MSBServer;
use OMP::UserServer;

use base qw(OMP::CGIComponent);

our $VERSION = (qw$ Revision: 1.2 $ )[1];

# Text wrap column size
$Text::Wrap::columns = 80;

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

Create a new instance of an C<OMP::CGIComponent::Fault> object.

  $comp = new OMP::CGIComponent::Fault( CGI => $q );

=cut

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;

  # Read the arguments
  my %args;
  %args = @_ if @_;

  # Call our parent class's constructor
  my $self = $class->SUPER::new();

  # Add some instance attributes
  $self->{Category} = undef;
  $self->{User} = undef;

  my $object = bless $self, $class; # Reconsecrate

  # Populate object
  for my $key (keys %args) {
    my $method = lc($key);
    $object->$method($args{$key});
  }

  return $object;
}

=back

=head2 Accessor methods

=over 4

=item B<category>

The currently selected fault category.

  $category = $comp->category()
  $comp->category($category)

Argument is a string that is a category name.  Returns a string,
or undef if not defined.

=cut

sub category {
  my $self = shift;
  if (@_) {
    $self->{Category} = shift;
  }
  return $self->{Category};
}

=item B<user>

User ID of the current user.

  $userid = $comp->user()
  $comp->user($userid)

Argument is a string that is an OMP user ID.  Returns a string,
or undef if not defined.

=cut

sub user {
  my $self = shift;
  if (@_) {
    $self->{User} = shift;
  }
  return $self->{User};
}

=back

=head2 Content Creation and Display Methods

=over 4

=item B<fault_table>

Put a fault into a an HTML table

  $fcomp->fault_table($fault, 'noedit')

Takes an C<OMP::Fault> object as the second argument.  Takes a third argument
which is a string of either "noedit" or "nostatus".  "noedit" displays the fault without links for updating the text and details, and without the status update form.  "nostatus" displays the fault just without the status update form.

=cut

sub fault_table {
  my $self = shift;
  my $fault = shift;
  my $option = shift;
  my $q = $self->cgi;

  my $nostatus;
  my $noedit;

  if ($option =~ /noedit/) {
    $noedit = 1;
  } elsif ($option =~ /nostatus/) {
    $nostatus = 1;
  }

  my $subject;
  ($fault->subject) and $subject = $fault->subject
    or $subject = "none";

  # Get file date as local time
  my $filedate = localtime($fault->filedate->epoch);
  $filedate = OMP::DateTools->display_date($filedate);

  my $faultdate = $fault->faultdate;
  if ($faultdate) {
    # Convert fault date to local time
    my $epoch = $faultdate->epoch;
    $faultdate = localtime($epoch);
    $faultdate = OMP::DateTools->display_date($faultdate);
  } else {
    $faultdate = "unknown";
  }

  my $urgencyhtml;
  ($fault->isUrgent) and $urgencyhtml = "<b><font color=#d10000>THIS FAULT IS URGENT</font></b>";

  # Get available statuses
  my ( $labels, $values ) = $self->get_status_labels( $fault );

  my $width = $self->_get_table_width;
  # First show the fault info
  my $sys_text = _get_system_label( $fault->category );

  print "<div class='black'>";
  print $q->startform;
  print "<table width=$width bgcolor=#6161aa cellspacing=1 cellpadding=0 border=0><td><b class='white'>Report by: " . OMP::Display->userhtml($fault->author, $q) . "</b></td>";
  print "<tr><td>";
  print "<table cellpadding=3 cellspacing=0 border=0 width=100%>";
  print "<tr bgcolor=#ffffff><td><b>Date filed: </b>$filedate</td><td><b>"
    . qq[${sys_text}:]
    . '</b> ' . $fault->systemText . '</td>'
    ;

  print "<tr bgcolor=#ffffff><td><b>Loss: </b>" . $fault->timelost . " hours</td><td><b>Fault type: </b>" . $fault->typeText . "</td>";
  print "<tr bgcolor=#ffffff><td><b>Actual time of failure: </b>$faultdate</td><td><b>Status: </b>";

  unless ($noedit or $nostatus) {
    # Make a form element for changing the status
    print $q->hidden(-name=>'show_output', -default=>'true');
    print $q->hidden(-name=>'faultid', -default=>$fault->id);
    print $q->popup_menu(-name=>'status',
                         -default=>$fault->status,
                         -values=> $values,
                         -labels=> $labels,);
    print " ";
    print $q->submit(-name=>'change_status',
                     -label=>'Change',);
    print $q->endform;
  } else {
    # Display only
    print $fault->statusText;
  }
  print "</td>";

  # Display links to projects associated with this fault if any
  my @projects = $fault->projects;

  if ($projects[0]) {
    my @html = map {"<a href='projecthome.pl?urlprojid=$_'>$_</a>"} @projects;
    print "<tr bgcolor=#ffffff><td colspan=2><b>Projects associated with this fault: </b>";
    print join(', ',@html);
    print "</td>";
  }

  # Display if urgent
  print "<tr bgcolor=#ffffff><td>$urgencyhtml</td><td></td>";

  # Link to fault editing page
  if (! $noedit) {
    print "<tr bgcolor=#ffffff><td> </td><td><span class='editlink'><a href='updatefault.pl?id=". $fault->id ."'>Click here to update or edit this fault</a></span></td>";
  }

  # Then loop through and display each response
  my @responses = $fault->responses;
  for my $resp (@responses) {
    # Convert response date to local time
    my $respdate = $resp->date;
    my $epoch = $respdate->epoch;
    $respdate = localtime($epoch);
    $respdate = OMP::DateTools->display_date($respdate);

    # Make the cell bgcolor darker and dont show "Response by:" and "Date:" if the
    # response is the original fault
    my $bgcolor;
    if ($resp->isfault) {
      $bgcolor = '#bcbce2';
    } else {
      $bgcolor = '#dcdcf2';
      print "<tr bgcolor=$bgcolor><td><b>Response by: </b>" . OMP::Display->userhtml($resp->author, $q) . "</td><td><b>Date: </b>" . $respdate;

      # Link to respons editing page
      if (! $noedit) {
        print "&nbsp;&nbsp;&nbsp;&nbsp;<span class='editlink'><a href='updateresp.pl?id=".$fault->id."&respid=".$resp->id."'>Edit this response</a></span></td>";
      }
    }

    # Show the response

    # Word wrap the text if it is in a pre block
    my $text = $resp->text;
    if ($text =~ m!^<pre>.*?</pre>$!is) {
      $text = wrap('', '', $text);
    }

    # Now turn fault IDs into links
    $text =~ s!((?:199|2\d{2})\d[01]\d[0-3]\d\.\d{3})!<a href='viewfault.pl?id=$1'>$1</a>!g;

    print "<tr bgcolor=$bgcolor><td colspan=2><table border=0><tr><td><font color=$bgcolor>___</font></td><td>$text</td></table><br></td>";
  }
  print "</table>";
  print "</td></table>";
  print "</div>";
}

=item B<query_fault_form>

Create and display a form for querying faults.

  $fcgi->query_fault_form([$hidesystype]);

If the optional argument is true, no fields are provided for selecting
system/type (useful for non-category specific fault queries).

=cut

sub query_fault_form {
  my $self = shift;
  my $hidefields = shift;
  my $q = $self->cgi;

  # Get category
  my $category = $self->category;
  my $sys_label = _get_system_label( $category );

  my $systems;
  my $types;
  my @systems;
  my @types;
  my %syslabels;
  my %typelabels;

  if (! $hidefields) {
    $systems = OMP::Fault->faultSystems($category);
    @systems = map {$systems->{$_}} sort keys %$systems;
    unshift( @systems, "any" );
    %syslabels = map {$systems->{$_}, $_} %$systems;
    $syslabels{any} = 'Any';

    $types = OMP::Fault->faultTypes($category);
    @types = map {$types->{$_}} sort keys %$types;
    unshift( @types, "any");
    %typelabels = map {$types->{$_}, $_} %$types;
    $typelabels{any} = 'Any';
  }

  my ( %status, %statuslabels );
  {
    my ( $labels, $status ) = _get_status_labels_by_name( $category );
    %status = %{ $status };
    %statuslabels = %{ $labels };
  }

  my @status = map {$status{$_}} sort keys %status;
  unshift( @status, "any", "all_open", "all_closed");

  $statuslabels{any} = 'Any';
  $statuslabels{all_open} = 'All open';
  $statuslabels{all_closed} = 'All closed';

  # Get the date so we can figure out our local timezone
  my $today = localtime;

  print "<table cellspacing=0 cellpadding=3 border=0 bgcolor=#dcdcf2><tr><td colspan=2>";
  print $q->startform(-method=>'GET');
  print $q->hidden(-name=>'faultsearch', -default=>['true']);

  print "<b>Find faults ";
  print $q->radio_group(-name=>'action',
                        -values=>['response','file','activity'],
                        -default=>'activity',
                        -labels=>{response=>"responded to",
                                  file=>"filed",
                                  activity=>"with any activity"});
  print "</td><tr><td colspan=2><b>by user <small>(ID)</small> </b>";
  print $q->textfield(-name=>'author',
                      -size=>17,
                      -maxlength=>32,);
  print "</b></td><tr><td valign=top align=right><b>";
  print $q->radio_group(-name=>'period',
                        -values=>['arbitrary','days','last_month'],
                        -default=>'arbitrary',
                        -labels=>{arbitrary=>'between dates',days=>'in the last',last_month=>'in the last calendar month'},
                        -linebreak=>'true',);
  print "</b></td><td valign=top><b>";
  print "<small>(YYYYMMDD)</small> ";
  print $q->textfield(-name=>'mindate',
                      -size=>18,
                      -maxlength=>32);
  print " and ";
  print $q->textfield(-name=>'maxdate',
                      -size=>18,
                      -maxlength=>32);
  # Display the local timezone since date searches are localtime
  print " ". $today->strftime("%Z");
  print "<br>";
  print $q->textfield(-name=>'days',
                      -size=>3,
                      -maxlength=>4,);
  print " days";
  print "<br>";
  print "</b></td><tr><td colspan=2>";

  if (! $hidefields) {
    print '<b>' . $sys_label . '</b> ';
    print $q->popup_menu(-name=>'system',
                         -values=> \@systems,
                         -labels=>\%syslabels,
                         -default=>'any',);
    print " <b>Type</b> ";
    print $q->popup_menu(-name=>'type',
                         -values=>\@types,
                         -labels=>\%typelabels,
                         -default=>'any',);
  }

  print " <b>Status</b> ";
  print $q->popup_menu(-name=>'status',
                       -values=>\@status,
                       -labels=>\%statuslabels,
                       -default=>'any',);

  print "</td><tr><td colspan=2>";
  print "<b>";

  # Only display option to return time-losing faults if the category allows it
  if (OMP::Fault->faultCanLoseTime($self->category)) {
    print $q->checkbox(-name=>'timelost',
                       -value=>'true',
                       -label=>'Return time-losing faults only',
                       -checked=>0,);
    print "&nbsp;&nbsp;";
  }

  # Only display option to return affected projects if the category allows it
  if (OMP::Fault->faultCanAssocProjects($self->category)) {
    print $q->checkbox(-name=>'show_affected',
                       -value=>'true',
                       -label=>'Show affected projects',
                       -checked=>0,);
  }

  # Return chronic faults checkbox
  print "<br>";
  print $q->checkbox(-name=>'chronic',
                     -value=>'true',
                     -label=>'Return chronic faults only',
                     -checked=>0,);

  print "<br>";
  print $q->checkbox(-name=>'summary',
                     -value=>'true',
                     -label=>'Organize by system/type',
                     -checked=>0,);
  print "</b></td><tr><td colspan=2>";
  print $q->textfield(-name=>'text',
                      -size=>44,
                      -maxlength=>256,);
  print "&nbsp;&nbsp;";
  print $q->submit(-name=>"search", -label=>"Search",);
  print "</b></td>";

  # Need the show_output hidden field in order for the form to be processed
  print $q->hidden(-name=>'show_output', -default=>['true']);
  print $q->hidden(-name=>'cat', -default=>$self->category);
  print "<tr><td colspan=2 bgcolor=#babadd><p><p><b>Or display </b>";
  print $q->submit(-name=>"major", -label=>"Major faults");
  print $q->submit(-name=>"recent", -label=>"Recent faults (2 days)");
  print $q->submit(-name=>"current", -label=>"Current faults (14 days)");
  print $q->endform;
  print "</td></table>";
}

=item B<query_faults>

Do a fault query and return a reference to an array of fault objects

  $fcgi->query_faults([$days]);

Optional argument is the number of days delta to return faults for.

=cut

sub query_faults {
  my $self = shift;
  my $days = shift;
  my $xml;

  if ($days) {
    my $t = gmtime;
    $xml = "<FaultQuery><date delta='$days'>" . $t->ymd . "</date></FaultQuery>";
  } else {
    $xml = "<FaultQuery></FaultQuery>";
  }

  my $faults;
  try {
    $faults = OMP::FaultServer->queryFaults($xml, "object");
    return $faults;
  } otherwise {
    my $E = shift;
    throw OMP::Error "$E";
  };
}

=item B<view_fault_form>

Create a form for submitting a fault ID for a fault to be viewed.

  $fcgi->view_fault_form();

=cut

sub view_fault_form {
  my $self = shift;
  my $q = $self->cgi;

  print $q->h2("View a fault");
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
}

=item B<close_fault_form>

Create a form with a button for closing a fault

  $fcgi->close_fault_form($faultid);

Takes a fault ID as the only argument.

=cut

sub close_fault_form {
  my $self = shift;
  my $faultid = shift;
  my $q = $self->cgi;

  my $width = $self->_get_table_width;
  print "<table border=0 width=$width bgcolor=#6161aa>";
  print "<tr><td align=right>";
  print $q->startform;
  print $q->hidden(-name=>'show_output', -default=>'true');
  print $q->hidden(-name=>'faultid', -default=>$faultid);
  print $q->submit(-name=>'close',
                   -label=>'Close Fault',);
  print $q->endform;
  print "</td></table>";
}

=item B<change_status_form>

Provide a form for changing the status of a fault.

  $fcgi->change_status_form($fault);

Only argument is an C<OMP::Fault> object.

=cut

sub change_status_form {
  my $self = shift;
  my $fault= shift;
  my $q = $self->cgi;

  my ( $labels, $values ) = $self->get_status_labels( $fault );

  my $faultid = $fault->id;

  print $q->startform;
  print $q->hidden(-name=>'show_output', -default=>'true');
  print $q->hidden(-name=>'faultid', -default=>$faultid);
  print $q->popup_menu(-name=>'status',
                       -default=>$fault->status,
                       -values=> $values,
                       -labels=> $labels,);
  print " ";
  print $q->submit(-name=>'change_status',
                   -label=>'Change',);
  print $q->endform;

}

=item B<file_fault_form>

Create a form for submitting fault details.  This subroutine takes its arguments in
the form of a hash containing the following keys:

  fault  - an C<OMP::Fault> object

The fault key is optional.  If present, the details of the fault object will
be used to provide defaults for all of the fields This allows this form to be
used for editing the details of an existing fault.

  $fcgi->file_fault_form(fault => $fault_object);

=cut

sub file_fault_form {
  my $self = shift;
  my %args = @_;
  my $fault = $args{fault};
  my $q = $self->cgi;

  # Get a new key for this form
  my $formkey = OMP::KeyServer->genKey;

  my $category = $self->category;
  my $is_safety = _is_safety( $category );

  # Create values and labels for the popup_menus
  my $systems = OMP::Fault->faultSystems( $category );
  my @sys_key = keys %$systems;
  my @system_values = _sort_values( \@sys_key, $systems, $category );

  my %system_labels = map {$systems->{$_}, $_} @sys_key;

  my $types = OMP::Fault->faultTypes($category);
  my @type_values = map {$types->{$_}} sort keys %$types;
  my %type_labels = map {$types->{$_}, $_} keys %$types;

  my ( %status, %status_labels );
  {
    my ( $labels, $status ) = _get_status_labels_by_name( $category );
    %status = %{ $status };
    %status_labels = %{ $labels };
  }

  my @status_values = map {$status{$_}} sort keys %status;

  # Location (for "Safety" category).
  my ( @place_values, %place_labels );
  if ( $is_safety ) {

    my %places = OMP::Fault->faultLocation_Safety;

    for ( sort keys %places ) {

      push @place_values, $places{ $_ };
      $place_labels{ $places{ $_ } } = $_ ;
    }
  }

  # Add some empty values to our menus (this is part of making sure that a
  # meaningful value is selected by the user) if a new fault is being filed
  unless ($fault) {
    push @system_values, undef;
    push @type_values, undef;
    $type_labels{''} = "Select a type";

    my $text =
      _is_vehicle_incident( $category )
      ? 'vehicle'
      : $is_safety
        ? 'severity level'
          : 'system'
          ;

    $system_labels{''} = qq[Select a $text];

    if ( $is_safety ) {

      push @place_values, undef;
      $place_labels{''} = 'Select a location';
    }
  }

  # Set defaults.  There's probably a better way of doing what I'm about
  # to do...
  my %defaults;
  my $submittext;

  if (!$fault) {
    %defaults = (user => $self->user,
                 system => '',
                 type => '',
                 location => '',
                 status => ! $is_safety ? $status{Open} : $status{'Follow up required'},
                 loss => undef,
                 time => undef,
                 tz => 'HST',
                 subject => undef,
                 message => undef,
                 assoc => undef,
                 assoc2 => undef,
                 urgency => undef,
                 condition => undef,);

    # Set the text for our submit button
    $submittext = "Submit fault";
  } else {
    # We have a fault object so use it's details as our defaults

    # Get the fault date (if any)
    my $faultdate = $fault->faultdate;

    # Convert faultdate to local time
    if ($faultdate) {
      my $epoch = $faultdate->epoch;
      $faultdate = localtime($epoch);
      $faultdate = $faultdate->strftime("%Y-%m-%dT%T")
    }

    # Is this fault marked urgent?
    my $urgent = ($fault->urgencyText =~ /urgent/i ? "urgent" : undef);

    # Is this fault marked chronic?
    my $chronic = ($fault->conditionText =~ /chronic/i ? "chronic" : undef);

    # Projects associated with this fault
    my @assoc = $fault->projects;

    # The fault text.  Strip out <PRE> tags.  If there aren't any <PRE> tags
    # we'll assume this fault used explicit HTML formatting so we'll add in
    # an opening <html> tag.
    my $message = $fault->responses->[0]->text;
    if ($message =~ m!^<pre>(.*?)</pre>$!is) {
      $message = OMP::Display->replace_entity($1);
    } else {
      $message = "<html>" . $message;
    }

    %defaults = (user=> $fault->responses->[0]->author->userid,
                 system => $fault->system,
                 status => $fault->status,
                 location => $fault->location,
                 type => $fault->type,
                 loss => $fault->timelost,
                 time => $faultdate,
                 tz => 'HST',
                 subject => $fault->subject,
                 message => $message,
                 assoc2 => join(',',@assoc),
                 urgency => $urgent,
                 condition => $chronic,
                );

    # Set the text for our submit button
    $submittext = "Submit changes";
  }

  # Fields in the query param stack will override normal defaults
  for (keys %defaults) {
    if ($q->param($_)) {
      $defaults{$_} = $q->param($_);
    }
  }

  print "<table border=0 cellspacing=4><tr>";
  print $q->startform;

  # Embed the key
  print $q->hidden(-name=>'formkey',
                   -default=>$formkey);

  # Embed fault category in case the user's cookie changes to
  # another category while fault is being filed
  print $q->hidden(-name=>'category',
                   -default=>$category,);

  # Need the show_output param in order for the output code ref to be called next
  print $q->hidden(-name=>'show_output',
                   -default=>'true');

  # Embed the fault ID and status if we are editing a fault
  if ($fault) {
    print $q->hidden(-name=>'faultid', -default=>$fault->id);
    print $q->hidden(-name=>'status', -default=>$defaults{status});
  }

  print "<td align=right><b>User:</b></td><td>";

  # DISABLE USER FIELD IF FORM IS FOR EDITING
  if (! $fault) {
    print $q->textfield(-name=>'user',
                        -size=>'16',
                        -maxlength=>'90',
                        -default=>$defaults{user},);
  } else {
    print " <strong>$defaults{user}</strong>";
    print $q->hidden(-name=>'user_hidden', -default=>$defaults{user});
  }

  my $sys_label = _get_system_label( $category );

  print '</td><tr><td align=right><b>', $sys_label, '</b></td><td>';

  print $q->popup_menu(-name=> lc $sys_label,
                       -values=>\@system_values,
                       -default=>$defaults{system},
                       -labels=>\%system_labels,);
  print "</td><tr><td align=right><b>Type:</b></td><td>";
  print $q->popup_menu(-name=>'type',
                       -values=>\@type_values,
                       -default=>$defaults{type},
                       -labels=>\%type_labels,);

  unless ($fault) {

    if ( $is_safety ) {

        print '</td><tr><td align="right"><b>Location:</b></td><td>',
          $q->popup_menu( '-name'    => 'location',
                          '-values'  => \@place_values,
                          '-default' => $defaults{'location'},
                          '-labels'  => \%place_labels,
                        );
    }

    print "</td><tr><td align=right><b>Status:</b></td><td>";
    print $q->popup_menu(-name=>'status',
                         -values=>\@status_values,
                         -default=>$defaults{status},
                         -labels=>\%status_labels,);
  }

  # Only provide fields for taking "time lost" and "time of fault"
  # if the category allows it
  if (OMP::Fault->faultCanLoseTime($category)) {
    print "</td><tr><td align=right><b>Time lost <small>(hours)</small>:</b></td><td>";
    print $q->textfield(-name=>'loss',
                        -default=>$defaults{loss},
                        -size=>'4',
                        -maxlength=>'10',);
  }

  if ( OMP::Fault->faultCanLoseTime($category)
      || $category =~ /events\b/i
      ) {

    print q[</td><tr valign="top"><td align="right">]
      . q[<b>Time of fault:</b>]
      . q[</td><td>]
      . $q->textfield(-name=>'time',
                      -default=>$defaults{time},
                      -size=>20,
                      -maxlength=>128,)
      . q[&nbsp;]
      . $q->popup_menu(-name=>'tz',
                        -values=>['UT','HST'],
                        -default=>$defaults{tz},)
      . q[<br /><small>(YYYY-MM-DDTHH:MM or HH:MM)</small>] ;
  }

  print "</td><tr><td align=right><b>Subject:</b></td><td>";
  print $q->textfield(-name=>'subject',
                      -size=>'60',
                      -maxlength=>'128',
                      -default=>$defaults{subject},);

  # Put up this reminder for telescope related filings
  if (OMP::Fault->faultIsTelescope($category)) {
    print "</td><tr><td colspan=2>";
    print "<small>Please remember to identify the instrument being used and "
      ."the data frame number if either are relevant</small>";
  }

  print "</td><tr><td colspan=2 align=right>";

  print $q->textarea(-name=>'message',
                     -rows=>20,
                     -columns=>78,
                     -default=>$defaults{message},);

  # If were in a category that allows project association create a
  # checkbox group for specifying an association with projects.

  if (OMP::Fault->faultCanAssocProjects($category)) {
    # Values for checkbox group will be tonights projects
    my $aref = OMP::MSBServer->observedMSBs({usenow => 1,
                                             format => 'data',
                                             returnall => 0,});

    if (@$aref[0] and ! $fault) {
      # We don't want this checkbox group if this form is being used for editing a fault
      my %projects;
      my %badproj; # used to limit error message noise
      for (@$aref) {
        # Make sure to only include projects associated with the current
        # telescope category
        my @instruments = split(/\W/, $_->instrument);
        # this may fail if an unexpected instrument turns up
        my $tel;
        try {
          $tel = OMP::Config->inferTelescope('instruments', @instruments);
        } catch OMP::Error::BadCfgKey with {
          my $key = $_->{projectid} . join("",@instruments);
          if (!exists $badproj{$key}) {
            print "<BR>Warning: Project $_->{projectid} used an instrument ".
              join(",",@instruments) .
                " that has no associated telescope. Please file an OMP fault<br>\n";
            $badproj{$key}++;
          }
        };
        next unless defined $tel;

        $projects{$_->projectid} = $_->projectid
          unless ($tel !~ /$category/i);

      }
      if (%projects) {
        print "</td><tr><td colspan=2><b>Fault is associated with the projects: </b>";
        print $q->checkbox_group(-name=>'assoc',
                                 -values=>[keys %projects],
                                 -default=>$defaults{assoc},
                                 -linebreak=>'true',);
        print "</td><tr><td colspan=2><b>Associated projects may also be specified here if not listed above </b>";
      } else {
        print "</td><tr><td colspan=2><b>Projects associated with this fault may be specified here </b>";
      }
    } else {
      print "</td><tr><td colspan=2><b>Projects associated with this fault may be specified here </b>";
    }
    print "<font size=-1>(separated by spaces)</font><b>:</b>";
    print "</td><tr><td colspan=2>";
    print $q->textfield(-name=>'assoc2',
                        -size=>50,
                        -maxlength=>300,
                        -default=>$defaults{assoc2},);
  }

  print "</td><tr><td colspan='2'><b>";

  # Setup condition checkbox group.  If the fault already exists,
  # allow user to indicate whether or not the fault is chronic
  my @convalues = ('urgent');
  my %conlabels = (urgent => "Urgent");
  my @condefaults = ($defaults{urgency});
  if ($fault) {
    if ($fault->id) {
      push @convalues, "chronic";
      $conlabels{chronic} = "Chronic";
      push @condefaults, $defaults{condition};
    }
  }

  # Even though there is only a single option for urgency I'm using a checkbox group
  # since it's easier to set a default this way
  print "This fault is ";
  print $q->checkbox_group(-name=>'condition',
                           -values=>\@convalues,
                           -labels=>\%conlabels,
                           -defaults=>\@condefaults,);

  print "</b></td><tr><td colspan='2' align=right>";
  print $q->submit(-name=>'submit',
                   -label=>$submittext,);
  print $q->endform;
  print "</td></table>";

}

=item B<response_form>

Create and display a form for submitting or editing a response.

  $fcgi->response_form(respid => $respid,
                       fault => $fault_obj);

Accepts arguments in hash format.  The following keys will be used:

  fault  - An C<OMP::Fault> object.  This key is always required.
  respid - The ID of a response to edit.  This key is optional.

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

  # Get a new key for this form
  my $formkey = OMP::KeyServer->genKey;

  my ( $labels, $values ) = $self->get_status_labels( $fault );

  # Set defaults.  Use cookie values if param values aren't available.
  my %defaults;
  if ($respid) {
    # Setup defaults for response editing
    my $resp = OMP::FaultUtil->getResponse($respid, $fault);

    my $text = $resp->text;

    # Prepare text for editing
    if ($text =~ m!^<pre>(.*?)</pre>$!is) {
      $text = OMP::Display->replace_entity($1);
    } else {
      $text = "<html>" . $text;
    }

    %defaults = (user => $resp->author->userid,
                 text => $text,
                 submitlabel => "Submit changes",);
  } else {

    %defaults = (user => $self->user,
                 text => undef,
                 status => $fault->status,
                 submitlabel => "Submit response",);
  }

  # Param list values take precedence
  for (keys %defaults) {
    if ($q->param($_)) {
      $defaults{$_} = $q->param($_);
    }
  }

  print "<table border=0><tr><td align=right><b>User: </b></td><td>";
  print $q->startform;

  # Embed the key
  print $q->hidden(-name=>'formkey',
                   -default=>$formkey);
  print $q->hidden(-name=>'show_output', -default=>['true']);
  print $q->hidden(-name=>'faultid', -default=>$fault->id);

  # Embed the response ID if we are editing a response
  print $q->hidden(-name=>'respid', -default=>$respid)
    if ($respid);

  # DISABLE USER FIELD IF FORM IS FOR EDITING
  if (! $respid) {
    print $q->textfield(-name=>'user',
                        -size=>'25',
                        -maxlength=>'75',
                        -default=>$defaults{user},);
  } else {
    print " <strong>$defaults{user}</strong>";
    print $q->hidden(-name=>'user_hidden', -default=>$defaults{user});
  }

  # Only show the status if we are filing a new response
  if (! $respid) {
    print "</td><tr><td><b>Status: </b></td><td>";
    print $q->popup_menu(-name=>'status',
                         -default=>$defaults{status},
                         -values=> $values,
                         -labels=> $labels,);
  }

  print "</td><tr><td></td><td>";
  print $q->textarea(-name=>'text',
                     -rows=>20,
                     -columns=>72,
                     -default=>$defaults{text},);
  print "</td></tr><td colspan=2 align=right>";
  print $q->submit(-name=>'respond',
                   -label=>$defaults{submitlabel});
  print $q->endform;
  print "</td></table>";
}

=item B<show_faults>

Show a list of faults.

  $fcgi->show_faults(faults => \@faults,
                     orderby => 'response',
                     descending => 1,
                     url => "fbfault.pl"
                     showcat => 1,);

Takes the following key/value pairs as arguments:

  CGI        - A C<CGI> query object
  faults     - A reference to an array of C<OMP::Fault> objects
  descending - If true faults are listed in descending order
  url        - The absolute or relative path to the script to be
               used for the view/respond link
  orderby    - Should be either 'response' (to sort by date of
               latest response) 'filedate', or 'timelost' (by amount
               of time lost).
  showcat    - true if a category column should be displayed

Only the B<faults> key is required.

=cut

sub show_faults {
  my $self = shift;
  my %args = @_;

  my @faults = @{ $args{faults} };
  my $descending = $args{descending};
  my $url = $args{url} || 'viewfault.pl';
  my $showcat = $args{showcat};

  my $q = $self->cgi;

  # Generate stats so we can decide to show fields like "time lost"
  # only if any faults have lost time
  my $stats = OMP::FaultGroup->new( faults => \@faults );

  my $width = $self->_get_table_width;
  print "<table width=$width cellspacing=0>";
  print "<tr>";

  # Show category column?
  print "<td><b>Category</b></td>"
    unless (! $showcat);

  print "<td><b>ID</b></td><td><b>Subject</b></td><td><b>Filed by</b></td><td><b>System</b></td><td><b>Type</b></td><td><b>Status</b></td>";

  # Show time lost field?
  if ($stats->timelost > 0) {
    print "<td align=center><b>Loss</b></td>";
  }

  print "<td><b>Replies</b></td><td> </td>";

  my $order = $args{'orderby'};

  if ( $order && lc $order eq 'faulttime' ) {

    @faults = @{ _sort_by_fault_time( \@faults, $descending ) };
  }
  else {

    my %sort =
      ( 'response' =>
          sub {
            $a->responses->[-1]->date->epoch
              <=>
            $b->responses->[-1]->date->epoch
          },

        'timelost' =>
          sub { $a->timelost <=> $b->timelost },
      );

    my $sort;
    $sort = $sort{ $order }
      if exists $sort{ $order };

    @faults = sort $sort @faults if $sort;

    @faults = reverse @faults
      if $descending;
  }

  my $alt_class;               # Keep track of alternating class style
  for my $fault (@faults) {
    my $classid;

    # Alternate row class style
    $alt_class++;
    if ($alt_class == 1) {
      $classid = 'row_shaded';
    } else {
      $classid = 'row_clear';
      $alt_class = 0;
    }

    my $faultid = $fault->id;
    my $user = $fault->author;
    my $system = $fault->systemText;
    my $type = $fault->typeText;

    my $subject = $fault->subject;
    (!$subject) and $subject = "[no subject]";

    my $status = $fault->statusText;
    ($fault->isNew and $fault->isOpen) and $status = "New";

    my $replies = $#{$fault->responses}; # The number of actual replies

    print "<tr class=\"${classid}\">";

    # Show category column?
    print "<td>". $fault->category ."</td>"
      unless (! $showcat);

    # Make the fault ID cell stand out if the fault is urgent
    print ($fault->isUrgent ? "<td class=\"cell_standout\">" : "<td>");
    print "$faultid</td>";
    print qq[<td><b><a href="$url?id=$faultid">$subject</a></b> &nbsp;];

    # Show affected projects?
    if ($q->param('show_affected') and $fault->projects) {
      print "<br>";
      my @projlinks = map {"<a href='projecthome.pl?urlprojid=$_'>$_</a>"} $fault->projects;
      print join (" | ", @projlinks);
    }

    print "</td>";
    print "<td>" . OMP::Display->userhtml($user, $q) . "</td>";
    print "<td>$system</td>";
    print "<td>$type</td>";
    print "<td>$status</td>";

    # Show time lost field?
    if ($stats->timelost > 0) {
      my $timelost = $fault->timelost;
      ($timelost == 0) and $timelost = "--" or $timelost = $timelost . " hrs";
      print "<td align=center>$timelost</td>";
    }


    print "<td align='center'>$replies</td>";
    print "<td><b><a href='$url?id=$faultid'>[View/Respond]</a></b></td>";
  }

  print "</table>";
}

=item B<print_form>

Create a simple form for sending faults to a printer.

  $fcgi->print_form($advanced, @faultids);

If the first argument is true then advanced options will be displayed.
Last argument is an array containing the fault IDs of the faults to be
printed.

=cut

sub print_form {
  my $self = shift;
  my $advanced = shift;
  my @faultids = @_;
  my $q = $self->cgi;

  # Get printers
  my @printers = OMP::Config->getData('printers');

  print $q->startform;

  # ($showoutput) and print $q->hidden(-name=>'show_output', -default=>'true');

  print $q->hidden(-name=>'faults',
                   -default=>join(',',@faultids));
  print $q->submit(-name=>'print',
                   -label=>'Send to printer');
  print "&nbsp;";
  print $q->popup_menu(-name=>'printer',
                       -values=>\@printers,);
  if ($advanced) {
    print "<br>Using method ";
    print $q->popup_menu(-name=>'print_method',
                         -values=>["separate","combined"],
                         -labels=>{separate => "One fault per page",
                                   combined => "Combined",},);
  }

  print $q->endform;
}

=item B<titlebar>

Create a title heading that identifies the current page

  $fcgi->titlebar(\@title);

Only argument should be an array reference containing the titlebar elements.
First element in the array will be placed in a shaded top-bar.  Second
element will appear in a smaller font below the top-bar.

=cut

  sub titlebar {
    my $self = shift;
    my $title = shift;
    my $q = $self->cgi;

    # We'll check the URL to determine if we're in the report problem or the
    # fault system and set the titlebar accordingly
    my $script = $q->url(-relative=>1);

    my $cat = $self->category;

    my $toptitle =
      _is_safety( $cat )
      ? "$cat Reporting"
      : _is_jcmt_events( $cat )
        ? 'JCMT Events'
        : _is_vehicle_incident( $cat )
          ? 'Vehicle Incident Reporting'
          : lc $cat ne 'anycat'
            ? "$cat Faults"
            : 'All Faults'
            ;

    my $width = $self->_get_table_width;
    print "<table width=$width><tr bgcolor=#babadd><td><font size=+1><b>$toptitle:&nbsp;&nbsp;".$title->[0]."</font></td>";
    print "<tr><td><font size=+2><b>$title->[1]</b></font></td>"
      if ($title->[1]);
    print "</table><br>";
  }

=item B<parse_file_fault_form>

Take the arguments from the fault filing form and parse them so they
can be used to create the fault and fault response objects.

  $fcgi->parse_file_fault_form();

Returns the following keys:

  subject, faultdate, timelost, system, type, status, urgency,
  projects, author, text

=cut

sub parse_file_fault_form {
  my $self = shift;
  my $q = $self->cgi;

  my $category = $q->param( 'category' );

  my %parsed = (subject => $q->param('subject'),
                type => $q->param('type'),
                status => $q->param('status'));

  if ( _is_safety( $category ) ) {

    $parsed{'system'} = $parsed{'severity'} =  $q->param('severity');
    $parsed{'location'} =  $q->param('location');
  }
  elsif ( _is_vehicle_incident( $category ) ) {

    $parsed{'system'} = $parsed{'vehicle'} =  $q->param('vehicle');
  }
  else {

    $parsed{'system'} =  $q->param('system');
  }

  # Determine urgency and condition
  my @checked = $q->param('condition');
  my %urgency = OMP::Fault->faultUrgency;
  my %condition = OMP::Fault->faultCondition;
  $parsed{urgency} = $urgency{Normal};
  $parsed{condition} = $condition{Normal};

  for (@checked) {
    ($_ =~ /urgent/i) and $parsed{urgency} = $urgency{Urgent};
    ($_ =~ /chronic/i) and $parsed{condition} = $condition{Chronic};
  }

  # Store time lost if defined.
  (length($q->param('loss')) >= 0) and $parsed{timelost} = $q->param('loss');

  # Get the associated projects
  if ($q->param('assoc') or $q->param('assoc2')) {
    my @assoc = $q->param('assoc');

    # Strip out commas and seperate on spaces
    my $assoc2 = $q->param('assoc2');
    $assoc2 =~ s/,/ /g;
    my @assoc2 = split(/\s+/,$assoc2);

    # Use a hash to eliminate duplicates
    my %projects = map {lc($_), undef} @assoc, @assoc2;
    $parsed{projects} = [keys %projects];
  }

  # If the time of fault was provided use it otherwise
  # do nothing
  if ($q->param('time')) {
    my $t;
    my $time = $q->param('time');

    # Define whether or not we have a local time
    my $islocal = ($q->param('tz') =~ /HST/ ? 1 : 0);
    my $utdate;

    if ($time =~ /^(\d\d*?)\W*(\d{2})$/) {
      # Just the time (something like HH:MM)
      my $hh = $1;
      my $mm = $2;
      if ($islocal) {
        # Time is local
        # Using Time::Piece localtime() method until OMP::DateTools::today()
        # method supports local time
        my $today = localtime;
        $utdate = OMP::DateTools->parse_date($today->ymd . "T$hh:$mm", 1);
      } else {
        my $today = OMP::DateTools->today;
        $utdate = OMP::DateTools->parse_date("$today" . "T$hh:$mm");
      }
    } else {
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

  my $author = $q->param('user');

  # User may be a hidden param
  (! $author) and $author = $q->param('user_hidden');

  $parsed{author} = OMP::UserServer->getUser($author);

  # The text.  Put it in <pre> tags if there isn't an <html>
  # tag present
  my $text = $q->param('message');

  $parsed{text} = OMP::Display->preify_text($text);

  return %parsed;
}

=item B<fault_summary_form>

Create a form for taking parameters for a fault summary.

  $fcgi->fault_summary_form();

=cut

sub fault_summary_form {
  my $self = shift;
  my $q = $self->cgi;

  # Get available fault categories
  my @categories = sort OMP::Fault->faultCategories;

  print "<h2>Summarize faults</h2>";
  print $q->start_form;
  print "Category";
  print $q->popup_menu(-name=>"category",
                       -values=>\@categories,);
  print "<table><td>";
  print $q->radio_group(-name=>"period",
                        -values=>["last_month","arbitrary"],
                        -labels=>{last_month=>"Last calendar month",arbitrary=>"For the past"},
                        -default=>"last_month",
                        -linebreak=>"true",);
  print "</td><td valign=bottom>";
  print $q->textfield(-name=>"days",
                      -default=>7,
                      -size=>3,
                      -maxlength=>4,);
  print " days";
  print "</td><tr><td>";
  print $q->submit(-name=>'submit',);
  print "</td></table>";
  print $q->end_form;
}

=item B<category_xml>

Return a snippet of xml containing the name of the current category
surrounded by an opening and closing category tag.

  $xmlpart = $fcgi->category_xml();

Returns an empty string if the given category is 'ANYCAT' or if the only
argument is undef.

=cut

sub category_xml {
  my $self = shift;
  my $cat = $self->category;

  if (defined $cat and $cat ne "ANYCAT") {
    return "<category>$cat</category>";
  } else {
    return "";
  }
}

=item B<get_status_labels>

Given a L<OMP::Fault> object, returns a a hash reference of labels for HTML
selection menu, and list of an array reference value

 ( $labels, $status ) = $comp->get_status_labels( $fault );

=cut

sub get_status_labels {

  my ( $self, $fault ) = @_;

  my %status =
    $fault->isJCMTEvents
    ? OMP::Fault->faultStatus_JCMTEvents
    : $fault->isSafety
      ? OMP::Fault->faultStatus_Safety
      : $fault->isVehicleIncident
        ? OMP::Fault->faultStatus_VehicleIncident
        : OMP::Fault->faultStatus
        ;

  # Pop-up menu labels.
  my %label = map { $status{$_}, $_ } %status;

  return (  \%label, [ values %status ] );
}

=back

=head2 Internal Methods

=over 4

=item B<_get_table_width>

Return the table width parameter value

=item B<_set_table_width>

Set the table width parameter value

=cut

{
  my $TABLEWIDTH = '100%';

  sub _get_table_width {
    return $TABLEWIDTH;
  }

  sub _set_table_width {
    my $self = shift;
    $TABLEWIDTH = shift;
  }
}

=item B<_get_status_labels_by_name>

Given a fault category name, returns a hash reference (status values as keys,
names as values for HTML selection list) and a hash reference of status (reverse
of first argument).  All of the status types are returned for category of
C<ANYCAT>.  (It is somehwhat similar to I<get_status_labels>.)

  ( $labels, $status_values ) = _get_status_labels_by_name( 'OMP' );

=cut

sub _get_status_labels_by_name {

  my ( $cat ) = @_;

  $cat = lc $cat;

  my $default = '_default_';
  my %method =
    ( $default => 'faultStatus',
      'safety' => 'faultStatus_Safety',
      'jcmt_events' => 'faultStatus_JCMTEvents',
      'vehicle_incident' => 'faultStatus_VehicleIncident',
    );

  my %status;
  if ( $cat =~ m/^any/i  ) {

    %status = map { OMP::Fault->$_() } values %method;
  }
  else {

    my $method = $method{ exists $method{ $cat } ? $cat : $default };
    %status = OMP::Fault->$method();
  }

  my $labels = { map {$status{$_}, $_} %status };

  return ( $labels, \%status );
}

=item B<_sort_by_fault_time>

Returns an array reference of faults sorted by fault times & file
dates, given an array reference of faults & optional truth value if to
sort in descending order.

  $faults = _sort_by_fault_time( \@fault, my $descending = 1 );

Faults are first sorted by fault time, when available.  All the
remaining faults (without a fault date) are then sorted by the filing
date.

=cut

sub _sort_by_fault_time {

  my ( $faults, $descend ) = @_;

  my ( @fault, @file );
  for my $f ( @{ $faults } ) {

    if ( $f->faultdate ) {

      push @fault, $f;
    }
    else {

      push @file, $f;
    }
  }

  return
    [ ( sort
        { $b->faultdate <=> $a->faultdate
          ||
          $b->filedate  <=> $a->filedate
        }
        @fault
      ),
      ( sort { $b->filedate  <=> $a->filedate  } @file )
    ]
    if $descend;

  return
    [ ( sort
        { $a->faultdate <=> $b->faultdate
          ||
          $a->filedate  <=> $b->filedate
        }
        @fault
      ),
      ( sort { $a->filedate  <=> $b->filedate  } @file )
    ];
}


sub _get_system_label {

  my ( $cat ) = @_;

  return
    _is_safety( $cat )
    ? 'Severity'
    : _is_vehicle_incident( $cat )
      ? 'Vehicle'
      : 'System'
      ;
}

sub _sort_values {

  my ( $keys, $sys, $cat, $mode ) = @_;

  unless ( $cat ) {

    $mode = 'alpha'
      unless scalar grep( $mode eq $_, qw[ num alphanum ] );
  }
  elsif ( _is_vehicle_incident( $cat ) ) {

    $mode = 'num';
  }

  my $sort =
    $mode eq 'num'
    ? sub { $a <=> $b }
    : $mode eq 'alphanum'
      ? sub { $a <=> $b || $a cmp $b }
      : sub { $a cmp $b }
      ;

  return map { $sys->{ $_ } } sort $sort @{ $keys };
}

sub _is_safety {

  my ( $cat ) = @_;
  return 'safety' eq lc $cat
}

sub _is_jcmt_events {

  my ( $cat ) = @_;
  return 'jcmt_events' eq lc $cat
}

sub _is_vehicle_incident {

  my ( $cat ) = @_;
  return 'vehicle_incident' eq lc $cat
}

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

1;
