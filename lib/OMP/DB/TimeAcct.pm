package OMP::DB::TimeAcct;

=head1 NAME

OMP::DB::TimeAcct - Manipulate the time accounting database

=head1 SYNOPSIS

    $acctdb = OMP::DB::TimeAcct->new(DB => $dbconnection);

    @time = $acctdb->getTimeSpent();
    $acctdb->setTimeSpent(@time);

=head1 DESCRIPTION

This class manipulates the time accounting database. It can
be used to set the time spent on a particular project on a particular
day and to return project totals.

=cut

use 5.006;
use strict;
use warnings;
use Carp;
our $VERSION = '2.000';

use OMP::Error qw/:try/;
use OMP::Project::TimeAcct;
use OMP::Query::TimeAcct;
use OMP::DateTools;
use OMP::General;
use OMP::DB::Project;
use OMP::Constants qw/:fb/;

use base qw/OMP::DB/;
our $ACCTTABLE  = 'omptimeacct';

=head2 Time Accounting

These methods adjust the time spent on a given project and provide
methods for obtaining the time accounting details for given dates
or projects.

=over 4

=item B<getTimeSpent>

Retrieve the time accounting details for the specified project and/or
UT date.

When called in list context returns all the C<OMP::Project::TimeAcct>
objects that are relevant.

    @accounts = $db->getTimeAccounting(projectid => $proj);
    @accpimts = $db->getTimeAccounting(utdate => $date);

The date must either be supplied as a Time::Piece object
or in YYYY-MM-DD format. If a telescope is specified along with
the UT date, the resulting projects will be filtered by telescope.

    @accpimts = $db->getTimeAccounting(utdate => $date, telescope => 'JCMT');

When a request for a project query is called in scalar context
returns a reference to an array containing two elements:

=over 4

=item *

the total approved time

=item *

the total time awaiting approval

=back

Scalar context has no meaning for a UT date query.

=cut

sub getTimeSpent {
    my $self = shift;
    my %args = @_;

    # check
    if (! exists $args{projectid} && ! exists $args{utdate}) {
        throw OMP::Error::BadArgs(
            "getTimeAccounting: must have either a projectid or UT date");
    }

    # if we had a date just extract the year, month and day
    my $date;
    if ($args{utdate}) {
        if (UNIVERSAL::isa($args{utdate}, "Time::Piece")) {
            $date = $args{utdate}->strftime('%Y-%m-%d');
        }
        else {
            $date = $args{utdate};
        }
    }

    # if we have a shifttype use that.
    my $shifttype;
    if ($args{shifttype}) {
        $shifttype = $args{shifttype};
    }

    # Create the query object
    # Note that we do not want to go exactly one day forward here
    my $q = OMP::Query::TimeAcct->new(HASH => {
        ((exists $args{'projectid'})
            ? (projectid => $args{'projectid'})
            : ()),
        ($date
            ? (date => {delta => 0.99999, value => $date})
            : ()),
        ($shifttype
            ? (shifttype => $shifttype)
            : ()),
    });

    # Run the query
    my @matches = $self->queryTimeSpent($q);

    # If we have a telescope specified must do an additional filter
    # but only if we did not do a project query
    if ($args{telescope} && ! $args{projectid}) {
        my $tel = uc($args{telescope});
        @matches = grep {
            OMP::DB::Project->new(DB => $self->db, ProjectID => $_->projectid)->verifyTelescope($tel)
        } @matches;
    }

    # determine context?
    return @matches;
}

=item B<verifyTimeAcctEntry>

Verify whether a specific entry exists in the database
and return an up-to-date version of the object. Accepts
and returns an C<OMP::Project::TimeAcct> object.

    $new = $db->verifyTimeAcctEntry($ref);

Returns undef if the relevant entry could not be located.
The supplied object must be fully specified except for its
time allocation and confirmed status.

=cut

sub verifyTimeAcctEntry {
    my $self = shift;
    my $ref = shift;

    throw OMP::Error::FatalError("Reference object is not of the correct type")
        unless UNIVERSAL::isa($ref, "OMP::Project::TimeAcct");

    # until we get tau bands and other things included in the allocation
    # this is essentially getTimeSpent
    my @results = $self->getTimeSpent(
        projectid => $ref->projectid,
        utdate => $ref->date,
        shifttype => $ref->shifttype);

    # return the result
    return $results[0];
}


