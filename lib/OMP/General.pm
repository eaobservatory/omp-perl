package OMP::General;

=head1 NAME

OMP::General - general purpose methods

=head1 SYNOPSIS

    use OMP::General;

    # To be saved with HTML markup.
    $insertstring = OMP::General->prepare_for_insert($string);

    # Provided project id is a partial string.
    $proj = OMP::General->infer_projectid(
        projectid => $input,
        telescope => 'ukirt',
        semester => $sem,
    );

    # Get array reference of file content.
    $lines = OMP::General->get_file_contents('file' => '/file/path');

=head1 DESCRIPTION

General purpose routines that are not associated with any particular
class but that are useful in more than one class.

=cut

use 5.006;
use strict;
use warnings;
use warnings::register;

# In some random cases with perl 5.6.1 (and possibly 5.6.0) we get
# errors such as:
#   Can't locate object method "SWASHNEW" via package "utf8"
#              (perhaps you forgot to load "utf8"?)
# Get round this by loading the utf8 module. Note that we solve the
# bug without contaminating our lexical namespace because the use
# line has the side effect of loading in the module that knows about
# the SWASHNEW method. Clearly crazy that the perl core can need this
# without loading it first. Fixed in perl 5.8.0. These are triggered
# because the XML parser and the web server provide UTF8 characters
# without loading associated handler code.
if ($] >= 5.006 && $] < 5.008) {
  eval "use utf8;";
}
use Carp;
use OMP::Constants qw/:logging/;
use OMP::Range;
use OMP::NetTools;
use OMP::DateTools;
use Term::ANSIColor qw/colored/;
use Time::Piece ':override';
use File::Spec;
use Fcntl qw/:flock SEEK_END/;
use OMP::Error qw/:try/;
use Text::Balanced qw/extract_delimited/;
use OMP::SiteQuality;
use POSIX qw/ /;

# Apr 13 2011 - The following comment needs to be verified ...
#   Note we have to require this module rather than use it because there is a
#   circular dependency with OMP::NetTools such that determine_host must be
#   defined before OMP::Config BEGIN block can trigger
require OMP::Config;
require OMP::UserServer;

our $VERSION = '2.000';

our $DEBUG = 0;

=head1 METHODS

There are no instance methods, only class (static) methods.

=head2 Projects

=over 4

=item B<infer_projectid>

Given a subset of a project ID attempt to determine the actual
project ID.

    $proj = OMP::General->infer_projectid(
        projectid => $input,
        telescope => 'jcmt');

    $proj = OMP::General->infer_projectid(
        projectid => $input,
        telescope => 'jcmt',
        semester => $sem);

    $proj = OMP::General->infer_projectid(
        projectid => $input,
        telescope => 'jcmt',
        date => $date);

If telescope is not supplied it is guessed.  If the project ID is a
number with a letter prefix it is assumed to be the JCMT style (ie u03
-> m01bu03). If the supplied ID is
ambiguous the telescope must be supplied or else
the routine will croak. JCMT service programs can be abbreviated with
the letter "s" and the country code ("su03" maps to s02bu03, valid
prefixes are "su", "si", and "sc". Dutch service programmes can not
be abbreviated). In general JCMT service programs do not really benefit
from abbreviations since in most cases the current semester is not
appropriate.

The semester is determined from a "semester" key directly or from a date.
The current date is used if no date or semester is supplied.
The supplied date must be a C<Time::Piece> object.

Finally, if the number is prefixed by more than one letter
(with the exception of s[uic] reserved for JCMT service) it is
assumed to indicate a special ID (usually reserved for support
scientists) that is not telescope specific (although be aware that
the Observing Tool can not mix telescopes in a single science
program even though the rest of the OMP could do it). The only
translation occuring in these cases is to pad the digit to two
characters.

If a project id consists entirely of alphabetic characters it
will be returned without modification.

=cut

sub infer_projectid {
    my $self = shift;
    my %args = @_;

    # The supplied ID
    my $projid = $args{projectid};
    croak "Must supply a project ID"
        unless defined $projid;

    # Make sure its not complete already (and extract substring at
    # same time)
    my $extracted = $self->extract_projectid($projid);
    return $extracted if defined $extracted;

    # If it's a special reserved ID (two characters + digit)
    # and *not* an abbreviated JCMT service programme
    # return it - padding the number)
    if ($projid !~ /^s[uic]\d\d/aai
            && $projid =~ /^([A-Za-z]{2,}?)(\d+)$/a) {
        return $1 . sprintf("%02d", $2);
    }

    # We need a guess at a telescope before we can guess a semester.
    # In most cases the supplied ID will be able to distinguish
    # JCMT (for example JCMT has a letter prefix such as "u03").
    # The exception is for UH where multiple telescopes may have
    # an "h" prefix.
    my $tel;
    if (exists $args{telescope}) {
        $tel = uc($args{telescope});
    }
    else {
        # Guess
        if ($projid =~ /^s?[juncidpltvkzf]\d+$/aai) {
            $tel = "JCMT";
        }
        else {
            croak "Unable to determine telescope from supplied project ID: $projid is ambiguous";
        }
    }

    # Now that we have a telescope we can find the semester
    my $sem;
    if (exists $args{semester}) {
        $sem = $args{semester};
    }
    elsif (exists $args{date}) {
        $sem = OMP::DateTools->determine_semester(
            date => $args{date},
            tel => $tel);
    }
    else {
        $sem = OMP::DateTools->determine_semester(tel => $tel);
    }

    # Now guess the actual projectid
    my $fullid;
    if ($tel eq "JCMT") {
        # Service mode changes the prefix
        my $prefix = ($projid =~ /^s/ ? 's' : 'm');

        # remove the s signifier
        $projid =~ s/^s//;

        $fullid = "$prefix$sem$projid";
    }
    else {
        croak "$tel is not a recognized telescope";
    }

    return $fullid;

}

=item B<extract_projectid>

Given a string (for example a full project id or possibly a subject
line of a mail message) attempt to extract a string that looks like
a OMP project ID.

    $projectid = OMP::General->extract_projectid($string);

Returns undef if nothing looking like a project ID could be located.
The match is done on word boundaries.

No attempt is made to verify that this project ID is actually
in the OMP system.

Note that this method has the side effect of untainting the
supplied variable.

=cut

sub extract_projectid {
    my $class = shift;
    my $string = shift;

    my $projid;

    if ($string =~ /\b([msre]\d\d[abxyzw][junchidpltvkzf]\d+([a-z]|fb)?)\b/aai  # JCMT [inc serv, FB and A/B suffix]
            or $string =~ /\b(m\d\d[ab]ec\d+)\b/aai          # JCMT E&C
            or $string =~ /\b(m\d\d[ab]gt\d+)\b/aai          # JCMT Guaranteed Time
            or $string =~ /\b(mjls[sgncdjty]\d+)\b/aai       # JCMT Legacy Surveys
            or $string =~ /\b(mjls[sgncdjty]\d\d[ab])\b/aai  # JCMT LS: semester-based
            or $string =~ /\b(m\d\d[ab]h\d+[a-z]\d?)\b/aai   # UH funny suffix JCMT
            or $string =~ /\b(nls\d+)\b/aai                  # JCMT Dutch service (deprecated format)
            or $string =~ /\b([LS]X_\d\d\w\w_\w\w)\b/aai     # SHADES proposal
            or $string =~ /\b([A-Za-z]+CAL(?:OLD)?)\b/aai    # Things like JCMTCAL
            or ($string =~ /\b([A-Za-z]{2,}\d{2,})\b/aai     # Staff projects TJ02
                && $string !~ /\bs[uinc]\d+\b/aai            # but not JCMT service abbrev
            )) {
        $projid = $1;
    }

    return $projid;
}

=item B<extract_faultid>

Given a string (for example a subject line of an email message)
attempt to extract a string that looks like an OMP fault ID.
The fault ID is assumed to be surrounded with square brackets
(as used in fault email subjects).

    $faultid = OMP::General->extract_faultid($string);

