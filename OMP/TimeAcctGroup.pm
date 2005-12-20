package OMP::TimeAcctGroup;

=head1 NAME

OMP::TimeAcctGroup - Information on a group of OMP::Project::TimeAcct objects

=head1 SYNOPSIS

  use OMP::TimeAcctGroup;
g
  $tg = new OMP::TimeAcctGroup( accounts => \@accounts );

  @stats = $tg->timeLostStats();

=head1 DESCRIPTION

This class can be used to generate time accounting statistics, based
on a group of C<OMP::Project::TimeAcct> objects.  A group is just an
array of C<OMP::Project::TimeAcct> objects.

=cut

use 5.006;
use strict;
use warnings;
use Carp;

our $VERSION = (qw$ Revision: $ )[1];

use OMP::Config;
use OMP::DBbackend;
use OMP::Error qw(:try);
use OMP::General;
use OMP::PlotHelper;
use OMP::ProjDB;
use OMP::ProjQuery;
use OMP::TimeAcctDB;
use OMP::TimeAcctQuery;

use Time::Seconds;

$| = 1;

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

Object constructor. Takes a hash as an argument, the keys of which can
be used to populate the object.  The keys must match the names of the
accessor methods (ignoring case).

  $tg = new OMP::TimeAcctGroup( accounts => \@accounts );

Arguments are optional.

=cut

sub new {
  my $proto = shift;
  my %args = @_;
  my $class = ref($proto) || $proto;

  my $tg = bless {
		  Accounts => [],
		  TotalTime => undef,
		  TotalTimeNonExt => undef,
		  CalTime => undef,
		  ClearTime => undef,
		  ConfirmedTime => undef,
		  ECTime => undef,
		  ExtTime => undef,
		  FaultLoss => undef,
		  ObservedTime => undef,
		  OtherTime => undef,
		  ScienceTime => undef,
		  ShutdownTime => undef,
		  Telescope => undef,
		  WeatherLoss => undef,
		 }, $class;

  if (@_) {
    $tg->populate( %args );
  }

  return $tg;
}

=back

=head2 Accessor Methods

=over 4

=item B<accounts>

Retrieve (or specify) the group of accounts.

  @accounts = $tg->accounts;
  $accountref = $tg->accounts;
  $tg->accounts(@accounts);
  $tg->accounts(\@accounts);

All previous accounts are removed when new accounts are stored.
Takes either an array, or reference to an array, of
C<OMP::Project::TimeAcct> objects.

=cut

sub accounts {
  my $self = shift;

  if (@_) {
    # Store new accounts
    my @accounts;
    if (ref($_[0]) eq 'ARRAY') {
      @accounts = @{$_[0]};
    } else {
      @accounts = @_;
    }

    # Make sure these are OMP::Project::TimeAcct objects
    # with a defined epoch
    for (@accounts) {
      throw OMP::Error::BadArgs("Account must be an object of class OMP::Project::TimeAcct")
	unless UNIVERSAL::isa($_, "OMP::Project::TimeAcct");
      throw OMP::Error::BadArgs("Account must have a valid date, not undef")
        unless defined $_->date;
    }

    # Store accounts, sorted
    @{$self->{Accounts}} = sort {$a->date->epoch <=> $b->date->epoch} @accounts;

    # Clear cached values
    $self->totaltime(undef);
    $self->totaltime_non_ext(undef);
    $self->cal_time(undef);
    $self->clear_time(undef);
    $self->ext_time(undef);
    $self->fault_loss(undef);
    $self->observed_time(undef);
    $self->other_time(undef);
    $self->weather_loss(undef);
    $self->science_time(undef);
    $self->ec_time(undef);
  }

  if (wantarray) {
    return @{$self->{Accounts}};
  } else {
    return $self->{Accounts};
  }
}

=item B<totaltime>

The total time spent according to all accounts (this includes
weather loss, other time, faults, and extended time).This
value is represented by a C<Time::Seconds> object.

  $time = $tg->totaltime();
  $tg->totaltime($time);

Call with a either a number of seconds or a C<Time::Seconds>
object to set this value.  Call with an undef value to unset
this value.  Returns a C<Time::Seconds> object with a value
of 0 seconds if undefined.

=cut

