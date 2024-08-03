package OMP::CGIPage;

=head1 NAME

OMP::CGIPage - Generate complete dynamic OMP web pages

=head1 SYNOPSIS

    use CGI;

    use OMP::CGIPage;

    $query = new CGI;

    $cgi = OMP::CGIPage->new(CGI => $query);

    $cgi->write_page(\&view_method, $auth_type, %opts);

=head1 DESCRIPTION

This class generates the content of the OMP feedback system CGI scripts by
piecing together code from different places.

=cut

use 5.006;
use strict;
use warnings;
use CGI::Carp qw/fatalsToBrowser/;
use JSON;
use Time::Piece;
use Time::Seconds qw/ONE_DAY/;
use Template;
use Template::Context;
use Template::Stash;
use Text::Wrap;

BEGIN {
    use Encode;
    die 'Encode module is too old (untaints data)' if $Encode::VERSION < '2.50';
}

use OMP::Auth;
use OMP::Config;
use OMP::DB::Backend;
use OMP::DB::Backend::Archive;
use OMP::Display;
use OMP::DB::Project;
use OMP::Error qw/:try/;
use OMP::Fault;
use OMP::DB::Fault;
use OMP::Util::File;
use OMP::General;
use OMP::NetTools;
use OMP::Password;

our $VERSION = '2.000';

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

Create a new instance of an C<OMP::CGIPage> object.

    $cgi = OMP::CGIPage->new(CGI => $q);

=cut

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;

    # Read the arguments
    my %args;
    %args = @_ if @_;

    my $c = {
        CGI => undef,
        Title => 'OMP System',
        Auth => undef,
        SideBar => [],
        DB => undef,
        DBArchive => undef,
        DBHedwig2OMP => undef,
        FileUtil => undef,
    };

    # create the object (else we cant use accessor methods)
    my $object = bless $c, $class;

    # Populate object
    for my $key (keys %args) {
        my $method = lc($key);
        $object->$method($args{$key});
    }

    return $object;
}

=back

=head2 Accessor Methods

=over 4

=item B<cgi>

Return the CGI object of class C<CGI>.

    $q = $cgi->cgi;
    $cgi->cgi($q);

The argument must be in class C<CGI>.

=cut

sub cgi {
    my $self = shift;
    if (@_) {
        my $cgi = shift;

        croak "Incorrect type. Must be a CGI object"
            unless UNIVERSAL::isa($cgi, "CGI");

        $self->{CGI} = $cgi;
    }
    return $self->{CGI};
}

=item B<html_title>

Return the string to be used for the HTML title.

    $title = $c->html_title;
    $c->html_title($title);

Default value is "OMP Feedback System".

=cut

sub html_title {
    my $self = shift;
    if (@_) {
        $self->{Title} = shift;
    }
    return $self->{Title};
}

=item B<auth>

The authentication object, if a user is logged in.

    $auth = $cgi->auth();
    $cgi->auth($auth);

=cut

sub auth {
    my $self = shift;
    if (@_) {
        my $auth = shift;

        throw OMP::Error::BadArgs('OMP::CGIPage->auth must be an OMP::Auth')
            unless UNIVERSAL::isa($auth, 'OMP::Auth');

        $self->{Auth} = $auth;
    }
    return $self->{Auth};
}

=item B<database>

A database backend object.

    $db = $page->database;

This will be an C<OMP::DB::Backend> instance, constructed the first
time this method is called.

=cut

sub database {
    my $self = shift;

    unless (defined $self->{'DB'}) {
        $self->{'DB'} = OMP::DB::Backend->new();
    }

    return $self->{'DB'};
}

=item B<database_archive>

A database backend object for the archive.

    $db = $page->database_archive;

This will be an C<OMP::DB::Backend::Archive> instance, constructed the first
time this method is called.

=cut

sub database_archive {
    my $self = shift;

    unless (defined $self->{'DBArchive'}) {
        $self->{'DBArchive'} = OMP::DB::Backend::Archive->new();
    }

    return $self->{'DBArchive'};
}

=item B<fileutil>

File utility object.

    $util = $page->fileutil;

This will be an C<OMP::Util::File> instance, constructed the first
time this method is called.