Returns undef if nothing looking like a fault ID could be located.

No attempt is made to verify that this fault ID is actually
in the OMP system.

Note that this method has the side effect of untainting the
supplied variable.

=cut

sub extract_faultid {
    my $class = shift;
    my $string = shift;

    # Regular expression based on that in OMP::CGIComponent::Fault::fault_table
    # for recognizing fault IDs.
    if ($string =~ /\[((?:199|2\d{2})\d[01]\d[0-3]\d\.\d{3})\]/a) {
        return $1;
    }

    return undef;
}

=back

=head2 Telescopes

=over 4

=item B<determine_tel>

Return the telescope name to use in the current environment.
This is usally obtained from the config system but if the config
system returns a choice of telescopes a Tk window will popup
requesting that the specific telescope be chosen.

If no Tk window reference is supplied, and multiple telescopes
are available, returns all the telescopes (either as a list
in list context or an array ref in scalar context). ie, if called
with a Tk widget, guarantees to return a single telescope, if called
without a Tk widget is identical to querying the config system directly.

    $tel = OMP::General->determine_tel($MW);

Returns undef if the user presses the "cancel" button when prompted
for a telescope selection.

If a Term::ReadLine object is provided, the routine will prompt for
a telescope if there is a choice. This has the same behaviour as for the
Tk option. Returns undef if the telescope was not valid after a prompt.

=cut

sub determine_tel {
    my $class = shift;
    my $w = shift;

    my $tel = OMP::Config->getData('defaulttel');

    my $telescope;
    if (ref($tel) eq "ARRAY") {
        unless (defined $w) {
            # Have no choice but to return the array
            if (wantarray) {
                return @$tel;
            }
            else {
                return $tel;
            }
        }
        elsif (UNIVERSAL::isa($w, "Term::ReadLine")
                || UNIVERSAL::isa($w, "Term::ReadLine::Perl")) {
            # Prompt for it
            my $res = $w->readline("Which telescope [" . join(",", @$tel) . "] : ");
            $res = uc($res);
            if (grep /^$res$/i, @$tel) {
                return $res;
            }
            else {
                # no match
                return ();
            }
        }
        else {
            # Can put up a widget
            require Tk::DialogBox;

            my $newtel;
            my $dbox = $w->DialogBox(
                -title => "Select telescope",
                -buttons => ["Accept", "Cancel"],
            );
            my $txt = $dbox->add(
                'Label',
                -text => "Select telescope for obslog",
            )->pack;

            foreach my $ttel (@$tel) {
                my $rad = $dbox->add(
                    'Radiobutton',
                    -text => $ttel,
                    -value => $ttel,
                    -variable => \$newtel,
                )->pack;
            }

            my $but = $dbox->Show;

            if ($but eq 'Accept' && $newtel ne '') {
                $telescope = uc($newtel);
            }
            else {
                # Pressed cancel
                return ();
            }
        }
    }
    else {
        $telescope = uc($tel);
    }

    return $telescope;
}

=back

=head2 Verification

=over 4

=item B<determine_user>

See if the user ID can be guessed from the system environment
without asking for it.

    $user = OMP::General->determine_user();

Uses the C<$USER> environment variable for the first guess. If that
is not available or is not verified as a valid user the method either
returns C<undef> or, if the optional widget object is supplied,
popups up a Tk dialog box requesting input from the user.

    $user = OMP::General->determine_user($MW);

If the userid supplied via the widget is still not valid, give
up and return undef.

Returns the user as an OMP::User object.

=cut