=item B<queryTimeSpent>

Do a generic query on the time accounting database. The argument
must be a C<OMP::Query::TimeAcct> object. Returns all the
matches as C<OMP::Project::TimeAcct> objects.

    @matches = $db->queryTimeSpent($q);

=cut

sub queryTimeSpent {
    my $self = shift;
    my $query = shift;

    # run the query
    my @results = $self->_run_timeacct_query($query);

    # context check?
    return @results;
}

=item B<setTimeSpent>

Takes a list of C<OMP::Project::TimeAcct> objects and
inserts the relevant information into the database.

    $db->setTimeSpent(@acct);

Recalculates the total time spent on a project and updates
the project table. Also sends a message to the feedback system.

=cut

sub setTimeSpent {
    my $self = shift;
    my @acct = @_;

    # Connect to the DB (and lock it out)
    $self->_db_begin_trans;
    $self->_dblock;

    # lop through each array and store it
    for my $acct (@acct) {
        $self->_insert_timeacct_entry($acct);
    }

    # instantiate a OMP::DB::Project object
    my $projdb = OMP::DB::Project->new(DB => $self->db);

    # get a summary of all the project data
    # grouped by project ID and UT date
    my %projects = OMP::Project::TimeAcct->summarizeTimeAcct(
        'byprojdate', @acct);

    # now need to recalculate the time spent for each project
    for my $proj (keys %projects) {
        # update the OMP::DB::Project object with the current project id
        $projdb->projectid($proj);

        # Some of the projects are not real (eg WEATHER, SCUBA)
        # so in those cases we just skip
        # Rather than doing an opt-in simply look for project validity
        next unless $projdb->verifyProject();

        # get the new totals
        my @all = $self->getTimeSpent(projectid => $proj);

        # calculate the totals for this project only
        my %results = OMP::Project::TimeAcct->summarizeTimeAcct('all', @all);
        my $pending = $results{pending};
        my $used = $results{confirmed};

        # get the project object
        my $project = $projdb->_get_project_row;

        # Modify the project
        $project->pending($pending);
        $project->remaining($project->allocated - $used);

        # Update the contents in the table
        $projdb->_update_project_row($project);

        # notify the feedback system - this is based on what was actually
        # changed rather than everything (hence we use %projects and not @all)
        for my $ut (keys %{$projects{$proj}}) {
            $self->projectid($proj);
            my ($subject, $text);
            # the message depends on whether we have pending >0 or
            # confirmed >0 [can only be one or the other]
            if (exists $projects{$proj}{$ut}{pending}
                    && $projects{$proj}{$ut}{pending} > 0) {
                # pending
                $subject = "[$proj] Adjust time awaiting confirmation for UT $ut";
                $text = "The amount of time awaiting confirmation for UT $ut is now $projects{$proj}{$ut}{pending} seconds";
            }
            elsif (exists $projects{$proj}{$ut}{confirmed}
                    && $projects{$proj}{$ut}{confirmed} > 0) {
                # confirmed
                $subject = "[$proj] Time spent on project $proj now confirmed for UT $ut";
                $text = "Confirmed that $projects{$proj}{$ut}{confirmed} seconds was assigned to project $proj for UT date $ut";
            }
            else {
                # both zero
                $subject = "[$proj] No time spent on project for UT $ut";
                $text = "The time assigned to project $proj for UT date $ut has been reset to zero seconds";
            }

            $self->_notify_feedback_system(
                subject => $subject,
                text => $text,
                msgtype => OMP__FB_MSG_TIME_ADJUST_CONFIRM,
            );
        }
    }

    # Disconnect
    $self->_dbunlock;
    $self->_db_commit_trans;
}

=item B<incPending>

Increment the time pending for a project by the specified amount.  The
date, projectid and time to be added are obtained from a
C<OMP::Project::TimeAcct> object.

=cut