=cut

sub fileutil {
    my $self = shift;

    unless (defined $self->{'FileUtil'}) {
        $self->{'FileUtil'} = OMP::Util::File->new();
    }

    return $self->{'FileUtil'};
}

=item B<side_bar>

Add a section to the side bar:

    $cgi->side_bar($title, \@entries, %opts);

Where each value of C<@entries> is a list giving the
name of the link, the URL, and optionally any extra information
to show after it:

    @entries[0] = [$name, $url, [$extra_info]];

Or retrieve a reference to the side bar sections array:

    my $side_bar = $cgi->side_bar();

=cut

sub side_bar {
    my $self = shift;
    if (@_) {
        my ($title, $entries, %opts) = @_;
        push @{$self->{'SideBar'}}, {
            title => $title,
            entries => $entries,
            options => \%opts,
        };
    }
    return $self->{'SideBar'};
}

=back

=head2 General Methods

=over 4

=item B<write_page>

Create the page with the login form if login details are needed.  Once login
details are acquired, call the code reference or method provided to this
method.

    $cgi->write_page(\&view_method, $auth_type, %opts);

First argument is the name of the C<OMP::CGIPage> method (or a code reference) to
be called for displaying the page.

Options for C<auth_type> are:

=over 4

=item no_auth

The login verification process is skipped

=item staff

Require staff log-in.

=item project

Require membership of the project specified by the "project" query parameter,
or staff log-in.

=back

These options can be prefixed as follows (in this order):

=over 4

=item local_or_

Allow access from a local machine.

=item staff_or_

Allow access with staff log-in, even if futher authorization information
is not provided (e.g. the project ID for "project" C<auth_type>).

=back

Additional options are:

=over 4

=item template

If a template is provided, and if the view method returns something
other than C<undef>, then it should be a hash reference which will be
passed to the template as context information.

Otherwise it is assumed that the view method will have written any
desired output, including the HTTP header.

=item title

Page title.

=item javascript

Array reference of names of additional JavaScript files to include.

=back

The given method will be called with the validated project ID as the
first argument (after C<$self>) if project access is required.

The subroutine passed to this method should shift off the first argument.

    sub view_method {
        my $self = shift;
        ...
    }

=cut

sub write_page {
    my $self = shift;
    my $view_method = shift;
    my $auth_type = shift;
    my %opt = @_;

    my $q = $self->cgi;

    # Check to see that it is defined...
    # Check that it is a code ref
    throw OMP::Error::BadArgs("Code reference or method name not given")
        unless defined $view_method;

    my $type = ref $view_method;
    croak "Must be a code reference or method name."
        unless ($type eq 'CODE' or $self->can($view_method));

    croak 'No auth_type specified' unless defined $auth_type;

    my $template = (exists $opt{'template'}) ? $opt{'template'} : undef;

    if (defined $opt{'title'}) {
        $self->html_title($opt{'title'});
    }

    $self->auth(my $auth = OMP::Auth->log_in($self));

    return if $auth->abort();

    my $auth_ok = 0;

    if ($auth_type =~ '^local_or_(\w+)$') {
        $auth_type = $1;
        $auth_ok = 1 if $self->is_host_local();
    }

    if ($auth_type =~ '^staff_or_(\w+)$') {
        $auth_type = $1;
        $auth_ok = 1 if $auth->is_staff();
    }

    my @args = ();
    unless ($auth_type eq 'no_auth') {
        # Check to see if any login information has been provided. If not then
        # put up a login page.
        return $self->_write_login()
            unless ($auth_ok or defined $auth->user());

        if ($auth_type eq 'staff') {
            return $self->_write_forbidden()
                unless ($auth_ok or $auth->is_staff());
        }
        elsif ($auth_type eq 'project') {
            # Require project access.

            my $projectid = OMP::General->extract_projectid(
                $self->decoded_url_param('project'));

            unless (defined $projectid) {
                return $self->_write_project_choice()
                    unless $auth_ok;
            }
            else {
                # Ensure project ID is upper case before attempting authorization.
                $projectid = uc $projectid;
            }

            return $self->_write_forbidden()
                unless $auth_ok
                or $auth->is_staff
                or $auth->has_project($self->database, $projectid);

            push @args, $projectid;

            $self->_sidebar_project($projectid);

            $self->html_title($projectid . ': ' . $self->html_title());
        }
        else {
            croak 'Unrecognized auth_type value';
        }
    }

    my $extra = $self->_write_page_extra();
    throw OMP::Error::BadArgs("hashref not returned by _write_page_extra")
        unless 'HASH' eq ref $extra;

    return if (exists $extra->{'abort'} and $extra->{'abort'});

    push @args, @{$extra->{'args'}} if exists $extra->{'args'};

    my $result = $self->_call_method($view_method, @args);

    if ((defined $template) and (defined $result)) {
        $self->_write_http_header(undef, \%opt);

        $self->render_template(
            $template, {
                %{$self->_write_page_context_extra(\%opt)},
                %$result,
            });
    }

    return;
}

