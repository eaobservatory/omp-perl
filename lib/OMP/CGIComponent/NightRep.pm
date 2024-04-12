package OMP::CGIComponent::NightRep;

=head1 NAME

OMP::CGIComponent::NightRep - CGI functions for the observation log tool

=head1 SYNOPSIS

    use OMP::CGIComponent::NightRep;

=head1 DESCRIPTION

This module provides routines used for CGI-related functions for
obslog -- variable verification, form creation, etc.

=cut

use strict;
use warnings;

use CGI::Carp qw/fatalsToBrowser/;
use Net::Domain qw/hostfqdn/;

use OMP::Config;
use OMP::Constants qw/:obs :timegap/;
use OMP::Display;
use OMP::DateTools;
use OMP::DB::Archive;
use OMP::MSBDoneDB;
use OMP::NightRep;
use OMP::General;
use OMP::Info::Comment;
use OMP::Info::Obs;
use OMP::Info::ObsGroup;
use OMP::ObslogDB;
use OMP::ProjDB;
use OMP::Project::TimeAcct;
use OMP::TimeAcctDB;
use OMP::Error qw/:try/;

use base qw/OMP::CGIComponent/;

our $VERSION = '2.000';

=head1 Routines

=over 4

=item B<obs_table_text>

Prints a plain text table containing a summary of information about a
group of observations.

    $comp->obs_table_text($obsgroup, %options);

The first argument is the C<OMP::Info::ObsGroup>
object, and remaining options tell the function how to
display things.

=over 4

=item showcomments

Boolean on whether or not to print comments [true].

=back

=cut

sub obs_table_text {
    my $self = shift;
    my $obsgroup = shift;
    my %options = @_;

    # Verify the ObsGroup object.
    unless (UNIVERSAL::isa($obsgroup, "OMP::Info::ObsGroup")) {
        throw OMP::Error::BadArgs("Must supply an Info::ObsGroup object");
    }

    my $showcomments;
    if (exists($options{showcomments})) {
        $showcomments = $options{showcomments};
    }
    else {
        $showcomments = 1;
    }

    my $nr = OMP::NightRep->new(DB => $self->database);
    my $summary = $nr->get_obs_summary(obsgroup => $obsgroup, %options);

    unless (defined $summary) {
        print "No observations for this night\n";
        return;
    }

    my $is_first_block = 1;
    foreach my $instblock (@{$summary->{'block'}}) {
        my $ut = $instblock->{'ut'};
        my $currentinst = $instblock->{'instrument'};

        if ($is_first_block) {
            print "\nObservations for " . $currentinst . " on $ut\n";
        }
        else {
            print "\nObservations for " . $currentinst . "\n";
        }

        print $instblock->{'heading'}->{_STRING_HEADER}, "\n";

        foreach my $entry (@{$instblock->{'obs'}}) {
            my $obs = $entry->{'obs'};
            my $nightlog = $entry->{'nightlog'};

            if ($entry->{'is_time_gap'}) {
                print $nightlog->{'_STRING'}, "\n";
            }
            else {
                my @text;
                if (exists $entry->{'msb_comments'}) {
                    my $comment = $entry->{'msb_comments'};

                    my $title = '';
                    $title = sprintf "%s\n", $comment->{'title'}
                        if defined $comment->{'title'};

                    foreach my $c (@{$comment->{'comments'}}) {
                        push @text, $title . sprintf "%s UT by %s\n%s\n",
                            $c->date,
                            ((defined $c->author) ? $c->author->name : 'UNKNOWN PERSON'),
                            $c->text();
                    }
                }

                print @text, "\n", $nightlog->{'_STRING'}, "\n";

                if ($showcomments) {
                    # Print the comments underneath, if there are any, and if the
                    # 'showcomments' parameter is not '0', and if we're not looking at a timegap
                    # (since timegap comments show up in the nightlog string)
                    my $comments = $obs->comments;
                    if (defined($comments) && defined($comments->[0])) {
                        foreach my $comment (@$comments) {
                            print "    " . $comment->date->cdate . " UT / " . $comment->author->name . ":";
                            print $comment->text . "\n";
                        }
                    }
                }
            }
        }

        $is_first_block = 0;
    }
}

=item B<obs_comment_form>

Returns information for a form that is used to enter a comment about
an observation or time gap.

    $values = $comp->obs_comment_form($obs, $projectid);

The first argument must be a an C<Info::Obs> object.

=cut

sub obs_comment_form {
    my $self = shift;
    my $obs = shift;
    my $projectid = shift;

    return {
        statuses => (eval {$obs->isa('OMP::Info::Obs::TimeGap')}
            ? [
                [OMP__TIMEGAP_UNKNOWN() => 'Unknown'],
                [OMP__TIMEGAP_INSTRUMENT() => 'Instrument'],
                [OMP__TIMEGAP_WEATHER() => 'Weather'],
                [OMP__TIMEGAP_FAULT() => 'Fault'],
                [OMP__TIMEGAP_NEXT_PROJECT() => 'Next project'],
                [OMP__TIMEGAP_PREV_PROJECT() => 'Last project'],
                [OMP__TIMEGAP_NOT_DRIVER() => 'Observer not driver'],
                [OMP__TIMEGAP_SCHEDULED() => 'Scheduled downtime'],
                [OMP__TIMEGAP_QUEUE_OVERHEAD() => 'Queue overhead'],
                [OMP__TIMEGAP_LOGISTICS() => 'Logistics'],
                ]
            : [
                map {
                    [$_ => $OMP::Info::Obs::status_label{$_}]
                } @OMP::Info::Obs::status_order
            ]
        ),
    };
}

=item B<obs_add_comment>

Store a comment in the database.

    $comp->obs_add_comment();

=cut

sub obs_add_comment {
    my $self = shift;

    my $q = $self->cgi;

    # Set up variables.
    my $qv = $q->Vars;
    my $status = $qv->{'status'};
    my $text = (defined($qv->{'text'}) ? $qv->{'text'} : "");

    # Get the Info::Obs object from the CGI object
    my $obs = $self->cgi_to_obs();

    # Form the Info::Comment object.
    my $comment = OMP::Info::Comment->new(
        author => $self->auth->user,
        text => $text,
        status => $status,
    );

    # Store the comment in the database.
    my $odb = OMP::ObslogDB->new(DB => $self->database);
    $odb->addComment($comment, $obs);

    return {
        messages => ['Comment successfully stored in database.'],
    };
}

=item B<time_accounting_shift>

Prepare time accounting information for a shift.

This generates an information hash for the given shift containing:

=over 4

=item shift

Name of shift.

=item entries

List of time accounting entries.

=back

=cut

sub time_accounting_shift {
    my $self = shift;
    my $tel = shift;
    my $shift = shift;
    my $times = shift;
    my $timelost = shift;

    my %exclude = map {$tel . $_ => 1} qw/
        EXTENDED WEATHER UNKNOWN OTHER FAULT BADOBS _SHUTDOWN
    /;
    my @entries = ();

    # If this shift exists in the times:
    my %rem;
    if (defined $times) {
        for my $proj (sort keys %$times) {
            if ($proj =~ /^$tel/) {
                $rem{$proj} ++;
            }
            else {
                push @entries, $self->_time_accounting_project(1, $proj, $times->{$proj});
            }
        }

        # Now put up everything else (except EXTENDED which is a special case)
        # and special WEATHER and UNKNOWN which we want to force the order
        for my $proj (sort keys %rem) {
            next if exists $exclude{$proj};
            push @entries, $self->_time_accounting_project(1, $proj, $times->{$proj});
        }
    }

    # Now put up the WEATHER, UNKNOWN
    my %strings = (
        WEATHER => 'Time lost to weather',
        _SHUTDOWN => 'Scheduled shutdown',
        OTHER => 'Other time',
    );
    for my $label (qw/WEATHER _SHUTDOWN OTHER/) {
        my $proj = $tel . $label;
        push @entries, $self->_time_accounting_project(
            1, $strings{$label},
            (exists $times->{$proj} ? $times->{$proj} : {}),
            key => $proj,
        );
    }

    push @entries,
        $self->_time_accounting_project(
            0, 'Time lost to faults',
            {},
            time_fixed => (defined $timelost ? $timelost->hours : 0.0),
            key => $tel . 'FAULTS',
        ),
        $self->_time_accounting_project(
            0, 'Bad/junk obs (not in total)',
            $times->{$tel . 'BADOBS'},
            key => $tel . 'BADOBS',
            no_total => 1,
        ),
        $self->_time_accounting_project(
            0, 'Total time',
            {},
            key => 'TOTAL',
        ),
        $self->_time_accounting_project(
            1, 'Extended time',
            (exists $times->{$tel . 'EXTENDED'} ? $times->{$tel . 'EXTENDED'} : {}),
            key => $tel . 'EXTENDED',
            no_total => 1,
        );

    return {
        shift => $shift,
        entries => \@entries,
    };
}

sub _time_accounting_project {
    my $self = shift;
    my $editable = shift;
    my $proj = shift;
    my $times = shift;
    my %opt = @_;

    my %entry = (
        name => $proj,
        editable => $editable,
    );

    foreach my $param (qw/key no_total/) {
        $entry{$param} = $opt{$param} if exists $opt{$param};
    }

    # Decide on the default value
    # Choose DATA over DB unless DB is confirmed.
    if (exists $opt{'time_fixed'}) {
        $entry{'time'} = sprintf '%.2f', $opt{'time_fixed'};
    }
    elsif (exists $times->{DB} and $times->{DB}->confirmed) {
        # Confirmed overrides data headers
        $entry{'time'} = _round_to_ohfive($times->{DB}->timespent->hours);
        $entry{'comment'} = $times->{DB}->comment;
    }
    elsif (exists $times->{DATA}) {
        $entry{'time'} = _round_to_ohfive($times->{DATA}->timespent->hours);
    }
    elsif (exists $times->{DB}) {
        $entry{'time'} = _round_to_ohfive($times->{DB}->timespent->hours);
        $entry{'comment'} = $times->{DB}->comment;
    }
    else {
        # Empty
        $entry{'time'} = '';
    }

    # Notes about the data source
    if (exists $times->{DB}) {
        $entry{'status'} = 'ESTIMATED';
        if ($times->{DB}->confirmed) {
            $entry{'status'} = 'CONFIRMED';
        }

        # Now also add the MSB estimate if it is an estimate
        # Note that we put it after the DATA estimate
        unless ($times->{DB}->confirmed) {
            $entry{'time_msb'} = _round_to_ohfive($times->{DB}->timespent->hours);
        }
    }
    elsif (exists $times->{DATA} and not $times->{DATA}->confirmed) {
        $entry{'status'} = 'ESTIMATED';
    }

    if (exists $times->{DATA}) {
        $entry{'time_data'} = _round_to_ohfive($times->{DATA}->timespent->hours);
    }

    return \%entry;
}

# Round to nearest 0.05
# Accepts number, returns number with the decimal part rounded to 0.05

sub _round_to_ohfive {
    my $num = shift;

    my $frac = 100 * ($num - int($num));
    my $byfive = $frac / 5;

    $frac = 5 * int( $byfive + 0.5 );

    return sprintf '%.2f', int($num) + ($frac / 100);
}

=item B<read_time_accounting_shift>

Read time accounting form for one shift.

Takes an information hash as generated by C<time_accounting_shift>
and updates the included list of entries based on the CGI parameters.

Returns a list of errors encountered, if any.

=cut

sub read_time_accounting_shift {
    my $self = shift;
    my $info = shift;

    my $q = $self->cgi;
    my $shift = $info->{'shift'};

    my %seen = ();
    my @errors = ();

    foreach my $entry (@{$info->{'entries'}}) {
        next unless $entry->{'editable'};
        my $key = $entry->{exists $entry->{'key'} ? 'key' : 'name'};
        $seen{$key} = 1;

        die 'Invalid time' unless $q->param(sprintf 'time_%s_%s', $shift, $key) =~ /^([0-9.]*)$/;
        $entry->{'time'} = $1;

        die 'Invalid comment' unless $q->param(sprintf 'comment_%s_%s', $shift, $key) =~ /^(.*)$/;
        $entry->{'comment'} = $1;
    }

    my $pattern = qr/^time_${shift}_(\w+)$/a;
    my $ndup = 0;

    foreach my $param ($q->param) {
        next unless $param =~ $pattern;
        my $key = $1;
        next if exists $seen{$key} or $key eq 'new';

        die 'Invalid project' unless $q->param(sprintf 'name_%s_%s', $shift, $key) =~ /^([A-Za-z0-9]*)$/;
        my $name = $1;

        die 'Invalid time' unless $q->param(sprintf 'time_%s_%s', $shift, $key) =~ /^([0-9.]*)$/;
        my $time = $1;

        die 'Invalid comment' unless $q->param(sprintf 'comment_%s_%s', $shift, $key) =~ /^(.*)$/;
        my $comment = $1;

        my %entry = (
            editable => 1,
            name => $name,
            time => $time,
            comment => $comment,
            user_added => 1,
        );

        if (exists $seen{$name}) {
            push @errors, sprintf 'Duplicate entry for %s: %s.', $shift, $name;
            $entry{'key'} = sprintf 'dup_%i', ++ $ndup;
        }
        else {
            $seen{$key} = 1;
        }

        push @{$info->{'entries'}}, \%entry;
    }

    return @errors;
}

=item B<store_time_accounting>

Attempt to store time accounting to the database.

Converts a list of hashes updated by C<read_time_accounting_shift>
and converts them to C<OMP::Project::TimeAcct> objects.

Returns a list of errors encountered.  If there were none, stores
the time accounting information in the database and updates the
given C<OMP::NightRep> object.

=cut

sub store_time_accounting {
    my $self = shift;
    my $nr = shift;
    my $shifts = shift;

    my $date = $nr->date;

    my @errors = ();
    my @acct = ();

    foreach my $info (@$shifts) {
        my $shift = $info->{'shift'};

        foreach my $entry (@{$info->{'entries'}}) {
            my $proj = $entry->{exists $entry->{'key'} ? 'key' : 'name'};
            next if $proj eq 'TOTAL' or $proj =~ /FAULTS/ or $proj =~/BADOBS/;

            # If the project was added by the user, verify that it exists and
            # is enabled.
            if ($entry->{'user_added'}) {
                my $projdb = OMP::ProjDB->new(DB => $self->database, ProjectID => $proj);
                unless ($projdb->verifyProject()) {
                    push @errors, sprintf 'Project %s does not exist.', $proj;
                    next;
                }

                my $p = $projdb->projectDetails();
                unless ($p->state) {
                    push @errors, sprintf 'Project %s exists but is disabled.', $proj;
                    next;
                }
            }

            my $tot = $entry->{'time'};
            $tot = 0.0 unless length($tot);

            my $comment = $entry->{'comment'};
            undef $comment if $comment eq '';

            push @acct, OMP::Project::TimeAcct->new(
                projectid => $proj,
                timespent => Time::Seconds->new($tot * 3600),
                date => $date,
                confirmed => 1,
                shifttype => $shift,
                comment => $comment,
            );
        }
    }

    unless (scalar @errors) {
        my $db = OMP::TimeAcctDB->new(DB => $self->database);
        $db->setTimeSpent(@acct);

        $nr->db_accounts(OMP::TimeAcctGroup->new(accounts => \@acct));
    }

    return @errors;
}

=item B<cgi_to_obs>

Return an C<Info::Obs> object.

    $obs = $comp->cgi_to_obs();

In order for this method to work properly, the parent page's C<CGI> object
must have the following URL parameters:

=over 4

=item ut

In the form YYYY-MM-DD-hh-mm-ss, where the month, day, hour,
minute and second can be optionally zero-padded. The month is 1-based
(i.e. a value of "1" is January) and the hour is 0-based and based on
the 24-hour clock.

=item runnr

The run number of the observation.

=item inst

The instrument that the observation was taken with. Case-insensitive.

=back

=cut

sub cgi_to_obs {
    my $self = shift;

    my $verify = {
        'ut' => qr/^(\d{4}-\d\d-\d\d-\d\d?-\d\d?-\d\d?)/a,
        'runnr' => qr/^(\d+)$/a,
        'inst' => qr/^([\-\w\d]+)$/a,
        'timegap' => qr/^([01])$/,
        'oid' => qr/^([a-zA-Z]+[-_A-Za-z0-9]+)$/,
    };

    my $ut = $self->_cleanse_query_value('ut', $verify);
    my $runnr = $self->_cleanse_query_value('runnr', $verify);
    my $inst = $self->_cleanse_query_value('inst', $verify);
    my $timegap = $self->_cleanse_query_value('timegap', $verify);
    $timegap ||= 0;
    my $obsid = $self->_cleanse_query_value('oid', $verify);

    # Form the Time::Piece object
    $ut = Time::Piece->strptime($ut, '%Y-%m-%d-%H-%M-%S');

    # Get the telescope.
    my $telescope = uc(OMP::Config->inferTelescope('instruments', $inst));

    # Form the Info::Obs object.
    my $obs;
    if ($timegap) {
        $obs = OMP::Info::Obs::TimeGap->new(
            runnr => $runnr,
            endobs => $ut,
            instrument => $inst,
            telescope => $telescope,
            obsid => $obsid,
        );
    }
    else {
        $obs = OMP::Info::Obs->new(
            runnr => $runnr,
            startobs => $ut,
            instrument => $inst,
            telescope => $telescope,
            obsid => $obsid,
        );
    }

    # Comment-ise the Info::Obs object.
    my $db = OMP::ObslogDB->new(DB => $self->database);
    $db->updateObsComment([$obs]);

    # And return the Info::Obs object.
    return $obs;
}