sub incPending {
    my $self = shift;
    my $pending = shift;

    # Connect to the DB (and lock it out)
    $self->_db_begin_trans;
    $self->_dblock;

    # first need to see if there is already an entry in the database
    my $current = $self->verifyTimeAcctEntry($pending);

    # add the two together
    if (defined $current) {
        $pending->incTime($current);
    }

    # set the pending flag
    $pending->confirmed(0);

    # and store it [this method does the locking but we need to
    # make sure we do not get out of sync]
    $self->setTimeSpent($pending);

    # Disconnect
    $self->_dbunlock;
    $self->_db_commit_trans;
}


=back

=head2 Internal Methods

=over 4

=item B<_run_timeacct_query>

Internal method to run the actual SQL query on the time accounting table.

    @results = $db->_run_timeacct_query($query);

Requires C<OMP::Query::TimeAcct> object and returns
C<OMP::ProjecT::TimeAcct> objects.

=cut

sub _run_timeacct_query {
    my $self = shift;
    my $query = shift;

    # get the SQL
    my $sql = $query->sql($ACCTTABLE);
    #print "SQL: $sql\n";

    # run it
    my $ref = $self->_db_retrieve_data_ashash($sql);

    # First parse the date field and convert it to a date object
    for my $row (@$ref) {
        my $date = OMP::DateTools->parse_date($row->{date});
        throw OMP::Error::FatalError(
            "Unable to parse date '" . $row->{date}
            . "' from time accounting table")
            unless defined $date;
        $row->{date} = $date;
    }

    # now convert these table entries to objects
    my @acct = map {
        OMP::Project::TimeAcct->new(%$_)
    } @$ref;

    return @acct;
}

=item B<_clear_old_timeacct_row>

Remove the entry associated with the specified C<OMP::Project::TimeAcct>
object.

    $db->_clear_old_timeacct_row($acct);

This allows a new entry to be inserted (easier than doing one query
to look for it and then deciding on UPDATE vs INSERT).

The object must include a project ID, a UT date and a shifttype.

=cut

sub _clear_old_timeacct_row {
    my $self = shift;
    my $acct = shift;

    # generate a hash representation of the object
    # that will match the column names
    my %details = (
        projectid => $acct->projectid,
        date => $acct->date->strftime('%Y-%m-%d'),
        shifttype => $acct->shifttype,
    );

    # construct the where clause
    # from the relevant keys
    my @clauses;
    for my $key (qw/projectid shifttype/) {
        throw OMP::Error::FatalError(
            "Must provide both UTDATE, SHIFTTYPE and PROJECTID to _clear_old_acct_row")
            unless exists $details{$key};

        push @clauses, " $key = '$details{$key}' ";
    }

    # at the moment delete everything for that ut date. This might be
    # dangerous in the long term until we sort out the timing properly
    # (for example sybase treats "YYYY-MM-DD" as midday rather than
    # midnight
    push @clauses, " date >= '$details{date} 00:00:00' AND date <= '$details{date} 23:59:59'";

    my $clause = join " AND ", @clauses;

    # delete the row
    $self->_db_delete_data($ACCTTABLE, $clause);

    return;
}

=item B<_insert_timeacct_entry>

Insert a new entry into the table, overwriting any previous
entry.

    $db->_insert_timeacct_entry($acct);

Requires the time to be specified as an C<OMP::Project::TimeAcct>
object.

=cut

sub _insert_timeacct_entry {
    my $self = shift;
    my $acct = shift;

    # delete old entry
    $self->_clear_old_timeacct_row($acct);

    # get the information we need
    my $proj = uc($acct->projectid);
    my $timespent = $acct->timespent->seconds;
    my $conf = $acct->confirmed;
    my $date = $acct->date->strftime('%Y-%m-%d');
    my $shifttype = $acct->shifttype;
    my $comment = $acct->comment;

    # insert
    $self->_db_insert_data(
        $ACCTTABLE,
        $date,
        $proj,
        $timespent,
        $conf,
        $shifttype,
        $comment);
}

1;

__END__

=back

=head1 SEE ALSO

This class inherits from C<OMP::DB>.

For related classes see C<OMP::DB::MSB> and C<OMP::DB::Project>.

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research
Council.  All Rights Reserved.

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

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut
