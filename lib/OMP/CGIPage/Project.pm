package OMP::CGIPage::Project;

=head1 NAME

OMP::CGIPage::Project - Web display of complete project information pages

=head1 SYNOPSIS

    use OMP::CGIPage::Project;

=head1 DESCRIPTION

Helper methods for creating and displaying complete web pages that
display project information.

=cut

use 5.006;
use strict;
use warnings;
use CGI::Carp qw/fatalsToBrowser/;
use Time::Seconds;

use OMP::CGIComponent::Fault;
use OMP::CGIComponent::MSB;
use OMP::CGIComponent::Project;
use OMP::Constants qw(:fb);
use OMP::Config;
use OMP::DB::Fault;
use OMP::Display;
use OMP::Error qw(:try);
use OMP::DB::Feedback;
use OMP::UserDB;
use OMP::DateTools;
use OMP::General;
use OMP::DB::MSB;
use OMP::MSBServer;
use OMP::ProjAffiliationDB;
use OMP::ProjDB;
use OMP::ProjQuery;
use OMP::TimeAcctDB;
use OMP::SiteQuality;

use base qw/OMP::CGIPage/;

our $telescope = 'JCMT';

$| = 1;

=head1 Routines

=over 4

=item B<fb_fault_content>

Display a fault along with a list of faults associated with the project.
Also provide a link to the feedback comment submission page for responding
to the fault.

    $page->fb_fault_content($projectid);

=cut

sub fb_fault_content {
    my $self = shift;
    my $projectid = shift;

    # Get a fault component object
    my $faultcomp = OMP::CGIComponent::Fault->new(page => $self);

    my $faultdb = OMP::DB::Fault->new(DB => $self->database);
    my @faults = $faultdb->getAssociations($projectid, 0);

    # Display the first fault if a fault isnt specified in the URL
    my $showfault;
    my $faultid = $self->decoded_url_param('fault');
    if ($faultid) {
        my %faults = map {$_->faultid, $_} @faults;
        $showfault = $faults{$faultid};
    }
    else {
        $showfault = $faults[0];
    }

    return {
        project => OMP::ProjDB->new(DB => $self->database, ProjectID => $projectid)->projectDetails(),
        fault_list => $faultcomp->show_faults(
            faults => \@faults,
            descending => 0,
            url => "fbfault.pl?project=$projectid"),
        fault_info => (defined $showfault
            ? $faultcomp->fault_table($showfault, no_edit => 1)
            : undef),
    };
}

=item B<list_projects>

Create a page with a form prompting for the semester to list projects for.

    $page->list_projects();

=cut