sub totaltime {
  my $self = shift;
  if (@_) {
    $self->_mutate_time('TotalTime',$_[0]);
  } elsif (! defined $self->{TotalTime}) {
    # Calculate total time since it isn't cached
    my @accounts = $self->accounts;
    my $timespent = Time::Seconds->new(0);
    for my $acct (@accounts) {
      $timespent += $acct->timespent;
    }
    # Store total
    $self->{TotalTime} = $timespent;
  }
  if (! defined $self->{TotalTime}) {
    return Time::Seconds->new(0);
  } else {
    return $self->{TotalTime};
  }
}

=item B<totaltime_non_ext>

The total time spent, except for extended time.  This
value is represented by a C<Time::Seconds> object.

  $time = $tg->totaltime_non_ext();
  $tg->totaltime_non_ext($time);

Call with a either a number of seconds or a C<Time::Seconds>
object to set this value.  Call with an undef value to unset
this value.

=cut

sub totaltime_non_ext {
  my $self = shift;
  if (@_) {
    $self->_mutate_time('TotalTimeNonExt',$_[0]);
  } elsif (! defined $self->{TotalTimeNonExt}) {
    # Get total and extended time
    my $total = $self->totaltime;
    my $extended = $self->ext_time;

    # Subtract extended time
    my $nonext = $total - $extended;

    # Store to cache
    $self->{TotalTimeNonExt} = $nonext;
  }
  return $self->{TotalTimeNonExt};
}

=item B<cal_time>

The total time spent on calibrations.  This value is represented by a
C<Time::Seconds> object.

  $time = $tg->cal_time();
  $tg->cal_time($time);

Call with a either a number of seconds or a C<Time::Seconds>
object to set this value.  Call with an undef value to unset
this value.

=cut

sub cal_time {
  my $self = shift;
  if (@_) {
    $self->_mutate_time('CalTime',$_[0]);
  } elsif (! defined $self->{CalTime}) {
    # Calculate CAL time since it isn't cached

    # Get just CAL accounts
    my @accounts = $self->_get_special_accts("CAL");

    my $timespent = Time::Seconds->new(0);
    for my $acct (@accounts) {
      $timespent += $acct->timespent;
    }
    # Store total
    $self->{CalTime} = $timespent;
  }
  return $self->{CalTime};
}

=item B<clear_time>

The amount of time where conditions were observable (everything
but weather loss and extended time).  This value is represented
by a C<Time::Seconds> object.

  $time = $tg->clear_time();
  $tg->clear_time($time);

Call with a either a number of seconds or a C<Time::Seconds>
object to set this value.  Call with an undef value to unset
this value.

=cut

sub clear_time {
  my $self = shift;
  if (@_) {
    $self->_mutate_time('ClearTime',$_[0]);
  } elsif (! defined $self->{ClearTime}) {
    # Get total non-extended and weather time
    my $nonext = $self->totaltime_non_ext;
    my $weather = $self->weather_loss;

    my $clear = $nonext - $weather;

    # Store to cache
    $self->{ClearTime} = $clear
  }
  return $self->{ClearTime};
}

=item B<ec_time>

Non-extended Time spent observing projects that are associated
with the E&C queue.

  $time = $tg->ec_time();
  $tg->ec_time($time);

Call with a either a number of seconds or a C<Time::Seconds>
object to set this value.  Call with an undef value to unset
this value.  Returns 0 seconds if undefined.

=cut

sub ec_time {
  my $self = shift;
  if (@_) {
    $self->_mutate_time('ECTime',$_[0]);
  } elsif (! defined $self->{ECTime}) {
    # Get EC accounts
    my @acct = $self->_get_accts('eng');

    # Add it up
    my $ectime = Time::Seconds->new(0);
    for my $acct (@acct) {
      $ectime += $acct->timespent;
    }

    # Store to cache
    $self->{ECTime} = $ectime;
  }
  return $self->{ECTime};
}

=item B<ext_time>

The total extended time spent.  This value is represented by a
C<Time::Seconds> object.

  $time = $tg->ext_time();
  $tg->ext_time($time);

Call with a either a number of seconds or a C<Time::Seconds>
object to set this value.  Call with an undef value to unset
this value.

=cut

sub ext_time {
  my $self = shift;
  if (@_) {
    $self->_mutate_time('ExtTime',$_[0]);
  } elsif (! defined $self->{ExtTime}) {
    # Calculate extended time since it isn't cached

    # Get just EXTENDED accounts
    my @accounts = $self->_get_special_accts("EXTENDED");

    my $timespent = Time::Seconds->new(0);
    for my $acct (@accounts) {
      $timespent += $acct->timespent;
    }
    # Store total
    $self->{ExtTime} = $timespent;
  }
  return $self->{ExtTime};
}

=item B<fault_loss>

The total time lost to faults.  This value is represented by a
C<Time::Seconds> object.

  $time = $tg->fault_loss();
  $tg->fault_loss($time);

Call with a either a number of seconds or a C<Time::Seconds>
object to set this value.  Call with an undef value to unset
this value.  Returns 0 seconds if the value is undefined.

=cut

sub fault_loss {
  my $self = shift;
  if (@_) {
    $self->_mutate_time('FaultLoss',$_[0]);
  } elsif (! defined $self->{FaultLoss}) {
    # Calculate fault loss time since it isn't cached

    # Get just the fault accounts
    my @acct = grep {$_->projectid eq '__FAULT__'} $self->accounts;

    my $timespent = Time::Seconds->new(0);
    for my $acct (@acct) {
      $timespent += $acct->timespent;
    }
    # Store total
    $self->{FaultLoss} = $timespent;
  }

  return $self->{FaultLoss};
}

=item B<observed_time>

The amount of time spent observing (everything but time lost to
weather and time spent doing "OTHER" things).  This value is
represented by a C<Time::Seconds> object.

  $time = $tg->observed_time();
  $tg->observed_time($time);

Call with a either a number of seconds or a C<Time::Seconds>
object to set this value.  Call with an undef value to unset
this value. Returns a C<Time::Seconds> object with a value
of 0 seconds if undefined.

=cut

sub observed_time {
  my $self = shift;
  if (@_) {
    $self->_mutate_time('ObservedTime',$_[0]);
  } elsif (! defined $self->{ObservedTime}) {
    # Get total, other, and weather time
    my $total = $self->totaltime;
    my $other = $self->other_time;
    my $weather = $self->weather_loss;

    # Subtract weather and other from total
    my $observed = $total - $weather - $other;

    # Store to cache
    $self->{ObservedTime} = $observed;
  }
  if (! defined $self->{ObservedTime}) {
    return Time::Seconds->new(0);
  } else {
    return $self->{ObservedTime};
  }
}

=item B<other_time>

The total time spent doing other things.  This value is represented by a
C<Time::Seconds> object.

  $time = $tg->other_time();
  $tg->other_time($time);

Call with a either a number of seconds or a C<Time::Seconds>
object to set this value.  Call with an undef value to unset
this value.

=cut

sub other_time {
  my $self = shift;
  if (@_) {
    $self->_mutate_time('OtherTime',$_[0]);
  } elsif (! defined $self->{OtherTime}) {
    # Calculate other time since it isn't cached

    # Get just OTHER accounts
    my @accounts = $self->_get_special_accts("OTHER");
    my $timespent = Time::Seconds->new(0);
    for my $acct (@accounts) {
      $timespent += $acct->timespent;
    }
    # Store total
    $self->{OtherTime} = $timespent;
  }
  return $self->{OtherTime};
}

=item B<science_time>

Non-extended Time spent observing projects not associated
with the E&C queue.

  $time = $tg->science_time();
  $tg->science_time($time);

Call with a either a number of seconds or a C<Time::Seconds>
object to set this value.  Call with an undef value to unset
this value.  Returns 0 seconds if undefined.

=cut

sub science_time {
  my $self = shift;
  if (@_) {
    $self->_mutate_time('ScienceTime',$_[0]);
  } elsif (! defined $self->{ScienceTime}) {
    # Get non-EC accounts
    my @acct = $self->_get_accts('sci');

    # Add it up
    my $scitime = Time::Seconds->new(0);
    for my $acct (@acct) {
      $scitime += $acct->timespent;
    }

    # Store to cache
    $self->{ScienceTime} = $scitime;
  }

  return $self->{ScienceTime};
}

=item B<shutdown_time>

Time spent on a planned shutdown.

  $time = $tg->shutdown_time();
  $tg->shutdown_time($time);

Call with a either a number of seconds or a C<Time::Seconds>
object to set this value.  Call with an undef value to unset
this value.  Returns 0 seconds if undefined.

=cut

sub shutdown_time {
  my $self = shift;
  if (@_) {
    $self->_mutate_time('ShutdownTime',$_[0]);
  } elsif (! defined $self->{ShutdownTime}) {
    # Get SHUTDOWN accounts
    my @accts = $self->_get_special_accts('_SHUTDOWN');

    # Add it up
    my $shuttime = Time::Seconds->new(0);
    for my $acct (@accts) {
      $shuttime += $acct->timespent;
    }

    # Store to cache
    $self->{ShutdownTime} = $shuttime;
  }

  return $self->{ShutdownTime};
}