sub _write_page_context_extra {
    my $self = shift;
    my $opt = shift;

    my $jscript_url = [];
    if (exists $opt->{'javascript'}) {
        push @$jscript_url,
            OMP::Config->getData('www-js'),
            map {'/' . $_} @{$opt->{'javascript'}};
    }

    return {
        omp_title => $self->html_title,
        omp_style => [OMP::Config->getData('www-css')],
        omp_favicon => OMP::Config->getData('www-favicon'),
        omp_theme_color => OMP::Config->getData('www-theme-color'),
        omp_javascript => $jscript_url,
        omp_user => $self->auth->user,
        omp_side_bar => $self->side_bar,
    };
}

=item B<_write_page_extra>

Method to prepare extra information for the L<write_page> system.  Subclasses
should override this method to perform any additional steps required.  A
reference to a hash must be returned.  This may contain:

=over 4

=item abort

Stop processing if true.  This can be used, for example, if some kind of
selection page has been shown.

=item args

Reference to an array of additional arguments to pass to the handler methods.

=back

=cut

sub _write_page_extra {
    my $self = shift;
    return {};
}

=item B<write_page_finish_log_in>

Complete a 2-step log in process.

    $page->write_page_finish_log_in(%auth_options);

The given options are passed to C<OMP::Auth-E<gt>log_in>.  It should either
return an object with C<abort> or C<message> set.

Note that this method invokes C<_write_error> rather than showing the log in
page again with C<_write_login>.  This is because we may have ended up with
the wrong set of query parameters.

=cut

sub write_page_finish_log_in {
    my $self = shift;

    my $q = $self->cgi;

    $self->auth(my $auth = OMP::Auth->log_in($self, @_));

    return if $auth->abort();

    if (defined $self->auth->message) {
        return $self->_write_error($self->auth->message);
    }

    return $self->_write_error('No log in process in progress.');
}

=item B<write_page_logout>

Creates a logout page and gives a cookie that has already expired.

    $cgi->write_page_logout(\&content, %opt);

=cut

sub write_page_logout {
    my $self = shift;
    my $content = shift;
    my %opt = @_;

    $self->auth(OMP::Auth->log_out($self));

    $self->html_title($opt{'title'});

    my $result = $self->_call_method($content);

    $self->_write_http_header(undef, \%opt);

    $self->render_template(
        $opt{'template'}, {
            %{$self->_write_page_context_extra(\%opt)},
            %$result,
        });
}

=item B<render_template>

Renders a Template::Toolkit template from the "templ" directory (as specified
by the www-templ configuration parameter.)

    $cgi->render_template($name, \%context);

=cut

sub render_template {
    my $self = shift;
    my $name = shift;
    my $context = shift;

    # Allow access to "private" attributes, e.g.
    # the _ORDER parameter from OMP::Info::Obs::nightlog.
    local $Template::Stash::PRIVATE = undef;

    local $Text::Wrap::huge = 'overflow';

    my $templatecontext = Template::Context->new({
        INCLUDE_PATH => scalar OMP::Config->getData('www-templ'),
        VARIABLES => {
            'create_counter' => sub {
                OMP::CGIPage::Counter->new(@_);
            },
        },
    });

    # Methods "date_prev" and "date_next" apply
    # to Time::Piece objects -- these are blessed arrays.
    $templatecontext->define_vmethod('array', 'date_prev', sub {
        my $utdate = shift;
        return scalar gmtime($utdate->epoch() - ONE_DAY());
    });

    $templatecontext->define_vmethod('array', 'date_next', sub {
        my $utdate = shift;
        return scalar gmtime($utdate->epoch() + ONE_DAY());
    });

    $templatecontext->define_vmethod('hash', 'json', sub {
        return encode_json($_[0]);
    });

    # Method to format as HTML text from any object with 'text' and 'preformatted'
    # attributes. (Unfortunately can't use a filter as that would stringify first.)
    # Wraps to the requested width, and if not preformatted, wraps in <pre> tags.
    $templatecontext->define_vmethod('hash', 'format_text', sub {
        my $object = shift;
        my $width = shift;
        return OMP::Display->format_html(
            $object->text, $object->preformatted,
            width => $width);
    });

    # Method to format as HTML text not enclosed in <pre> tags.  I.e. instead
    # of line wrapping, replace newlines with <br /> tags.
    $templatecontext->define_vmethod('hash', 'remove_pre_tags', sub {
        my $object = shift;
        if ($object->preformatted) {
            my $text = $object->text;
            $text =~ s/^\s*<PRE>//i;
            $text =~ s/<\/PRE>\s*$//i;
            return $text;
        }
        return OMP::Display->format_html_inline($object->text, 0);
    });

    $templatecontext->define_filter('abbr_html', sub {
        my ($context, $width) = @_;
        return sub {
            my $text = shift;
            return OMP::Display::escape_entity($text) if $width >= length $text;
            return '<abbr title="' . OMP::Display::escape_entity($text) . '">'
                . OMP::Display::escape_entity(substr $text, 0, $width)
                . '&hellip;</abbr>';
        };
    }, 1);

    my $template = Template->new({
        CONTEXT => $templatecontext,
        ENCODING => 'utf8',
    }) or die "Could not configure template object: $Template::ERROR";

    binmode STDOUT, ':utf8';
    $template->process($name, $context) or die $template->error();
}

=item B<decoded_url_param>

Get URL parameter from the CGI object (using its C<url_param> method)
and ensure it has been decoded.

    $value = $page->decoded_url_param('parameter');

Note: the CGI module's C<utf8> pragma enables decoding of parameters
when fetched via the C<param> method, but currently not when fetched
via C<url_param>.  This method does the same thing to results from
C<url_param>.

=cut

sub decoded_url_param {
    my $self = shift;
    my $param = shift;

    my $value = $self->cgi->url_param($param);

    $value = Encode::decode('UTF-8', $value) unless Encode::is_utf8($value);

    return $value;
}

=item B<url_absolute>

Get an "absolute" URL (without host) including only query parameters.

    my $url = $page->url_absolute([%extra_query_parameters]);

Note: the URL should already be escaped (by CGI-E<gt>url) so it should not
be further escaped, e.g. by the template 'url' filter.

=cut

sub url_absolute {
    my $self = shift;
    my %extra_params = @_;

    my $q = $self->cgi;

    return $q->new({
        (map {
            my $value = $q->url_param($_);
            $value = Encode::decode('UTF-8', $value)
                unless Encode::is_utf8($value);
            $_ => $value
        } $q->url_param()),
        %extra_params,
    })->url(-absolute => 1, -query => 1);
}

=back

=head2 Internal Methods

=over 4

=item B<_call_method>

Given a method name or code reference, call the method or code reference.

    $cgi->($method_name, @args);

=cut

sub _call_method {
    my $self = shift;
    my $method = shift;

    if (ref($method) eq 'CODE') {
        # It's a code reference; call it with self as the object.
        return $method->($self, @_);
    }
    else {
        # It's a method name, run it on self.
        return $self->$method(@_);
    }
}

=item B<_sidebar_project>

Set up a project sidebar.

  $page->_sidebar_project($projectid);

=cut

sub _sidebar_project {
    my $self = shift;
    my $projectid = shift;

    # If there are any faults associated with this project put a link up to the
    # fault system and display the number of faults.
    my $faultdb = OMP::DB::Fault->new(DB => $self->database);
    my @faults = $faultdb->getAssociations($projectid, 1);

    $self->side_bar("Project $projectid", [
        ['Project home' => "/cgi-bin/projecthome.pl?project=$projectid"],
        ['Contacts' => "/cgi-bin/projusers.pl?project=$projectid"],
        ['Feedback entries' => "/cgi-bin/feedback.pl?project=$projectid"],
        ['Add comment' => "/cgi-bin/fbcomment.pl?project=$projectid"],
        ['Active MSBs' => "/cgi-bin/fbmsb.pl?project=$projectid"],
        ['MSB history' => "/cgi-bin/msbhist.pl?project=$projectid"],
        ['Program regions' => "/cgi-bin/spregion.pl?project=$projectid"],
        ['Program summary' => "/cgi-bin/spsummary.pl?project=$projectid"],
        (@faults ? ['Faults', "/cgi-bin/fbfault.pl?project=$projectid", '(' . scalar(@faults) . ')'] : ()),
    ]);

    $self->side_bar("Project administration", [
        ['Edit project' => "/cgi-bin/alterproj.pl?project=$projectid"],
        ['Edit support ' => "/cgi-bin/edit_support.pl?project=$projectid"],
        ['Target observability' => "/cgi-bin/sourceplot.pl?project=$projectid"],
    ], project_id_panel => 1) if $self->auth->is_staff;
}

=item B<_sidebar_night>

Set up a side bar for staff-access night-based pages.

    $page->_sidebar_night($telescope, $utdate);

=cut

sub _sidebar_night {
    my $self = shift;
    my $telescope = shift;
    my $utdate = shift;

    return unless defined $telescope and defined $utdate;

    $telescope = uc $telescope;
    $utdate = $utdate->ymd if ref $utdate;

    $self->side_bar($utdate, [
        ['Observing report' => "/cgi-bin/nightrep.pl?tel=$telescope&utdate=$utdate"],
        ['Time accounting' => "/cgi-bin/timeacct.pl?telescope=$telescope&utdate=$utdate"],
        ['MSB summary' => "/cgi-bin/wwwobserved.pl?telescope=$telescope&utdate=$utdate"],
        ['Shift log' => "/cgi-bin/shiftlog.pl?telescope=$telescope&utdate=$utdate"],
        ['Schedule' => "/cgi-bin/sched.pl?tel=$telescope&utdate=$utdate#night_$utdate"],
        ['Faults' => "/cgi-bin/queryfault.pl?faultsearch=true&action=activity&period=arbitrary"
            . "&mindate=$utdate&maxdate=$utdate&timezone=UT&search=Search&cat=$telescope"],
        ['WORF' => "/cgi-bin/staffworfthumb.pl?telescope=$telescope&ut=$utdate"],
    ]);
}

=item B<_write_http_header>

Write the HTTP header, including cookie if present.

    $cgi->_write_http_header($status, \%opt);

=cut

sub _write_http_header {
    my $self = shift;
    my $status = shift;
    my $opt = shift;

    my $q = $self->cgi;
    my $cookie = $self->auth->cookie;

    my %header_opt = (
        -expires => '-1d',
        -charset => 'utf-8',
    );

    $header_opt{'-cookie'} = $cookie if defined $cookie;
    $header_opt{'-status'} = $status if defined $status;

    print $q->header(%header_opt);
}

=item B<_write_login>

Create a page with a login form.

    $cgi->_write_login();

=cut

sub _write_login {
    my $self = shift;
    my %opt = (javascript => ['log_in.js']);

    $self->_write_http_header(undef, \%opt);

    $self->render_template(
        'log_in.html', {
            %{$self->_write_page_context_extra(\%opt)},
            message => $self->auth->message,
            target => $self->url_absolute,
        });
}

=item B<_write_forbidden>

Create a page with "forbidden" error message.

    $cgi->_write_forbidden();

=cut

sub _write_forbidden {
    my $self = shift;
    my %opt = ();

    $self->_write_http_header('403 Forbidden', \%opt);

    $self->render_template(
        'error.html', {
            %{$self->_write_page_context_extra(\%opt)},
            error_title => 'Forbidden',
            error_messages => [
                'The system was unable to verify your access to this page.',
            ],
        });

    return undef;
}