=item B<cgi_to_obsgroup>

Given a hash of information, return an C<Info::ObsGroup> object.

    $obsgroup = $comp->cgi_to_obsgroup(ut => $ut, inst => $inst);

In order for this method to work properly, the hash
should have the following keys:

=over 4

=item ut

In the form YYYY-MM-DD.

=back

Other parameters are optional and can include:

=over 4

=item inst

The instrument that the observation was taken with.

=item projid

The project ID for which observations will be returned.

=item telescope

The telescope that the observations were taken with.

=back

The C<inst> and C<projid> variables are optional, but either one or the
other (or both) must be defined.

These parameters will override any values contained in the parent page's
C<CGI> object.

=cut

sub cgi_to_obsgroup {
    my $self = shift;
    my %args = @_;

    my $q = $self->cgi;

    my $ut = defined($args{'ut'}) ? $args{'ut'} : undef;
    my $inst = defined($args{'inst'}) ? uc($args{'inst'}) : undef;
    my $projid = defined($args{'projid'}) ? $args{'projid'} : undef;
    my $telescope = defined($args{'telescope'}) ? uc($args{'telescope'}) : undef;
    my $inccal = defined($args{'inccal'}) ? $args{'inccal'} : 0;
    my $timegap = defined($args{'timegap'}) ? $args{'timegap'} : 1;

    my $qv = $q->Vars;
    $ut = (defined($ut) ? $ut : $qv->{'ut'});
    $inst = (defined($inst) ? $inst : uc($qv->{'inst'}));
    $projid = (defined($projid) ? $projid : $qv->{'projid'});
    $telescope = (defined($telescope) ? $telescope : uc($qv->{'telescope'}));

    if (! defined($telescope) || length($telescope . '') == 0) {
        if (defined($inst) && length($inst . '') != 0) {
            $telescope = uc(OMP::Config->inferTelescope('instruments', $inst));
        }
        elsif (defined($projid)) {
            $telescope = OMP::ProjDB->new(
                DB => $self->database, ProjectID => $projid)->getTelescope();
        }
        else {
            throw OMP::Error("OMP::CGIComponent::NightRep: Cannot determine telescope!\n");
        }
    }

    unless (defined $ut) {
        throw OMP::Error::BadArgs("Must supply a UT date in order to get an Info::ObsGroup object");
    }

    my %options = (
        date => $ut,
        ignorebad => 1,
    );

    $options{'inccal'} = $inccal if $inccal;
    $options{'timegap'} = OMP::Config->getData('timegap') if $timegap;
    $options{'telescope'} = $telescope if defined $telescope;
    $options{'projectid'} = $projid if defined $projid;
    $options{'instrument'} = $inst if defined($inst) && length($inst . '') > 0;

    my $arcdb = OMP::DB::Archive->new(
        DB => $self->page->database_archive,
        FileUtil => $self->page->fileutil);

    my $grp = OMP::Info::ObsGroup->new(
        ADB => $arcdb,
        %options,
    );

    return $grp;
}

=item B<_cleanse_query_value>

Returns the cleansed URL parameter value given a CGI object,
parameter name, and a hash reference of parameter names as keys &
compiled regexen (capturing a value to be returned) as values.

    $value = $comp->_cleanse_query_value(
        'number', {
            'number' => qr/^(\d+)$/a,
        });

=cut

sub _cleanse_query_value {
    my ($self, $key, $verify) = @_;

    my $val = $self->page->decoded_url_param($key);

    return unless defined $val
        && length $val;

    my $regex = $verify->{$key} or return;

    return ($val =~ $regex)[0];
}

1;

__END__

=back

=head1 SEE ALSO

C<OMP::CGIPage::NightRep>

=head1 AUTHOR

Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2008 Science and Technology Facilities Council.
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
along with this program; if not, write to the
Free Software Foundation, Inc., 59 Temple Place, Suite 330,
Boston, MA  02111-1307  USA

=cut