sub list_projects {
    my $self = shift;

    my $q = $self->cgi;

    my $comp = OMP::CGIComponent::Project->new(page => $self);

    return $comp->list_projects_form(telescope => $telescope)
        unless $q->param('submit_search');

    my $semester = $q->param('semester');
    my $state = ($q->param('state') eq 'all' ? undef : $q->param('state'));
    my $status = ($q->param('status') eq 'all' ? undef : $q->param('status'));
    my $support = $q->param('support');
    my $country = $q->param('country');
    my $order = $q->param('order');

    undef $semester if $semester =~ /any/i;
    undef $support if $support eq '';
    undef $country if $country eq '';

    OMP::General->log_message("Projects list retrieved by user " . $self->auth->user->userid);

    my $projects = OMP::ProjDB->new(DB => $self->database)->listProjects(OMP::ProjQuery->new(HASH => {
        (defined $state ? (state => {boolean => $state}) : ()),
        (defined $status ? (status => $status) : ()),
        (defined $semester ? (semester => $semester) : ()),
        (defined $support ? (support => $support) : ()),
        (defined $country ? (country => [split /\+/, $country]) : ()),
        telescope => $telescope,
    }));

    my @sorted = ();
    if (@$projects) {
        # Group by either project ID or TAG priority
        # If grouping by project ID, group by telescope, semester, and
        # country, then sort by project number.
        # Otherwise, group the projects by country and telescope, then
        # sort by TAG priority, or adjusted priority.
        #
        # NOTE: This may be too slow.  We will probably want to let the
        # database do the sorting and grouping for us in the future,
        # although that will require OMP::ProjQuery to support
        # <orderby> and <groupby> tags

        if ($order eq 'projectid') {
            my %group;
            for (@$projects) {
                # Try to get the semester from the project ID since that is
                # more useful for sorting than the actual semester which will
                # be the same for all projects
                my $sem = $_->semester_ori;
                (! $sem) and $sem = $_->semester;

                # Fudge with semesters like 99A so that they are sorted
                # before and not after later semesters like 00B and 04A
                ($sem =~ /^(9\d)([ab])$/aai) and $sem = $1 - 100 . $2;

                push @{$group{$_->telescope}{$sem}{$_->country}}, $_;
            }

            # Grouping is finished. Now sort.
            for my $telescope (sort keys %group) {
                for my $semester (sort {$a <=> $b} keys %{$group{$telescope}}) {
                    for my $country (sort keys %{$group{$telescope}{$semester}}) {
                        my @tmpsort = sort {$a->project_number <=> $b->project_number}
                            @{$group{$telescope}{$semester}{$country}};

                        push @sorted, @tmpsort;
                    }
                }
            }
        }
        else {
            my %adj_priority;
            for (@$projects) {

                $adj_priority{$_} = $_->tagpriority();

                next unless $order eq 'adj-priority';

                my $adj = $_->tagadjustment($_->primaryqueue())
                    or next;

                $adj_priority{$_} += $adj;
            }

            if ($telescope and $country) {
                @sorted = sort {$adj_priority{$a} <=> $adj_priority{$b}} @$projects;
            }
            else {
                my %group;
                for (@$projects) {
                    push @{$group{$_->telescope}{$_->country}}, $_;
                }

                for my $telescope (sort keys %group) {
                    for my $country (sort keys %{$group{$telescope}}) {
                        my @sortedcountry = sort {$adj_priority{$a} <=> $adj_priority{$b}}
                            @{$group{$telescope}{$country}};
                        push @sorted, @sortedcountry;
                    }
                }
            }
        }
    }

    return {
        %{$comp->list_projects_form(telescope => $telescope)},
        %{$comp->proj_sum_table(\@sorted, ($order ne 'priority'))},
        values => {
            semester => $semester,
            state => $state,
            status => $status,
            support => $support,
            country => $country,
            order => $order,
        },
    };
}

=item B<project_home>

Create a page which has a simple summary of the project and links to the rest of the system that are easy to follow.

    $page->project_home($projectid);

=cut

sub project_home {
    my $self = shift;
    my $projectid = shift;

    my $msbcomp = OMP::CGIComponent::MSB->new(page => $self);
    my $msbdb = OMP::DB::MSB->new(DB => $self->database);
    my $msbdonedb = OMP::MSBDoneDB->new(DB => $self->database, ProjectID => $projectid);

    # Get the project details
    my $project = OMP::ProjDB->new(DB => $self->database, ProjectID => $projectid)->projectDetails();

    # Get nights for which data was taken
    my $nights = $msbdonedb->observedDates(1);

    # Since time may have been charged to the project even though no MSBs
    # were observed, check with the accounting DB as well
    my $adb = OMP::TimeAcctDB->new(DB => $self->database);

    # Because of shifttypes, there may be more than one shift per night.
    my @accounts = $adb->getTimeSpent(projectid => $project->projectid);

    # Display nights where data was taken
    my %accounts = ();
    # Sort account objects by night
    for my $acc (@accounts) {
        my $ymd = $acc->date->ymd;
        unless (exists $accounts{$ymd}) {
            $accounts{$ymd} = {
                confirmed => 0.0,
                unconfirmed => 0.0,
            };
        }
        $accounts{$ymd}->{$acc->confirmed ? 'confirmed' : 'unconfirmed'}
            += $acc->timespent->hours;
    }

    # Some instruments do not allow data retrieval. For now, assume that
    # we can not retrieve if any of the instruments in the project are marked as such.
    # For surveys this will usually be the case
    my $cannot_retrieve;
    try {
        my @noretrieve = OMP::Config->getData("unretrievable", telescope => $project->telescope);
        my $projinst = $msbdb->getInstruments(${projectid});

        # See if the instrument in the project are listed in noretrieve
        my %inproj = map {(uc($_), undef)}
            (exists $projinst->{$projectid} ? @{$projinst->{$projectid}} : ());

        for my $nr (@noretrieve) {
            if (exists $inproj{uc($nr)}) {
                $cannot_retrieve = 1;
                last;
            }
        }
    }
    otherwise {
    };

    # Get the "important" feedback comments
    my $fdb = OMP::DB::Feedback->new(ProjectID => $projectid, DB => $self->database);
    my $comments = $fdb->getComments(status => [OMP__FB_IMPORTANT]);

    return {
        project => $project,
        is_staff => (!! $self->auth->is_staff),
        proposal_url => 'https://proposals.eaobservatory.org/'
            . (lc $project->telescope)
            . '/proposal_by_code?code=' . $projectid,
        today => OMP::DateTools->today(),
        accounts => \%accounts,
        cannot_retrieve => $cannot_retrieve,
        msbs_observed => ((scalar @$nights)
            ? $msbcomp->fb_msb_observed($projectid)
            : undef),
        msbs_active => $msbcomp->fb_msb_active($projectid),
        comments => $comments,
        taurange_is_default => sub {
            return OMP::SiteQuality::is_default('TAU', $_[0]);
        },
        seeingrange_is_default => sub {
            return OMP::SiteQuality::is_default('SEEING', $_[0]);
        },
        skyrange_is_default => sub {
            return OMP::SiteQuality::is_default('SKY', $_[0]);
        },
        cloudrange_is_default => sub {
            return OMP::SiteQuality::is_default('CLOUD', $_[0]);
        },
    };
}

=item B<program_summary>

View summary text of a science program.

=cut

sub program_summary {
    my $self = shift;
    my $projectid = shift;

    my $q = $self->cgi;

    my $sp = undef;
    my $error = undef;
    try {
        my $db = OMP::DB::MSB->new(
            ProjectID => $projectid,
            DB => $self->database);
        $sp = $db->fetchSciProg(1);
    }
    catch OMP::Error::UnknownProject with {
        $error = "Science program for $projectid not present in the database.";
    }
    catch OMP::Error::SpTruncated with {
        $error = "Science program for $projectid is in the database but has been truncated.";
    }
    otherwise {
        my $E = shift;
        $error = "Error obtaining science program details for project $projectid: $E";
    };

    return $self->_write_error($error)
        if defined $error;

    return $self->_write_error('The science program could not be fetched for this project.')
        unless defined $sp;

    # Program retrieved successfully: apply summary XSLT.
    print $q->header(-type => 'text/plain', -charset => 'utf-8');

    $sp->apply_xslt('toml_summary.xslt');
}

=item B<proposals>

View proposals for specific projects.

    $page->proposals($projectid);

=cut

sub proposals {
    my $self = shift;
    my $projectid = shift;

    my $q = $self->cgi;

    # Proposals directory
    my $propdir = OMP::Config->getData('propdir');

    # Which directories to use?
    my @dirs;
    push(@dirs, $propdir);

    my $propfilebase = $projectid;

    $propfilebase =~ s/\W//ag;
    $propfilebase = lc($propfilebase);

    my %extensions = (
        ps => "application/postscript",
        pdf => "application/pdf",
        "ps.gz" => "application/postscript",
        "txt" => "text/plain",
    );

    my $propfile;
    my $type;
    #  File name to offer for file being downloaded.
    my $offer = 'proposal';

    DIRLOOP: for my $dir (@dirs) {
        for my $ext (qw/ps pdf ps.gz txt/) {
            my $name = "$propfilebase.$ext";
            if (-e "$dir/$name") {
                $propfile = "$dir/$name";
                $offer .= '-' . $name;
                $type = $extensions{$ext};
                last DIRLOOP;
            }
        }
    }

    if ($propfile) {
        # Read in proposal file
        open(my $fh, '<', $propfile);
        my @file = <$fh>;    # Slurrrp!

        close($fh);

        # Serve proposal
        print $q->header(
            -type => $type,
            -Content_Disposition => "attachment; filename=$offer",
        );

        print join("", @file);

        # Enter log message
        my $message = "Proposal for $projectid retrieved.";
        OMP::General->log_message($message);
    }
    else {
        # Proposal file not found
        return $self->_write_error("Proposal file not available.");
    }
}

=item B<project_users>

Create a page displaying users associated with a project.

    $page->project_users($projectid);

First argument should be the project ID.

=cut

sub project_users {
    my $self = shift;
    my $projectid = shift;

    my $q = $self->cgi;

    my $db = OMP::ProjDB->new(
        ProjectID => $projectid,
        DB => $self->database,
    );

    # Get the project info
    my $project = $db->projectDetails();

    # Get contacts
    my @contacts = $project->investigators;

    if ($q->param('update_contacts')) {
        my %new_contactable;
        my %new_access;

        # Go through each of the contacts and store their new contactable values
        my $count_email;
        my $count_access;
        for (@contacts) {
            my $userid = $_->userid;

            $new_contactable{$userid} = ($q->param('email_' . $userid) ? 1 : 0);
            $count_email += $new_contactable{$userid};

            $new_access{$userid} = ($q->param('access_' . $userid) ? 1 : 0);
            $count_access += $new_access{$userid};
        }

        # Make sure at least 1 person is getting emails
        if ($count_email == 0) {
            return $self->_write_error('The system requires at least 1 person to receive project emails.  Update aborted.');
        }
        # Same for OMP access.
        if ($count_access == 0) {
            return $self->_write_error('The system requires at least 1 person to have OMP access.  Update aborted.');
        }

        # Store user contactable info to database (have to actually store
        # entire project back to database)
        my $error = undef;
        try {
            $db->updateContactability(\%new_contactable);
            $db->updateOMPAccess(\%new_access);
            $project->contactable(%new_contactable);
            $project->omp_access(%new_access);
        }
        otherwise {
            my $E = shift;
            $error = "An error prevented the contactable information from being updated: $E";
        };

        return $self->_write_error($error) if defined $error;

        return $self->_write_redirect('/cgi-bin/projecthome.pl?project=' . $projectid);
    }

    # Get contactables and those with OMP access.
    my %contactable = $project->contactable;
    my %access = $project->omp_access;

    return {
        target => $self->url_absolute(),
        project => $project,
        contacts => [map {
            my $userid = $_->userid;
            {
                user => $_,
                contactable => $contactable{$userid},
                access => $access{$userid}
            };
        } sort {$a->name cmp $b->name} @contacts],
    };
}

=item B<support>

Create a page listing staff contacts for a project and which also provides a form for defining which is the primary staff contact.

    $page->support();

=cut

sub support {
    my $self = shift;

    my $q = $self->cgi;

    # Try and get a project ID
    my $projectid = OMP::General->extract_projectid($self->decoded_url_param('project'));

    return {
        target_base => $q->url(-absolute => 1),
        project_id => $projectid,
        contacts => undef,
        } unless defined $projectid;

    my $projdb = OMP::ProjDB->new(
        ProjectID => $projectid,
        DB => $self->database,
    );

    # Verify that project exists
    my $verify = $projdb->verifyProject;
    return $self->_write_error("No project with ID of [$projectid] exists.")
        unless $verify;

    # Get project details (as object)
    my $project;
    my $E;
    try {
        $project = $projdb->projectDetails();
    }
    catch OMP::Error with {
        $E = shift;
    };

    return $self->_write_error(
        "An error occurred while getting project details.", "$E")
        if defined $E;

    return $self->_write_error("Could not get project details.")
        unless $project;

    $self->_sidebar_project($project->projectid);

    # Get support contacts
    my @support = $project->support;

    # Make contact changes, if any
    if ($q->param('update_contacts')) {
        my %new_contactable;
        my %new_access;

        for (@support) {
            my $userid = $_->userid;

            $new_contactable{$userid} = ($q->param('email_' . $userid) ? 1 : 0);

            $new_access{$userid} = ($q->param('access_' . $userid) ? 1 : 0);
        }

        # Must have at least one primary contact defined.
        if (scalar grep {$_} values %new_contactable) {
            # Store changes to DB
            my $E;
            try {
                $projdb->updateContactability(\%new_contactable);
                $projdb->updateOMPAccess(\%new_access);
                $project->contactable(%new_contactable);
                $project->omp_access(%new_access);
            }
            otherwise {
                $E = shift;
            };

            return $self->_write_error(
                "An error occurred.  Your changes have not been stored.", "$E")
                if defined $E;
        }
        else {
            # No new primary contacts defined
            return $self->_write_error(
                "At least one primary support contact must be defined.  Your changes have not been stored.");
        }
    }

    # Store primary
    my @primary = grep {$project->contactable($_->userid)} @support;

    # Store secondary
    my @secondary = grep {! $project->contactable($_->userid)} @support;

    my %contactable = $project->contactable;
    my %access = $project->omp_access;

    return {
        target_base => $q->url(-absolute => 1),
        project_id => $projectid,

        target => $self->url_absolute(),
        contacts => [map {
            my $userid = $_->userid;
            {
                user => $_,
                contactable => $contactable{$userid},
                access => $access{$userid},
            };
        } sort {$a->name cmp $b->name} @support],
        primary => \@primary,
        secondary => \@secondary,
    };
}

=item B<alter_proj>

Create a page for adjusting a project's properties.

    $page->alter_proj();

=cut

sub alter_proj {
    my $self = shift;

    my $q = $self->cgi;

    my $projectid = OMP::General->extract_projectid($self->decoded_url_param('project'));

    return {
        target_base => $q->url(-absolute => 1),
        project => undef,
    } unless defined $projectid;

    # Connect to the database
    my $projdb = OMP::ProjDB->new(
        ProjectID => $projectid,
        DB => $self->database,
    );

    # Verify that project exists
    my $verify = $projdb->verifyProject;
    return $self->_write_error("No project with ID of [$projectid] exists.")
        unless $verify;

    # Retrieve the project object
    my $project = $projdb->_get_project_row();

    $self->_sidebar_project($project->projectid);

    return $self->process_project_changes($project, $projdb)
        if $q->param('alter_submit');

    my $pi = $project->pi->userid();
    my $pi_affiliation = $project->pi->affiliation();
    $pi .= ':' . $pi_affiliation if defined $pi_affiliation;

    my $coi = join "\n", map {
        my $userid = $_->userid();
        my $coi_affiliation = $_->affiliation();
        $userid .= ':' . $coi_affiliation if defined $coi_affiliation;
        $userid;
    } $project->coi;

    my $supp = join "\n", map {
        my $userid = $_->userid;
        my $supp_affiliation = $_->affiliation();
        $userid .= ':' . $supp_affiliation if defined $supp_affiliation;
        $userid;
    } $project->support;

    # Allocation
    my $allocated = $project->allocated;
    my $remaining = $project->remaining;
    # my ($alloc_h, $alloc_m, $alloc_s) = split(/\D/,$allocated->pretty_print);
    my $alloc_h = int($allocated / 3600);
    my $alloc_m = int(($allocated - $alloc_h * 3600) / 60);
    my $alloc_s = $allocated - $alloc_h * 3600 - $alloc_m * 60;

    # Get semester options
    my @semesters = $projdb->listSemesters(telescope => $project->telescope);

    # Get cloud options
    my %cloud_lut = OMP::SiteQuality::get_cloud_text();
    my %cloud_labels = map {$cloud_lut{$_}->max(), $_} keys %cloud_lut;
    my @clouds = sort {$b->[0] <=> $a->[0]} map {
        [$cloud_lut{$_}->max(), $_]
    } keys %cloud_lut;

    # Tag adjustment
    my %tagpriority = $project->queue;
    my %tagadj = $project->tagadjustment;
    my @priority = ();

    for my $queue (sort keys %tagpriority) {
        push @priority, {
            queue => $queue,
            adj => ($tagadj{$queue} =~ /^\d+$/a ? '+' : '') . $tagadj{$queue},
            priority => $tagpriority{$queue},
        };
    }

    return {
        target_base => undef,

        project => $project,
        target => $self->url_absolute(),
        values => {
            pi => $pi,
            coi => $coi,
            support => $supp,
            alloc_h => $alloc_h,
            alloc_m => $alloc_m,
            alloc_s => $alloc_s,
            cloud => int($project->cloudrange->max()),
            priority => \@priority,
        },
        semesters => \@semesters,
        clouds => \@clouds,

        messages => undef,
    };
}

