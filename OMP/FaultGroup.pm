package OMP::FaultGroup;

=head1 NAME

OMP::FaultGroup - Information on groups of OMP::Fault objects.

=head1 SYNOPSIS

  use OMP::FaultGroup;

  $f = new OMP::FaultGroup( faults => \@faults );

  $f->summary('html');

=head1 DESCRIPTION

This class can be used to determine statistics for a given
group of faults. A group can be specified by an array of faults.

=cut

use 5.006;
use strict;
use warnings;
use Carp;

our $VERSION = (qw$ Revision: $ )[1];

use OMP::Fault;
use OMP::FaultDB;
use OMP::General;
use OMP::PlotHelper;
use OMP::Project::TimeAcct;

use Time::Piece;
use Time::Seconds;

$| = 1;

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

Object constructor. Takes a hash as an argument, the keys of which can
be used to populate the object. The key names must match the names of
the accessor methods (ignoring case). If they do not match they are
ignored (for now).

  $f = new OMP::FaultGroup( %args );

Arguments are optional.

Additionally, a key named 'faults' pointing to an array reference
containing C<OMP::Fault> objects may be passed as an argument. If
this is the case, then the C<OMP::FaultGroup> object can provide
a summary of all of the faults passed.

=cut

sub new {
  my $proto = shift;
  my %args = @_;
  my $class = ref($proto) || $proto;

  my $f = bless {
		 FaultArray => [],
		 TimeLost => undef,
		 TimeLostNonTechnical => undef,
		 TimeLostTechnical => undef,
                 Categories => [],
                }, $class;

  if( @_ ) {
    $f->populate( %args );
  }

  return $f;
}

=back

=head1 Accessor Methods

=over 4

=item B<faults>

Retrieve (or set) the group of faults.

  @faults = $f->faults;
  $faultref = $f->faults;
  $f->faults(@faults);
  $f->faults(\@faults);

All previous faults are removed when new faults are stored.  Takes
either an array or array reference containing objects of class
C<OMP::Fault> as an argument.

=cut

sub faults {
  my $self = shift;

  if (@_) {
    my @faults;
    if (ref($_[0]) eq 'ARRAY') {

      # Argument is an array reference
      @faults = @{$_[0]};
    } else {
      @faults = @_;
    }

    # Make sure the faults are OMP::Fault objects
    for (@faults) {
      throw OMP::Error::BadArgs("Fault must be an object of class OMP::Fault")
	unless UNIVERSAL::isa($_, "OMP::Fault");
    }

    # Store the fault objects (sorted)
    @{$self->{FaultArray}} = sort {$a->faultid <=> $b->faultid} @faults;

    # Clear old time lost values
    $self->timelost(undef);
  }

  if (wantarray) {

    # Return an array
    return @{$self->{FaultArray}};
  } else {

    # Return an array reference
    return $self->{FaultArray};
  }
}

=item B<timelost>

Time lost to faults on the specified UT date. The time is
represented by a Time::Seconds object.

  $time = $f->timelost;
  $f->timelost( new Time::Seconds( 3600 ) );

If called with only an undef value, this method will clear
the value this method returns.  If undefined, a C<Time::Seconds>
object is returned with a value of 0 seconds.

=cut

sub timelost {
  my $self = shift;
  if(@_) {
    if (! defined $_[0]) {

      # Clear time lost value since the argument was undef
      $self->{TimeLost} = undef;
      $self->timelostNonTechnical( undef );
      $self->timelostTechnical( undef );
    } else {
      # Set the new time lost value
      my $time = shift;
      $time = new Time::Seconds( $time )
	unless UNIVERSAL::isa($time, "Time::Seconds");
      $self->{TimeLost} = $time;
    }
  } elsif (! defined $self->{TimeLost}) {

    # Calculate time lost since the value is not already cached
    my @faults = $self->faults;
    my $timelost = 0;
    my $timelost_nontech = 0;
    my $timelost_technical = 0;
    for my $fault ( @faults ) {
      my $loss = new Time::Seconds($fault->timelost * ONE_HOUR);
      if ($fault->typeText =~ /human/i or $fault->statusText =~ /not a fault/i) {
	
	# Fault is non-technical
	$timelost_nontech += $loss;
      } else {
	$timelost_technical += $loss;
      }
      $timelost += $loss;
    }

    # Store time lost values
    $self->{TimeLost} = $timelost;
    $self->timelostNonTechnical( $timelost_nontech );
    $self->timelostTechnical( $timelost_technical );
  }
  if (! defined $self->{TimeLost}) {
    return Time::Seconds->new(0);
  } else {
    return $self->{TimeLost};
  }
}

=item B<timelostTechnical>