sub determine_user {
    my $class = shift;
    my $w = shift;

    my $user;
    if (exists $ENV{USER}) {
        $user = OMP::UserServer->getUser($ENV{USER});
    }

    unless ($user) {
        # no user so far so if we have a widget popup dialog
        if ($w) {
            require Tk::DialogBox;
            require Tk::LabEntry;

            while (! defined $user) {
                my $dbox = $w->DialogBox(
                    -title => "Request OMP user ID",
                    -buttons => ["Accept", "Don't Know"],
                );
                my $ent = $dbox->add(
                    'LabEntry',
                    -label => "Enter your OMP User ID:",
                    -width => 15
                )->pack;

                my $but = $dbox->Show;

                if ($but eq 'Accept') {
                    my $id = $ent->get;

                    # Catch any errors that might pop up.
                    try {
                        $user = OMP::UserServer->getUser($id);
                    }
                    catch OMP::Error with {
                        my $Error = shift;

                        my $dbox2 = $w->DialogBox(
                            -title => "Error",
                            -buttons => ["OK"],
                        );
                        my $label =
                            $dbox2->add('Label',
                            -text => "Error: " . $Error->{-text},
                        )->pack;

                        my $but2 = $dbox2->Show;
                    }
                    otherwise {
                        my $Error = shift;

                        my $dbox2 = $w->DialogBox(
                            -title => "Error",
                            -buttons => ["OK"],
                        );
                        my $label =
                            $dbox2->add('Label',
                            -text => "Error: " . $Error->{-text},
                        )->pack;

                        my $but2 = $dbox2->Show;
                    };
                    if (defined($user)) {
                        last;
                    }
                }
                else {
                    last;
                }
            }
        }
    }

    return $user;
}

=back

=head2 Logging

=over 4

=item B<log_level>

Control which log messages are written to the log file.

    $current = OMP::General->log_level();
    OMP::General->log_level(&OMP__LOG_DEBUG);
    OMP::General->log_level("DEBUG");

The constants are defined in OMP::Constants. Currently supported
logging levels are:

=over 4

=item IMPORTANT

Only important messages.

=item INFO

Informational and important messages.

=item DEBUG

Debugging, info and important messages.

=back

The level can be set using the above strings as well as the actual
constants, but constants will be returned if the level is requested.
If the new level is not recognized, the existing level will be retained.

Note that WARNING and ERROR log messages are always written to the log
and can not be disabled individually.

The default log level is INFO (ie no DEBUG messages) but can be over-ridden
by defining the environment OMP_LOG_LEVEL to one of "IMPORTANT", "INFO" or
"DEBUG"

=cut

{
    # Hide access to this variable
    my $LEVEL;

    # private routine to translate string to constant value
    # and then sort out the bit mask
    # return undef if not recognized
    # Note that the only system that calculates level from bits is this
    # internal function
    sub _str_or_const_to_level {
        my $arg = shift;
        my $bits = 0;

        # define some groups
        my $important = OMP__LOG_IMPORTANT;
        my $info = $important | OMP__LOG_INFO;
        my $debug = $info | OMP__LOG_DEBUG;
        my $err = OMP__LOG_ERROR | OMP__LOG_WARNING;

        if ($arg eq 'IMPORTANT' || $arg eq OMP__LOG_IMPORTANT) {
            $bits = $important;
        }
        elsif ($arg eq 'INFO' || $arg eq OMP__LOG_INFO) {
            $bits = $info;
        }
        elsif ($arg eq 'DEBUG' || $arg eq OMP__LOG_DEBUG) {
            $bits = $debug;
        }

        # Now set LEVEL to this value if we have $bits != 0
        # else no change to $LEVEL
        # if we allow 0 then nothing will be logged ever. We currently
        # do not have a OMP__LOG_NONE option
        if ($bits != 0) {
            # Include WARNING and ERROR in bitmask
            $bits |= $err;
            $LEVEL = $bits;
        }

        return;
    }

    # Accessor method
    sub log_level {
        my $class = shift;
        if (@_) {
            _str_or_const_to_level(shift);
        }

        # force default if required. This will only be called once
        unless (defined $LEVEL) {
            _str_or_const_to_level($ENV{'OMP_LOG_LEVEL'})
                if exists $ENV{'OMP_LOG_LEVEL'};

            _str_or_const_to_level(OMP__LOG_INFO)
                unless defined $LEVEL;
        }

        return $LEVEL;
    }

    # Returns true if the supplied message severity is consistent with
    # the current logging level.
    # undef indicates INFO
    # Keep this private for now
    sub _log_logok {
        my $class = shift;
        my $sev = shift;

        $sev = OMP__LOG_INFO unless defined $sev;

        return ($class->log_level & $sev);
    }

    # Translate supplied constant back to a descriptive string
    # we assume that multiple logging levels are not specified
    # keep internal for the moment since we only need it for the
    # log output
    sub _log_level_string {
        my $class = shift;
        my $sev = shift;

        $sev = OMP__LOG_INFO unless defined $sev;

        return colored("ERROR:    ", 'red') if $sev & OMP__LOG_ERROR;
        return colored("WARNING:  ", 'yellow') if $sev & OMP__LOG_WARNING;
        return colored("IMPORTANT:", 'green') if $sev & OMP__LOG_IMPORTANT;
        return colored("INFO:     ", 'cyan') if $sev & OMP__LOG_INFO;
        return colored("DEBUG:    ", 'magenta') if $sev & OMP__LOG_DEBUG;
    }
}