=item B<weather_loss>

The total time lost to weather.  This value is represented by a
C<Time::Seconds> object.

  $time = $tg->weather_loss();
  $tg->weather_loss($time);

Call with a either a number of seconds or a C<Time::Seconds>
object to set this value.  Call with an undef value to unset
this value.  Returns 0 seconds if the value is undefined.

=cut

sub weather_loss {
  my $self = shift;
  if (@_) {
    $self->_mutate_time('WeatherLoss',$_[0]);
  } elsif (! defined $self->{WeatherLoss}) {
    # Calculate weather time since it isn't cached

    # Get just the weather accounts
    my @accounts = $self->_get_special_accts("WEATHER");

    my $timespent = Time::Seconds->new(0);
    for my $acct (@accounts) {
      $timespent += $acct->timespent;
    }
    # Store total
    $self->{WeatherLoss} = $timespent;
  }
  return $self->{WeatherLoss};
}

=item B<telescope>

The telescope that the time accounts are associated with.

  $tel = $tg->telescope();
  $tg->telescope($tel);

Returns a string.

=cut

sub telescope {
  my $self = shift;
  if (@_) {
    my $tel = shift;
    $self->{Telescope} = uc($tel);
  }
  return $self->{Telescope};
}

=item B<db>

A shared database connection (an C<OMP::DBbackend> object). The first
time this is called, triggers a database connection.

  $db = $tg->db;

Takes no arguments.

=cut

sub db {
  my $self = shift;
  if (!defined $self->{DB}) {
    $self->{DB} = new OMP::DBbackend;
  }
  return $self->{DB};
}

=back

=head2 General Methods

=over 4

=item B<completion_stats>

Produce statistics suitable for use in a time-series plot.

  %stats = $tg->completion_stats;

Returns a hash containing the following keys:

  science - contains an array reference of coordinates where
            X is an integer MJD date and Y is the completion
            percentage on that date.  No binning is done on
            these values.

  weather - contains an array reference of coordinates where
            X is a modified Julian date and Y is the hours lost
            to weather on that date. These values are binned up
            by 7 day periods.

  ec      - contains an array reference of coordinates where
            X is a modified Julian date and Y is the hours spent
            on E&C projects on that date. These values are binned
            up by 7 day periods

  fault   - contains an array reference of coordinates where
            X is a modified Julian date and Y is the hours lost
            to faults on that date. These values are binned up
            by 7 day periods.

  __ALLOC__  - contains the total time allocated to projects
               during the semesters spanned by the accounts in
               this group.  Value is represented by an
               C<OMP::Seconds> object.
  __OFFSET__ - contains the total time spent during previous
               semesters on projects associated with the accounts
               in this group.  Value is represented by an
               C<OMP::Seconds> object.

=cut

sub completion_stats {
  my $self = shift;

  my $telescope = $self->_get_telescope();
  my @semesters = $self->_get_semesters();
  my $lowdate = $self->_get_low_date();
  $lowdate -= 1;

  # Get total TAG allocation for semesters
  my $projdb = new OMP::ProjDB(DB=>$self->db);
  my $alloc = 0;
  for my $sem (@semesters) {
    $alloc += $projdb->getTotalAlloc($telescope, $sem);
  };

  # DEBUG
  printf "\nTotal allocation: [%.1f] hours\n", $alloc->hours;

  # Offset correction: get total time spent on the projects
  # we have accounts for, prior to date of the first account.
  # Subtract this number from the total allocation.
  my @accts = $self->_get_non_special_accts();
  my %projectids = map {$_->projectid, undef} @accts;
  my $tdb = new OMP::TimeAcctDB(DB=>$self->db);
  my $xml = "<TimeAcctQuery>".
    "<date><max>".$lowdate->datetime."</max></date>".
      join("",map {"<projectid>$_</projectid>"} keys %projectids).
	"</TimeAcctQuery>";
  my $query = new OMP::TimeAcctQuery(XML=>$xml);
  my @offset_accts = $tdb->queryTimeSpent( $query );
  my $offset_grp = $self->new(accounts=>\@offset_accts);

  #DEBUG
  printf "Offset (time spent on these projects in previous semesters): [%.1f] hours\n", $offset_grp->science_time->hours;

  my $final_alloc = $alloc - $offset_grp->science_time;

  #DEBUG
  printf "Total allocation minus offset: [%.1f] hours\n", $final_alloc->hours;

  # Get all accounts grouped by UT date
  my %groups = $self->group_by_ut(1);

  # Map Y values to X (date)
  my $sci_total = 0;
  my (@sci_cumul, @fault, @weather, @ec);
  for my $x (sort keys %groups) {
    $sci_total += $groups{$x}->science_time;
    push @sci_cumul, [$x, $sci_total / $final_alloc * 100];
    push @weather, [$x, $groups{$x}->weather_loss->hours];
    push @ec, [$x, $groups{$x}->ec_time->hours];
    push @fault, [$x, $groups{$x}->fault_loss->hours];
  }

  my %returnhash = (
		    science => \@sci_cumul,
		    fault => \@fault,
		    ec => \@ec,
		    weather => \@weather,
		    __ALLOC__ => $alloc,
		    __OFFSET__ => $offset_grp->science_time,
		   );

  for my $stat (keys %returnhash) {
    next if $stat eq 'science' or $stat =~ /^__/;
    @{$returnhash{$stat}} = OMP::PlotHelper->bin_up(size => 7,
						    method => 'sum',
						    values => $returnhash{$stat});
  }

  return %returnhash;
}


=item B<group_by_ut>

Group all the C<OMP::Project::TimeAcct> objects by UT date.  Store
each group in an C<OMP::TimeAcctGroup> object.  Return a hash indexed
by UT date where each key points to an C<OMP::TimeAcctGroup> object.

  %groups = $tg->group_by_ut(1);

If the optional argument is true, The returned hash is indexed by
an integer modified Julian date.

=cut

sub group_by_ut {
  my $self = shift;
  my $mjd = shift;
  my @acct = $self->accounts;

  my $method = ($mjd ? "mjd" : "strftime('%Y%m%d')");
  # Group by UT date
  my %accts;
  for my $acct (@acct) {
    push @{$accts{$acct->date->$method}}, $acct;
  }

  # Convert each group into an OMP::TimeAcctGroup object
  for my $ut (keys %accts) {
    $accts{$ut} = $self->new(accounts=>$accts{$ut});
  }

  return %accts;
}

=item B<populate>

Populate the object.

  $tg->populate(
                accounts => \@accounts,
                telescope => $tel,
              );

Arguments are to be given in hash form, with the keys being the names
of the accessor methods.

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

=item B<pushacct>

Add more accounts to the group.

  $tg->pushacct(@acct);
  $tg->pushacct(\@acct);

Takes either an array or a reference to an array of C<OMP::Project::TimeAcct>
objects.  Returns true on success.

=cut

sub pushacct {
  my $self = shift;
  my @addacct = @_;
  my @currentacct = $self->accounts;
  $self->accounts([@currentacct,@addacct]);
  return 1;
}

=item B<remdupe>

Remove duplicate accounts from the group.

  $tg->remdupe();

=cut

sub remdupe {
  my $self = shift;
  my @acct = $self->accounts;

  my @unique_acct;
  for my $old (@acct) {
    my $exists = 0;
    for my $unique (@unique_acct) {
      if ($old == $unique) {
	$exists = 1;
      }
    }
    push @unique_acct, $old
      unless ($exists);
  }

  $self->accounts(@unique_acct);

  return 1;
}

=back

=head2 Internal Methods

=over 4

=item B<_get_non_special_accts>

Return only non-special accounts.

  @accts = $self->_get_non_special_accts();

=cut

sub _get_non_special_accts {
  my $self = shift;

  # Create regexp to filter out special projects
  my $telpart = join('|', OMP::Config->getData('defaulttel'));
  my $specpart = join('|', qw/CAL EXTENDED OTHER WEATHER/);
  my $regexp = qr/^(${telpart})(${specpart})$/;

  # Filter out "__FAULT__" accounts and accounts that are named 
  # something like TELESCOPECAL, etc.
  my @acct = grep {$_->projectid !~ $regexp and $_->projectid ne '__FAULT__'}
    $self->accounts;

  if (wantarray) {
    return @acct;
  } else {
    return \@acct;
  }
}

=item B<_get_accts>

Return either science accounts (accounts that are not associated with
projects in the E&C queue) or E&C.  Special
accounts are not returned (WEATHER, CAL, EXTENDED, OTHER, __FAULT__).

  @accts = $self->_get_accts('sci'|'eng');