sub process_project_changes {
    my $self = shift;
    my ($project, $projdb) = @_;

    my $q = $self->cgi;

    my @msg;  # Build up output message

    for my $type (qw/pi coi support/) {
        my $err;
        my $users = $q->param($type);
        try {
            push @msg, $self->update_users($project, $type, split /[;,\s]+/, $users);
        }
        catch OMP::Error with {
            my ($e) = @_;
            $err = $e->text;
        };

        return $self->_write_error($err) if defined $err;
    }

    push @msg, _update_project_make_message(
        $project,
        \&_match_string,
        'update' => 'title',
        'field-text' => 'title',
        'old' => $project->title,
        'new' => scalar $q->param('title'),
    );

    # Check whether state changed.
    my $new_state = $q->param('state');
    if ($new_state xor $project->state) {
        $project->state($new_state ? 1 : 0);
        push @msg, sprintf 'Project %s.', ($new_state ? 'enabled' : 'disabled');
    }

    # Check whether allocation has changed
    my $new_alloc_h = $q->param('alloc_h') * 3600;
    my $new_alloc_m = $q->param('alloc_m') * 60;
    my $new_alloc_s = $q->param('alloc_s');
    my $new_alloc = Time::Seconds->new($new_alloc_h + $new_alloc_m + $new_alloc_s);
    my $old_alloc = $project->allocated;

    if ($new_alloc != $old_alloc) {
        # Allocation was changed
        $project->fixAlloc($new_alloc->hours);

        push @msg, "Updated allocated time from "
            . $old_alloc->pretty_print
            . " to " . $new_alloc->pretty_print . ".";
    }

    # Check whether semester has changed
    my $new_sem = $q->param('semester');
    my $old_sem = $project->semester;

    if ($new_sem ne $old_sem) {
        # Semester waschanged
        $project->semester($new_sem);

        push @msg, "Updated semester from " . $old_sem
            . " to " . $new_sem . ".";
    }

    # Check whether cloud constraint has changed
    my $new_cloud_max = $q->param('cloud');
    my $new_cloud = OMP::SiteQuality::default_range('CLOUD');
    $new_cloud->max($new_cloud_max);
    my $old_cloud = $project->cloudrange;

    if ($new_cloud->max() != $old_cloud->max()) {

        # Cloud constraint was changed
        $project->cloudrange($new_cloud);

        push @msg, "Updated cloud range constraint from " . $old_cloud
            . " to " . $new_cloud . ".";
    }

    # Check whether TAG adjustment has changed
    my %oldadj = $project->tagadjustment;
    my %newadj;
    for my $queue (keys %oldadj) {
        $newadj{$queue} = $q->param('tag_' . $queue);

        # Taint checking

        if (defined $newadj{$queue} and $newadj{$queue} != $oldadj{$queue}) {
            # POSSIBLE KLUGE: setting a new tagadjustment causes the actual
            # tagpriority to change, which is okay when reading a project
            # object, but not okay when storing the object back to the database.
            # In order to reset the tagpriority, the tagpriority method is
            # called with its original value.

            my $oldpriority = $project->tagpriority($queue);

            $project->tagadjustment({$queue, $newadj{$queue}});

            $project->tagpriority($queue => $oldpriority);

            push @msg, "Updated TAG adjustment for $queue queue from $oldadj{$queue} to $newadj{$queue}.";
        }
    }

    # Check whether TAU range has changed
    my $old_taurange = $project->taurange;
    my %tau_params;
    $tau_params{Min} = $q->param('taumin');
    $tau_params{Max} = $q->param('taumax')
        unless (! $q->param('taumax'));
    my $new_taurange = OMP::Range->new(%tau_params);

    if ($old_taurange->min() != $new_taurange->min()
            or $old_taurange->max() != $new_taurange->max()) {
        $project->taurange($new_taurange);

        push @msg, "Updated TAU range from " . $old_taurange
            . " to " . $new_taurange . ".";
    }

    # Check whether Seeing range has changed
    my $old_seeingrange = $project->seeingrange;
    my %seeing_params;
    $seeing_params{Min} = $q->param('seeingmin');
    $seeing_params{Max} = $q->param('seeingmax')
        unless (! $q->param('seeingmax'));
    my $new_seeingrange = OMP::Range->new(%seeing_params);

    if ($old_seeingrange->min() != $new_seeingrange->min()
            or $old_seeingrange->max() != $new_seeingrange->max()) {
        $project->seeingrange($new_seeingrange);

        push @msg, "Updated Seeing range from " . $old_seeingrange
            . " to " . $new_seeingrange . ".";
    }

    # Check whether the expiry date was changed
    my $old_expirydate = $project->expirydate();
    my $expirydate = $q->param('expirydate');
    if ((not defined $old_expirydate) and (! $expirydate)) {
        # Expiry date null in database and not set here: do nothing.
    }
    elsif ((not defined $old_expirydate)
            or (! $expirydate)
            or ($expirydate ne "$old_expirydate")) {
        # Expiry date has changed.
        undef $expirydate unless $expirydate;
        $project->expirydate($expirydate);

        push @msg, 'Updated expiry date from '
            . ($old_expirydate // 'none')
            . ' to ' . ($expirydate // 'none')
            . '.';
    }

    # Generate feedback message

    # Get OMP user object
    if ($q->param('send_mail')) {
        my $fdb = OMP::DB::Feedback->new(ProjectID => $project->projectid, DB => $self->database);
        $fdb->addComment(
            {
                author => $self->auth->user,
                subject => 'Project details altered',
                text =>
                    "The following changes have been made to this project:\n\n"
                    . join("\n", @msg)
            },
        );
    }

    # Now store the changes
    $projdb->_update_project_row($project);

    if (scalar @msg) {
        push @msg,
            (scalar @msg == 1
                ? 'This change has'
                : 'These changes have')
            . ' been committed.';
    }
    else {
        push @msg, "No changes were submitted.";
    }

    return {
        target_base => undef,

        project => $project,
        target => undef,

        messages => \@msg,
    };
}

sub update_users {
    my $self = shift;
    my ($proj, $type, @userid) = @_;

    return unless $proj && (scalar @userid or $type ne 'pi');

    my @old = $proj->$type;

    my $old_id = join ',', map {
        my $id = $_->userid();
        my $affiliation = $_->affiliation();
        $id .= ':' . $affiliation if defined $affiliation;
        $id;
    } @old;

    return if _match_string($old_id, join ',', @userid);

    my @user = map {$self->_make_user($_)} @userid;

    if ($type eq 'pi') {
        # The "pi" method only accepts a single user (first argument) so pass
        # list directly.
        $proj->$type(@user);
    }
    else {
        # Pass list as a reference in case it is empty.
        $proj->$type(\@user);
    }

    my $join = sub {
        join ', ', map {$_->name} @_;
    };

    return sprintf 'Updated %s from (%s) to (%s)',
        $type,
        $join->(@old),
        $join->(@user);
}

sub _make_user {
    my $self = shift;
    my ($userid) = @_;

    return unless $userid;

    my $affiliation;
    ($userid, $affiliation) = split ':', $userid, 2;

    my $user = OMP::UserDB->new(DB => $self->database)->getUser($userid)
        or throw OMP::Error "Unknown user ID given: $userid";

    if (defined $affiliation) {
        throw OMP::Error::FatalError("User $userid affiliation '$affiliation' not recognized by the OMP")
            unless exists $OMP::ProjAffiliationDB::AFFILIATION_NAMES{$affiliation};

        $user->affiliation($affiliation);
    }

    return $user;
}

sub _match_string {
    my ($one, $two) = @_;

    return (defined $one && defined $two)
        && ($one eq $two);
}

sub _match_number {
    my ($one, $two) = @_;

    return (defined $one && defined $two)
        && ($one == $two);
}

sub _update_project_make_message {
    my ($project, $match, %args) = @_;

    my ($old, $new) = @args{qw/old new/};

    return if $match && $match->($old, $new);

    my $update = $args{'update'};

    $project->$update($new)
        and return qq[Updated $args{'field-text'} from "$old" to "$new".];

    return;
}

sub translate_msb {
    my $self = shift;
    my $projectid = shift;

    return $self->_write_forbidden() unless $self->auth->is_staff;

    die 'No valid checksum specified'
        unless $self->decoded_url_param('checksum') =~ /^([0-9a-f]+[OAS]*)$/a;
    my $checksum = $1;

    # Import OMP::Translator here because CGI scripts using this method will
    # need to use JAC::Setup qw/ocsq ocscfg/ to make the relevant modules available.
    require OMP::Translator;
    require IO::String;

    my $logh = IO::String->new();
    my $error = undef;
    my $result = undef;

    try {
        my $db = OMP::DB::MSB->new(
            ProjectID => $projectid,
            DB => $self->database);

        my $msb = $db->fetchMSB(checksum => $checksum, internal => 1);

        $result = OMP::Translator->translate(
            OMP::SciProg->new(XML => $msb->dummy_sciprog_xml()),
            asdata => 1,
            loghandle => $logh,
            no_log_input => 1);
    }
    catch OMP::Error with {
        my $E = shift;
        $error = $E->{'-text'};
    }
    otherwise {
        my $E = shift;
        if (UNIVERSAL::isa($E, 'XML::LibXML::Error')) {
            $error = $E->as_string();
        }
        else {
            $error = "$E";
        }
    };

    my $logref = $logh->string_ref;

    return {
        checksum => $checksum,
        error => $error,
        log => $$logref,
        configs => $result,
    };
}

1;

__END__

=back

=head1 SEE ALSO

C<OMP::CGIComponent::Project>, C<OMP::CGIComponent::Feedback>,
C<OMP::CGIComponent::MSB>

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
along with this program; if not, write to the
Free Software Foundation, Inc., 59 Temple Place, Suite 330,
Boston, MA  02111-1307  USA

=cut