=item B<log_message>

Log general information to a file. Each message can be associated with
a particular importance or severity such that a particular log message
will only be written to the log file if that particular level of
logging is enabled (which can be set via the C<log_level>
method). WARNING and ERROR log messages will always be written.

By default, all messages are treated as "INFO" messages if no log
level is specified.

    OMP::General->log_message($message);

If a second argument is provided, it specifies the log
severity/importance level. Constants are available from
C<OMP::Constants>.

    OMP::General->log_message($message, OMP__LOG_DEBUG);

The currently defined set are:

=over 4

=item ERROR

An error message.

=item WARNING

A warning message.

=item IMPORTANT

Important log message (always written).

=item INFO

General information.

=item DEBUG

Verbose logging.

=back

The log file is opened for append (with a lock), the message is written
and the file is closed. The message is augmented with details of the
hostname, the process ID and the date.

Fails silently if the file can not be opened (rather than cause the whole
system to stop because it is not being written).

Uses the config C<logdir> entry to determine the required logging
directory but will fall back to C</tmp/ompLogs> if the required
directory can not be written to. A new file is created for each UT day.
The directory is created if it does not exist.

Returns immediately if the environment variable C<$OMP_NOLOG> is set,
even if the message has been tagged ERROR [maybe it should always send
error messages to STDERR if the process is attached to a terminal?].

=cut