Time lost to technical faults (those with type that is not "human" or status other than "Not a fault").
The time is represented by a Time::Seconds object.

  $time = $f->timelostTechnical;
  $f->timelostTechnical( new Time::Seconds( 3600 ) );

If called with only an undef value, this method will clear
the value this method returns. If undefined, a C<Time::Seconds>
object is returned with a value of 0 seconds.

=cut

sub timelostTechnical {
  my $self = shift;
  if(@_) {
    if (! defined $_[0]) {

      # Unset value since the argument was undef
      $self->{TimeLostTechnical} = undef;
    } else {
      my $time = shift;
      $time = new Time::Seconds( $time )
	unless UNIVERSAL::isa($time, "Time::Seconds");
      $self->{TimeLostTechnical} = $time;
    }
  }
  if (! defined $self->{TimeLostTechnical}) {
    return Time::Seconds->new(0);
  } else {
    return $self->{TimeLostTechnical};
  }
}

=item B<timelostNonTechnical>

Time lost to non-technical faults (those with type that is "human" or status of "Not a fault").  The time is represented by a Time::Seconds object.

  $time = $f->timelostNonTechnical;
  $f->timelostNonTechnical( new Time::Seconds( 3600 ) );

If called with only an undef value, this method will clear
the value this method returns. If undefined, a C<Time::Seconds>
object is returned with a value of 0 seconds.

=cut

sub timelostNonTechnical {
  my $self = shift;
  if(@_) {
    if (! defined $_[0]) {

      # Unset value since the argument was undef
      $self->{TimeLostNonTechnical} = undef;
    } else {
      my $time = shift;
      $time = new Time::Seconds( $time )
	unless UNIVERSAL::isa($time, "Time::Seconds");
      $self->{TimeLostNonTechnical} = $time;
    }
  }
  if (! defined $self->{TimeLostNonTechnical}) {
    return Time::Seconds->new(0);
  } else {
    return $self->{TimeLostNonTechnical};
  }
}

=item B<categories>

The fault categories spanned by the group of faults.  An array of
fault categories (case-sensitive, must be valid) can be provided as
an argument in order to set this value.

  @categories = $f->categories;
  $categories = $f->categories;
  $f->categories(@categories);

Depending on the calling context, returns either an array of category
names or a comma-separated list of category names.  If called with only
an undef value, this method will unset the value this method returns.

=cut

sub categories {
  my $self = shift;

  if(@_) {
    if (! defined $_[0]) {

      # Unset value since the argument was undef
      $self->{Categories} = undef;
    } else {
      my @categories = shift;

      # Make sure categories are valid
      my %validcats = map {$_, undef} OMP::Fault->categories;
      for (@categories) {
	throw OMP::Error::BadArgs("Category names must be valid.")
	  unless exists($validcats{$_});
      }
      @{$self->{Categories}} = @categories;
    }
  } elsif (! defined $self->{Categories}->[0]) {

    # Set the value since it doesn't exist yet
    my %categories = map {$_->category, undef} $self->faults;
    @{$self->{Categories}} = keys %categories;
  }
  if (wantarray) {
    return @{$self->{Categories}};
  } else {
    return join(",", @{$self->{Categories}});
  }
}

=back

=head2 General Methods

=over 4

=item B<populate>

Populate the object.

  $f->populate(
                timelost => $timelost,
              );

The timelost must be either a C<Time::Seconds> object or an
integer number of seconds.

=cut

sub populate {
  my $self = shift;
  my %args = @_;

  for my $key (keys %args) {
    my $method = lc($key);
    if ($self->can($method)) {
      $self->$method( $args{$key} );
    }
  }
};

=item B<summary>

Presents a summary of the information contained in the
C<OMP::FaultGroup> object.

  $summary = $f->summary('html');

Valid parameters are 'html' or 'text'. Default is 'text'.

=cut

sub summary {
  my $self = shift;
  my $type = shift || 'text';

  my $timelost = $self->timelost;

  return
    unless (defined $timelost);

  my $return;
  if($type =~ /^html$/i) {
    $return .= sprintf("(%s hours from fault system)<br>\n", $timelost->hours);
  } elsif( $type =~ /^text$/i) {
    $return = sprintf("Time lost to faults: %s hours\n", $timelost->hours);
  }

  return $return;
}

=item B<timeLostStats>

Generate values for total time lost (in hours) in each fault system.

  %stats = $f->timeLostStats;
  $hours_lost = $stats{$category}{$system};

A hash is returned containing keys for each category with the values
being a reference to a hash of values for total hours lost keyed by
system name.

=cut

sub timeLostStats {
  my $self = shift;

  my %faults = $self->_getSystems(0);

  # Calculate and store totals for each system
  map {$faults{$_->category}{$_->systemText} += $_->timelost} $self->faults;

  return %faults;
}

=item B<numFaultStats>

Number of faults in each system.

  %stats = $f->numFaultStats( $includeAll );
  $num_faults = $stats{$category}{$system};

A hash is returned containing keys for each category with the values
being a reference to a hash of values for total number of faults keyed by
system name.  If the optional argument is true, zero time loss faults are
included in the result.

=cut

sub numFaultStats {
  my $self = shift;
  my $includeAll = shift;

  # Get a hash of available fault systems with values
  # defaulting to zero
  my %faults = $self->_getSystems(0);

  # Only count faults that lost time unless the 'include all'
  # argument is true
  my @faults = ($includeAll ? $self->faults : grep {$_->timelost > 0} $self->faults);

  # Calculate and store totals for each system
  map {$faults{$_->category}{$_->systemText}++} @faults;

  return %faults;
}

=item B<faultRateStats>

Fault frequency as a function of time, or time loss rate as a
function of time.

  @stats = $f->faultRateStats([bin => 7,
                              startdate => $date,
                              filed => 1,
                              loss => 1,
                              average => 1,]);

Arguments should be given in hash form.  The arguments are:

  bin       - Number of days to bin-up the results by.  The number
              can be fractional.  Defaults to 1.
  startdate - A date, provided as a C<Time::Piece> object, that
              the statistics should start at.  Defaults to the
              date of the oldest fault.
  filed     - If true, the file date, rather than occurrence date
              of the fault, is used in determining what date range
              range the fault falls within.  Defaults to false.
  loss      - If true, stats are calculated for time loss rate,
              rather than fault occurrence rate.  Default is false.
  average   - If true, values are averaged after binning.  If fault
              occurrence rate is being calculated (if 'loss'
              parameter is false), this will be forced to have a
              false value.  Default is false.

All arguments are optional.  Returns an array.

=cut

sub faultRateStats {
  my $self = shift;
  my %args = @_;

  # Get the faults
  my @faults = $self->faults;

  # Default argument values
  my %defaults = (bin => 1,
                  filed => 0,
                  stardate => undef,
		  loss => 0,
                  average => 0,);

  %args = (%defaults, %args);

  # Force 'average' to be false if calculating fault occurrence rate
  if (! $args{loss}) {
    $args{average} = 0
  };

  # Populate coordinate array with Time::Piece objects as X
  # and the value 1 as Y
  my @coords;
  for my $fault (@faults) {
    my $date;
    if ($args{filed}) {
      $date = $fault->responses->[0]->date;
    } else {
      $date = $fault->date;
    }

    # Use time lost as Y value unless we are calculating for
    # occurrence rate
    push @coords, [$date, ($args{loss} ? $fault->timelost : 1)];
  }

  # Bin up
  my @stats = OMP::PlotHelper->bin_up_by_date(days => $args{bin},
					      method => ($args{average} ? 'average' : 'sum'),
					      values => \@coords,
					      startdate => $args{startdate},);

  return @stats;
}


=item B<timeacct>

Return an array of C<OMP::Project::TimeAcct> group objects.  One
C<OMP::Project::TimeAcct> object is created for each UT date where
time was lost.  The special project ID assigned to each object
is "__FAULT__".

  @acct = $f->timeacct();
  $acct = $f->timeacct();

Returns either an array or a reference to an array.

=cut

sub timeacct {
  my $self = shift;
  my @fault = $self->faults;
  my %faults_by_ut;

  for my $fault (@fault) {
    if ($fault->timelost) {
      push @{$faults_by_ut{$fault->date->strftime('%Y%m%d')}}, $fault;
    }
  }

  my @acct;
  for my $ut (sort keys %faults_by_ut) {
    my $fgroup = $self->new(faults=>$faults_by_ut{$ut});
    my $acct = new OMP::Project::TimeAcct(projectid => '__FAULT__',
					  date => OMP::General->parse_date($ut),
					  timespent => $fgroup->timelost,
					  confirmed => 1,);
    push @acct, $acct;
  }
  if (wantarray) {
    return @acct;
  } else {
    return \@acct;
  }
}

=back

=head2 Internal Methods

=over 4

=item B<_getSystems>

Return a hash of hashes keyed by category, then system name.  The default
value for all system keys can be set by passing it in as an argument,
otherwise the default value is undef.

=cut

sub _getSystems {
  my $self = shift;
  my $default = shift;

  # Get the fault categories we're dealing with
  my @categories = $self->categories;

  # Prepare the result so that all systems start with
  # a default value
  my %systems;
  for my $category (@categories) {
    my $sysref = OMP::Fault->faultSystems($category);
    map {$systems{$category}{$_} = $default} keys %$sysref;
  }

  return %systems;
}

=back

=head1 AUTHORS

Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>,
Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002 Particle Physics and Astronomy Research Council.
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