Argument is a string that is either 'sci' or 'eng'.  Returns either
an array or an array reference.  Returns an empty list if no accounts
could be returned.

=cut

sub _get_accts {
  my $self = shift;
  my $arg = shift;

  throw OMP::Error::BadArg("Argument must be either 'sci' or 'eng'")
    unless ($arg eq 'sci' or $arg eq 'eng');

  # Get the regular accounts
  my @acct = $self->_get_non_special_accts;

  # Return immediately if we didn't get any accounts back
  return
    unless (defined $acct[0]);

  # Get project objects, using a different query depending on whether
  # we are returning science or engineering accounts
  my $db = new OMP::ProjDB(DB => $self->db,);
  my $tel_xml = "<telescope>". $self->_get_telescope ."</telescope>";
  my $query_xml;
  if ($arg eq 'sci') {
    # Get all the projects in the semesters that we have time
    # accounts for.
    my $sem_xml = join ("", map {"<semester>$_</semester>"} $self->_get_semesters());
    $query_xml = "<ProjQuery>${sem_xml}${tel_xml}</ProjQuery>";
  } else {
    # Get projects in the EC queue
    $query_xml = "<ProjQuery><country>EC</country><isprimary>1</isprimary>${tel_xml}</ProjQuery>";
  }

  my $query = new OMP::ProjQuery(XML=>$query_xml);
  my @projects = $db->listProjects($query);
  my %projects = map {$_->projectid, $_} @projects;

  if ($arg eq 'sci') {
    # Only keep non-EC projects
    @acct = grep {
      exists $projects{$_->projectid} and $projects{$_->projectid}->isScience
    } @acct;
  } else {
    # Only keep EC projects
    @acct = grep { exists $projects{$_->projectid} } @acct;
  }

  if (wantarray) {
    return @acct;
  } else {
    return \@acct;
  }
}

=item B<_get_special_accts>

Return only accounts with project IDs that begin with a telescope
name and end with the given string.  Does not return the special
accounts with the project ID '__FAULT__'.

  @accts = $self->_get_special_accts("CAL");

=cut

sub _get_special_accts {
  my $self = shift;
  my $proj = shift;

  my @accounts = $self->accounts;
  my $regexpart = $self->telescope;

  @accounts = grep {$_->projectid =~ /^(${regexpart})${proj}$/} @accounts;
  if (wantarray) {
    return @accounts;
  } else {
    return \@accounts;
  }
}

=item B<_get_low_date>

Retrieve the date of the first non-special account object.

  $date = $self->_get_low_date();

=cut

sub _get_low_date {
  my $self = shift;
  my @accts = $self->_get_non_special_accts;
  return $accts[0]->date;
}

=item B<_get_semesters>

Retrieve the list of semesters that the science time accounts span.

  @sems = $self->_get_semesters();

Returns a list, or reference to a list.

=cut

sub _get_semesters {
  my $self = shift;
  my @accts = $self->_get_non_special_accts;
  my $tel = $self->_get_telescope;
  my %sem = map {
    OMP::General->determine_semester(date => $_->date, tel => $tel), undef
    } @accts;

  if (wantarray) {
    return keys %sem;
  } else {
    return [keys %sem];
  }
}

=item B<_get_telescope>

Retrieve the telescope name associated with the first time account object.

  $tel = $self->_get_telescope();

=cut

sub _get_telescope {
  my $self = shift;
  my @accts = $self->_get_non_special_accts;
  my $db = new OMP::ProjDB(DB=>$self->db,
			   ProjectID=>$accts[0]->projectid,
			  );
  return $db->getTelescope();
}

=item B<_mutate_time>

Reset the time or store a new time for one of the object properties.

  $self->_mutate_time("WeatherLoss", 32000);

=cut

sub _mutate_time {
  my $self = shift;
  my $key = shift;
  my $value = shift;

  if (! defined $value) {
    $self->{$key} = undef;
  } else {
    # Set the new value
    my $time = shift;
    $time = new Time::Seconds( $time )
      unless UNIVERSAL::isa($time, "Time::Seconds");
    $self->{$key} = $time;
  }
}

=back

=head1 AUTHOR

Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>

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
along with this program (see SLA_CONDITIONS); if not, write to the 
Free Software Foundation, Inc., 59 Temple Place, Suite 330, 
Boston, MA  02111-1307  USA


=cut

1;