sub log_message {
    my $class = shift;
    my $message = shift;
    my $severity = shift;

    return if exists $ENV{'OMP_NOLOG'};

    # Check the logging level.
    return unless $class->_log_logok($severity);

    # Get the current date
    my $datestamp = gmtime;

    # "Constants"
    my $logdir;

    # Look for the logdir but make sure this is none fatal
    # so for any error ignore it. in some cases a bare eval{}
    # here did not catch everyhing so use a try with empty otherwise
    try {
        # Make sure a date is available to the config system
        $logdir = OMP::Config->getData("logdir", utdate => $datestamp);
    }
    otherwise {
        # empty - we want to catch everything
    };
    my $fallback_logdir = File::Spec->catdir(File::Spec->tmpdir, "ompLogs");
    my $today = $datestamp->strftime("%Y%m%d");

    # The filename depends on whether the logdir includes the ut date
    my $file1 = "omp.log";
    my $file2 = "omp_$today.log";

    # Create the message
    my (undef, undef, $email) = OMP::NetTools->determine_host;

    my $sevstr = $class->_log_level_string($severity);

    # Create the log message without a prefix
    my $logmsg = colored("$datestamp", 'blue underline')
        . " PID: " . colored("$$", "green underline")
        . " User: " . colored("$email", "green underline")
        . "\nMsg: $message\n";

    # Split on newline, attached prefix, and then join on new line
    my @lines = split(/\n/, $logmsg);
    $logmsg = join("\n", map {$sevstr . $_} @lines) . "\n";

    # Get current umask
    my $umask = umask;

    # Set umask to 0 so that we can remove all protections
    umask 0;

    # Try both the logdir and the back up
    for my $thisdir ($logdir, $fallback_logdir) {
        next unless defined $thisdir;

        my $filename = ($thisdir =~ /$today/ ? $file1 : $file2);

        my $path = File::Spec->catfile($thisdir, $filename);

        # First check the directory and create it if it isnt here
        # Loop around if we can not open it
        unless (-d $thisdir) {
            mkdir $thisdir, 0777
                or next;
        }

        # Open the file for append
        # Creating the file if it is not there already
        open my $fh, '>>', $path
            or next;

        # Attempt to get a lock in a reasonable amount of time.
        # (Currently we try for 5 seconds.)
        do {
            # Try to get an exclusive lock (non-blocking).
            my $lock_mode = LOCK_EX | LOCK_NB;
            my $locked = flock($fh, $lock_mode);

            # If we didn't get the lock, try 5 more times after
            # 1 second delays.
            for (my $i = 0; ((not $locked) and ($i < 5)); $i ++) {
                sleep 1;
                $locked = flock($fh, $lock_mode);
            }

            # If we still don't have the lock, give up on this log file
            # and try the next.
            unless ($locked) {
                close $fh;
                next;
            }
        };

        # Seek in case the file was appended while we were
        # waiting (see perlfunc flock "mailbox appender" example).
        seek $fh, 0, SEEK_END;

        # write out the message
        print $fh $logmsg;

        # Explicitly close the file (dont check return value since
        # we will just return anyway)
        close $fh;

        # If we got to the end we jump out the loop
        last;
    }

    # Reset umask
    umask $umask;

    return;
}

=back

=head2 File

=over 4

=item B<get_file_contents>

Returns the file contents (lines) as array reference.  Throws
L<OMP::Error::FatalError> if file cannot be  or closed.  Takes in a
hash with keys of ...

=over 4

=item I<file>

File path to open.

=item I<filter>

Optional regular expression to keep only the matching lines.

=item I<start-whitespace>

Optional true value to keep whitespaces at the start of line (default
is to remove).

=item I<end-whitespace>

Optional true value to keep whitespaces at the end of line (default is
to remove).

=back

Get all the lines with whitespace removed from both ends of file called
F</file/path> ...

    $lines = OMP::General->get_file_contents(
        'file' => '/file/path');

Get the lines matching "is" anywhere in the line, with whitespace at
the line beginning intact ....

    $filtered = OMP::General->get_file_contents(
        'file' => '/file/path',
        'filter' => qr/is/i,
        'start-whitespace' => 1);

=cut

sub get_file_contents {
    my ($self, %arg) = @_;

    open my $fh, '<', $arg{'file'}
        or throw OMP::Error::FatalError
        "Cannot open file \"$arg{'file'}\" to read: $!\n";

    my @lines;
    while (my $line = <$fh>) {
        next if $arg{'filter'} && $line !~ $arg{'filter'};
        push @lines, $line;
    }

    close $fh
        or throw OMP::Error::FatalError
        "Cannot close file \"$arg{'file'}\" after reading: $!\n";

    # Loop only if requested to keep whitespace on at least one end.
    unless ($arg{'start-whitespace'} && $arg{'end-whitespace'}) {
        for (@lines) {
            s/^\s+// unless $arg{'start-whitespace'};
            s/\s+$// unless $arg{'end-whitespace'};
        }
    }

    return \@lines;
}

=item B<get_directory_contents>

Returns non-recursive directory listing as array reference.  Current
and parent directories are skipped; every file path is prefixed with
the given directory path.

Throws L<OMP::Error::FatalError> if directory cannot be  or closed.
Takes in a hash with keys of ...

=over 4

=item I<dir>

Directory path to list.

=item I<filter>

Optional regular expression to keep only the matching names.

=item I<sort>

Optional truth value to sort alphabetiscally.

=back

Get an unsorted, unfiletered list as array reference ...

    $files = OMP::General->get_directory_contents(
        'dir' => '/dir/path');