=item B<_write_error>

Create an internal server error page.

    $page->_write_error('Message', ...);

Calls C<_write_error_page> with status 500.

=cut

sub _write_error {
    my $self = shift;

    return $self->_write_error_page(
        '500 Internal Server Error', 'Error', @_);
}

=item B<_write_error_page>

Create a page with an error message.

    $page->_write_error_page('Status description', $title, @messages);

This method includes a header and footer.

=cut

sub _write_error_page {
    my $self = shift;
    my $status = shift;
    my $title = shift;
    my %opt = ();

    $self->_write_http_header($status, \%opt);

    $self->render_template(
        'error.html', {
            %{$self->_write_page_context_extra(\%opt)},
            error_title => $title,
            error_messages => \@_,
        });

    return undef;
}

=item B<_write_not_found_page>

Create a not found page.

    $page->_write_not_found_page('Message', ...);

Calls C<_write_error_page> with status 404.

B<Note:> for resource-fetching scripts, the basic C<_write_not_found>
method may be preferable.

=cut

sub _write_not_found_page {
    my $self = shift;

    return $self->_write_error_page(
        '404 Not Found', 'Not Found', @_);
}

=item B<_write_not_found>

Create a basic not-found error response.

B<Note:> unlike the other error page methods, this does not
call C<_write_http_header>, so does not include cookies,
or render a full template.  As such it is more useful for
resource-fetching scripts.

=cut

sub _write_not_found {
    my $self = shift;

    my $q = $self->cgi;
    print $q->header(-status => '404 Not Found', -type => 'text/plain', -charset => 'utf-8');
    print '404 Not Found';

    return undef;
}

=item B<_write_redirect>

Create a redirect response.

    $page->_write_redirect($url);

=cut

sub _write_redirect {
    my $self = shift;
    my $url = shift;

    unless (OMP::Config->getData('www-meta-refresh')) {
        my $q = $self->cgi;

        print $q->redirect($url);
    }
    else {
        $self->_write_http_header(undef, {});

        print "<html><head><meta http-equiv=\"refresh\" content=\"2; url=$url\" /></head><body><p>Redirecting&hellip;</p><p><a href=\"$url\">$url</a></p></body></html>";
    }

    return undef;
}

=item B<_write_project_choice>

Create a page with a project choice form.

    $cgi->_write_project_choice();

=cut

sub _write_project_choice {
    my $self = shift;
    my %opt = ();
    my $q = $self->cgi;

    my $project_choices = undef;
    my %proj_opts = ();
    if (defined $self->auth->user) {
        my $projects = $self->auth->projects($self->database);
        if (@$projects) {
            $project_choices = [sort @$projects];
        }
    }

    $self->_write_http_header(undef, \%opt);
    $self->render_template(
        'project_choice.html', {
            %{$self->_write_page_context_extra(\%opt)},
            project_choices => $project_choices,
            target => $q->url(-absolute => 1),
        });
}

=item B<is_host_local>

Returns true if the host accessing this page is local, false
if not. The definition of "local" means that either there are
no dots in the domainname (eg "lapaki" or "ulu") or the domain
includes one of the endings specified in the "localdomain" config
setting.

    print "local" if $page->is_host_local

=cut

sub is_host_local {
    my $self = shift;

    my @domain = OMP::NetTools->determine_host();

    # if no domain, assume we are really local (since only a host name)
    return 1 unless $domain[1];

    # Also return true if the domain does not include a "."
    return 1 if $domain[1] !~ /\./;

    # Now get the local definition of allowed remote hosts
    my @local = OMP::Config->getData('localdomain');

    # See whether anything in @local matches $domain[1]
    if (grep {$domain[1] =~ /$_$/i} @local) {
        return 1;
    }
    else {
        return 0;
    }
}

=back

=cut

package OMP::CGIPage::Counter;

sub new {
    my $class = shift;
    my $value = shift // 0;

    my $self = {
        value => $value,
    };

    return bless $self, $class;
}

sub nextvalue {
    my $self = shift;
    return ++ $self->{'value'};
}

sub value {
    my $self = shift;
    return $self->{'value'};
}

1;

__END__

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>,
Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>

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
