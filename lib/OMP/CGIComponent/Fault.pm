package OMP::CGIComponent::Fault;

=head1 NAME

OMP::CGIComponent::Fault - Components for fault system web pages

=head1 SYNOPSIS

  use OMP::CGIComponent::Fault;

  $comp = new OMP::CGIComponent::Fault(page => $fault_page);

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
use OMP::Display;
use OMP::DateTools;
use OMP::General;
use OMP::Error qw(:try);
use OMP::Fault;
use OMP::FaultDB;
use OMP::FaultServer;
use OMP::FaultGroup;
use OMP::FaultUtil;
use OMP::MSBServer;
use OMP::UserServer;

use base qw(OMP::CGIComponent);

our $VERSION = (qw$ Revision: 1.2 $ )[1];

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
      my ($labels, $values) = $self->get_status_labels($fault);
      @statuses = map {[$_, $labels->{$_}]} @$values;
  }

  my %shifts = OMP::Fault->shiftTypes($fault->category);

  return {
      fault => $fault,
      display_date_local => sub {
          my $epoch = $_[0]->epoch;
          my $date = localtime($epoch);
          return OMP::DateTools->display_date($date);
      },
      system_label => _get_system_label($fault->category),
      allow_edit => ! $noedit,
      target => $self->page->url_absolute(),
      statuses => \@statuses,
      has_shift_type => !! %shifts,
  }
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

  my $sys_label = _get_system_label( $category );

  my @systems;
  my @types;

  if (! $hidefields) {
    my $systems = OMP::Fault->faultSystems($category);
    @systems = map {[$systems->{$_}, $_]} sort keys %$systems;

    my $types = OMP::Fault->faultTypes($category);
    @types = map {[$types->{$_}, $_]} sort keys %$types;
  }

  (undef, my $status) = _get_status_labels_by_name($category);

  my @status = (
      [all_open => 'All open'],
      [all_closed => 'All closed'],
      map {[$status->{$_}, $_]} sort keys %$status);

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
    ],
    periods => [
        [arbitrary => 'between dates'],
        [days => 'in the last'],
        [last_month => 'in the last calendar month'],
    ],
    text_searches => [
        'text',
        'subject',
        'both',
    ],
    system_label => $sys_label,
    systems => \@systems,
    types => \@types,
    statuses => \@status,
    values => {
        action => (scalar $q->param('action') // 'activity'),
        period => (scalar $q->param('period') // 'arbitrary'),
        timezone => (scalar $q->param('timezone') // 'HST'),
        text_search => (scalar $q->param('text_search') // 'both'),
        map {$_ => scalar $q->param($_)}
            qw/author mindate maxdate days system type status
            timelost show_affected chronic summary
            text text_boolean/,
    },
  };
}

=item B<file_fault_form>

Create a form for submitting fault details.  This subroutine takes its arguments in
the form of a hash containing the following keys:

  fault  - an C<OMP::Fault> object

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

  my $is_safety = _is_safety( $category );

  # Create values and labels for the popup_menus
  my @systems; {
    my $systems = OMP::Fault->faultSystems( $category );
    my @sys_key = keys %$systems;
    my @system_values = _sort_values( \@sys_key, $systems, $category );
    my %system_labels = map {$systems->{$_}, $_} @sys_key;
    @systems = map {[$_, $system_labels{$_}]}  _sort_values( \@sys_key, $systems, $category );
  }

  my $types = OMP::Fault->faultTypes($category);
  my @types = map {[$types->{$_}, $_]} sort keys %$types;

  my @statuses; {
    (undef, my $status) = _get_status_labels_by_name($category);
    @statuses = map {[$status->{$_}, $_]} sort keys %$status;
  }

  # Location (for "Safety" category).
  my @locations;
  if ($is_safety) {
    my %places = OMP::Fault->faultLocation_Safety;
    @locations = map {[$places{$_}, $_]} sort keys %places;
  }

  my $sys_text =
    _is_vehicle_incident( $category )
    ? 'vehicle'
    : $is_safety
      ? 'severity level'
        : 'system';

  # Set defaults.  There's probably a better way of doing what I'm about
  # to do...
  my %defaults;
  my @projects = ();
  my @warnings = ();

  if (!$fault) {
    %defaults = (system => undef,
                 type => undef,
                 location => undef,
                 status => ($is_safety ? OMP::Fault::FOLLOW_UP : OMP::Fault::OPEN),
                 loss => undef,
                 time => undef,
                 tz => 'HST',
                 subject => undef,
                 message => undef,
                 assoc2 => undef,
                 urgency => undef,
                 condition => undef,
                 shifttype => undef,
                 remote => undef,);

    # If we're in a category that allows project association create a
    # checkbox group for specifying an association with projects.
    # We don't want this checkbox group if this form is being used for editing a fault.
    if (OMP::Fault->faultCanAssocProjects($category)) {
      # Values for checkbox group will be tonights projects
      my $aref = OMP::MSBServer->observedMSBs({usenow => 1,
                                               format => 'data',
                                               returnall => 0,});

      if (@$aref[0]) {
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
              push @warnings, "Project $_->{projectid} used an instrument "
                  . join(",",@instruments)
                  . " that has no associated telescope.";
              $badproj{$key}++;
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

    %defaults = (system => $fault->system,
                 status => $fault->status,
                 location => $fault->location,
                 type => $fault->type,
                 loss => $fault->timelost * 60.0,
                 time => $faultdate,
                 tz => 'HST',
                 subject => $fault->subject,
                 message => $message,
                 assoc2 => join(',',@assoc),
                 urgency => $urgent,
                 condition => $chronic,
                 shifttype => $fault->shifttype,
                 remote => $fault->remote,
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

  my $sys_label = _get_system_label( $category );

  my %shifts = OMP::Fault->shiftTypes($category);
  my @shifts = map {[$_ => $shifts{$_}]} sort keys %shifts;

  my %remotes = OMP::Fault->remoteTypes($category);
  my @remotes = map {[$_ => $remotes{$_}]} sort keys %remotes;

  my @conditions = (['urgent', 'Urgent', 'urgency']);
  push @conditions, (['chronic', 'Chronic', 'condition'])
      if defined $fault;

  return {
      target => $self->page->url_absolute(),
      fault => $fault,
      has_location => $is_safety,
      has_time_loss => OMP::Fault->faultCanLoseTime($category),
      has_time_occurred => !! (OMP::Fault->faultCanLoseTime($category) or $category =~ /events\b/i),
      has_project_assoc => OMP::Fault->faultCanAssocProjects($category),
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

  $comp->response_form(respid => $respid,
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

  my ( $labels, $values ) = $self->get_status_labels( $fault );
  my @statuses = map {[$_, $labels->{$_}]} @$values;

  # Set defaults.
  my %defaults;
  my $resp = undef;
  if ($respid) {
    # Setup defaults for response editing
    $resp = OMP::FaultUtil->getResponse($respid, $fault);

    my $text = $resp->text;

    # Prepare text for editing
    if ($text =~ m!^<pre>(.*?)</pre>$!is) {
      $text = OMP::Display->replace_entity($1);
    } else {
      $text = "<html>" . $text;
    }

    %defaults = (text => $text,
                 flag => $resp->flag,
                 submitlabel => "Submit changes",);
  } else {

    %defaults = (text => '',
                 status => $fault->status,
                 submitlabel => "Submit response",);
  }

  # Param list values take precedence
  for (qw/text status flag/) {
    if ($q->param($_)) {
      $defaults{$_} = $q->param($_);
    }
  }

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
  };
}

=item B<show_faults>

Show a list of faults.

  $comp->show_faults(faults => \@faults,
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
               latest response) 'filedate', 'timelost' (by amount
               of time lost) or 'relevance'.
  showcat    - true if a category column should be displayed

Only the B<faults> key is required.

=cut

sub show_faults {
  my $self = shift;
  my %args = @_;

  my @faults = @{ $args{faults} };
  my $descending = $args{descending};
  my $url = $args{url} || 'viewfault.pl';

  my $q = $self->cgi;

  # Generate stats so we can decide to show fields like "time lost"
  # only if any faults have lost time
  my $stats = OMP::FaultGroup->new( faults => \@faults );

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

        'relevance' =>
          sub {$a->relevance() <=> $b->relevance()},
      );

    my $sort;
    $sort = $sort{ $order }
      if exists $sort{ $order };

    @faults = sort $sort @faults if $sort;

    @faults = reverse @faults
      if $descending;
  }

  return {
      show_cat => $args{'showcat'},
      show_time_lost => ($stats->timelost > 0),
      show_projects => $args{'show_affected'},
      faults => \@faults,
      view_url => ($url . (($url =~ /\?/) ? '&' : '?') . 'fault='),
  };
}

=item B<category_title>

Return the name of a category, suitable for including in a page title.

=cut

sub category_title {
    my $self = shift;
    my $cat = shift;

    return _is_safety($cat)
        ? "$cat Reporting"
        : _is_jcmt_events($cat)
            ? 'JCMT Events'
            : _is_vehicle_incident($cat)
                ? 'Vehicle Incident Reporting'
                : lc $cat ne 'anycat'
                    ? "$cat Faults"
                    : 'All Faults';
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

  my %parsed = (subject => scalar $q->param('subject'),
                type => scalar $q->param('type'),
                status => scalar $q->param('status'),
      );

  my @params = $q->multi_param;
  my %paramhash = map { $_ => 1 } @params;
  if(exists($paramhash{remote})){
      $parsed{'remote'} = $q->param('remote');
  } else {
      $parsed{'remote'} = undef;
  }
  if(exists($paramhash{shifttype})){
      $parsed{'shifttype'} = $q->param('shifttype');
  } else {
      $parsed{'shifttype'} = undef;
  }



  if ( _is_safety( $category ) ) {

    $parsed{'system'} = $parsed{'severity'} =  $q->param('system');
    $parsed{'location'} =  $q->param('location');
  }
  elsif ( _is_vehicle_incident( $category ) ) {

    $parsed{'system'} = $parsed{'vehicle'} =  $q->param('system');
  }
  else {

    $parsed{'system'} =  $q->param('system');
  }

  # Determine urgency and condition
  my @checked = $q->multi_param('condition');
  my %urgency = OMP::Fault->faultUrgency;
  my %condition = OMP::Fault->faultCondition;
  $parsed{urgency} = $urgency{Normal};
  $parsed{condition} = $condition{Normal};

  for (@checked) {
    ($_ =~ /urgent/i) and $parsed{urgency} = $urgency{Urgent};
    ($_ =~ /chronic/i) and $parsed{condition} = $condition{Chronic};
  }

  # Store time lost if defined (convert to hours)
  (length($q->param('loss')) >= 0) and $parsed{timelost} = $q->param('loss')/60.0;

  # Get the associated projects
  if ($q->param('assoc') or $q->param('assoc2')) {
    my @assoc = $q->multi_param('assoc');

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

  # The text.  Put it in <pre> tags if there isn't an <html>
  # tag present
  my $text = $q->param('message');

  $parsed{text} = OMP::Display->preify_text($text);

  return %parsed;
}

=item B<category_xml>

Return a snippet of XML containing the name of the given category
surrounded by an opening and closing category tag.

  $xmlpart = $comp->category_xml($category);

Returns an empty string if the given category is 'ANYCAT' or if the only
argument is undef.

=cut

sub category_xml {
  my $self = shift;
  my $cat = shift;

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