Get the sorted list of files matching regular expression "te?mp"
anywhere in the its name ...

    $filtered = OMP::General->get_directory_contents(
        'dir' => '/dir/path',
        'filter' => qr/te?mp/,
        'sort' => 1);

For other filter options, please refer to L<find(1)>, L<File::Find>,
L<File::Find::Rule>.

=cut

sub get_directory_contents {

    my ($self, %arg) = @_;

    my $dh;
    opendir $dh, $arg{'dir'}
        or throw OMP::Error::FatalError
        "Could not open directory \"$arg{'dir'}\": $!\n";

    my @file;
    my ($cur, $up) = map {File::Spec->$_} qw/curdir updir/;

    while (my $f = readdir $dh) {
        next if $f eq $cur or $f eq $up;

        next if $arg{'filter'} && $f !~ $arg{'filter'};

        push @file, File::Spec->catfile($arg{'dir'}, $f);
    }

    closedir $dh
        or throw OMP::Error::FatalError
        "Could not close directory \"$arg{'dir'}\": $!\n";

    return $arg{'sort'}
        ? [sort {$a cmp $b || $a <=> $b} @file]
        : \@file;
}

=back

=head2 String manipulation

=over 4

=item B<split_string>

Split a string that uses a whitespace as a delimiter into a series of
substrings. Substrings that are surrounded by double-quotes will be
separated out using the double-quotes as the delimiters.

    $string = 'foo "baz xyz" bar';
    @substrings = OMP::General->split_string($string);

Returns an array of substrings.

=cut

sub split_string {
    my $self = shift;
    my $string = shift;

    my @substrings;

    # Loop over the string extracting out the double-quoted substrings
    while ($string =~ /\".*?\"/s) {
        my $savestring = '';
        if ($string !~ /^\"/) {
            # Modify the string so that it begins with a quoted string and
            # store the portion of the string preceding the quoted string
            my $index = index($string, '"');
            $savestring .= substr($string, 0, $index);
            $string = substr($string, $index);
        }

        # Extract out the quoted string
        my ($extracted, $remainder) = extract_delimited($string, '"');
        $extracted =~ s/^\"(.*?)\"$/$1/;  # Get rid of the begin and end quotes
        push @substrings, $extracted;
        $string = $savestring . $remainder;
    }

    # Now split the string apart on white space
    push @substrings, split(/\s+/, $string);

    return @substrings;
}

=item B<nint>

Return the nearest integer to a supplied floating point
value. 0.5 is rounded up.

    $nint = OMP::General::nint($in);

=cut

sub nint {
    my $value = shift;

    if ($value >= 0) {
        return (int($value + 0.5));
    }
    else {
        return (int($value - 0.5));
    }
}

=item B<nearest_mult>

Return the nearest multiple.

    my $quant = OMP::General::nearest_mult(129, 64);  # 128

=cut

sub nearest_mult {
    my $value = shift;
    my $mult = shift;

    return nint($value / $mult) * $mult;
}

=item B<rot13>

Given a list of strings, returns list of ROT-13 obfuscated strings.

    # 'cbyxn qbg' is retuned.
    @rot = OMP::General->rot13('polka dot');

=cut

sub rot13 {
    my ($self, @in) = @_;

    for (@in) {
        defined $_
            and tr/A-Za-z/N-ZA-Mn-za-m/;
    }

    return @in;
}

=back

=head2 References

=over 4

=item B<hashref_keys_size>

Returns the number of keys in a given hash reference; returns nothing
if the reference is undefined or is not actually a reference.

    print "given hash ref is undef, empty, or not a reference at all"
        unless OMP::General->hashref_keys_size($some_hash_ref);

=cut

sub hashref_keys_size {
    my ($self, $r) = @_;
    return unless defined $r and ref $r;
    return scalar keys %{$r};
}

1;

__END__

=back

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>,
Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>,
Anubhav AgarwalE<lt>a.agarwal@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2007 Science and Technology Facilities Council.
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
