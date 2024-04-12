#!/local/perl/bin/perl -X

=head1 NAME

obslog - Review and comment on observations and timegaps for observing runs

=head1 SYNOPSIS

    obslog
    obslog -disk
    obslog -ut 2002-12-10
    obslog -tel jcmt
    obslog -ut 2002-10-05 -tel ukirt
    obslog --help

=head1 DESCRIPTION

This program allows you to review and comment on observations and timegaps
for a night of observing. It allows for changing the status of an observation
(good, questionable, junk or bad) or the underlying reason for a timegap (unknown,
weather, or fault). It also supports multiple instruments via a tabbed window
interface.

=head1 OPTIONS

The following options are supported:

Note that if both I<-db> and I<-disk> are either set to true or false,
database will be searched for past data and files on disk for data for
current date.

=over 4

=item B<-db>

Specify to search for data B<only in the database>, repeatedly if
necessary. It is default.

=item B<-disk>

Specify to search for data B<only in files on disk>, repeatedly if
necessary.

=item B<-font> font-description

Specify the font for everything; default is
I<-*-Courier-Medium-R-Normal--*-120-*-*-*-*-*-*>.

Another font to try is C<{Dejavu LGC Sans Mono}:8:medium>. If you do, you may also
need to change the window size via I<-geometry> option.

=item B<-font-fixed> | B<-ff> font-description

Specify the fixed-width font; default is same as metioned in I<-font>
description.

It is used for observation listings, headers, and.

Another font to try is C<Dejavu LGC Sans Mono::medium>.

=item B<-font-var> | B<-fv>  font-description

Specify variable width font; default is same as metioned in I<-font>
description.

It is used for buttons, labels, and comments.

Another font to try is C<Dejavu LGC Sans::medium>.

=item B<-geometry> window-geometry

Specify window location and size of the main obslog window; default is
I<785x450>.

=item B<-tel>

Specify the telescope to use for the report. If the telescope can
be determined from the domain name it will be used automatically.
If the telescope can not be determined from the domain and this
option has not been specified a popup window will request the
telescope from the supplied list (assume the list contains more
than one telescope).

=item B<-ut>

Override the UT date used for the report. By default the current date
is used.  The UT can be specified in either YYYY-MM-DD or YYYYMMDD format.
If the supplied date is not parseable, the current date will be used.

=item B<-width> integer

Specify the number of characters in each line before line break.

=item B<-version>

Report the version number.

=item B<-help>

A help message.

=item B<-man>

This manual page.

=back

=cut

use warnings;
use strict;

use Tk;
use Tk::Toplevel;
use Tk::NoteBook;
use Tk::Radiobutton;
use Tk::Dialog;
use Tk::Font;
use Tk::Adjuster;

use Getopt::Long;
use Time::Piece qw/:override/;
use Pod::Usage;
use File::Spec;
use FindBin;

BEGIN {
    use constant OMPLIB => "$FindBin::RealBin/../lib";
    use lib OMPLIB;
}

use OMP::DB::Archive;
use OMP::Constants;
use OMP::Display;
use OMP::DateTools;
use OMP::NetTools;
use OMP::General;
use OMP::Config;
use OMP::Error qw/:try/;
use OMP::Util::Client;
use OMP::Util::File;

BEGIN {
    $ENV{'OMP_CFG_DIR'} = File::Spec->catdir(OMPLIB, '../cfg')
        unless exists $ENV{'OMP_CFG_DIR'};
}

use OMP::DB::Obslog;
use OMP::ObsQuery;
use OMP::MSB;
use OMP::DB::MSBDone;
use OMP::ArcQuery;
use OMP::ShiftDB;
use OMP::ShiftQuery;
use OMP::Info::Obs;
use OMP::Info::Comment;
use OMP::DB::Backend;
use OMP::DB::Backend::Archive;

our $VERSION = '2.000';


# global variables
$| = 1;
my $obslog;              # refers to the object that holds the obslog information
my %obs;                 # keys are instruments, values are ObsGroup objects
my %obs_ref;             # Quick lookup for observations.
my @shiftcomments;       # Shift log comments.
my %notebook_contents;   # All the notebook content windows
my %notebook_headers;    # All the notebook header windows
my $notebook;            # The widget that holds the tabbed windows.
my $shiftcommentText;    # The widget that holds shiftlog comments.
my $lastinst;            # The instrument of the most recent observation.
my $current_instrument;  # The instrument currently displayed.
my $verbose;             # Long or short output
my %msbtitles;           # md5 to title
$msbtitles{'CAL'} = 'Calibration';
my $id;


# Number of characters to display for observation summary before linewrapping.
my $BREAK = 98;

my %opt = (
    'geometry' => '785x450',

    # Fixed width font;
    'font-fixed' => '-*-Courier-Medium-R-Normal--*-120-*-*-*-*-*-*',
);

# variable width font.
$opt{'font-var'} = $opt{'font-fixed'};

my ($help, $man, $version);

# Look in database by default.
$opt{'database'} = 1;
my $status = GetOptions(
    "ut=s" => \$opt{ut},
    "tel=s" => \$opt{tel},

    "disk|file!" => \$opt{disk},
    "db|database!" => \$opt{database},

    'width=i' => \$BREAK,
    'geometry=s' => \$opt{'geometry'},

    'font-fixed|ff=s' => \$opt{'font-fixed'},
    'font-var|fv=s' => \$opt{'font-var'},
    'font=s' => \$opt{'font-all'},

    "help" => \$help,
    "man" => \$man,
    "version" => \$version,
) or pod2usage(1);

pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

if ($version) {
    print "obslog - Observation reporting tool\n";
    print "Version: ", $VERSION, "\n";
    exit;
}

# initialise
my $ut = OMP::DateTools->determine_utdate( $opt{ut} )->ymd;
my $currentut = OMP::DateTools->today;
my $utdisp = "Current UT date: $ut";

my $dbb = OMP::DB::Backend->new();
my $arcdb = OMP::DB::Archive->new(
    DB => OMP::DB::Backend::Archive->new(),
    FileUtil => OMP::Util::File->new(recent_files => 0));
$arcdb->use_existing_criteria(1);

my $user;

# Create a mainwindow that can be shared by everyone
# we have found that creating two MainWindow's sometimes leads
# to core dumps on some X servers
my $MainWindow = MainWindow->new();
$MainWindow->withdraw; # hide it

for my $fn (grep {/font-/ && defined $opt{$_}} keys %opt) {
    $opt{$fn} = font_parse($MainWindow, $opt{$fn});
}

if ($opt{'font-all'}) {
    $opt{'font-fixed'} = $opt{'font-var'} = $opt{'font-all'};
}

# Table data, looks best in monospace font.
my ($HEADERFONT, $LISTFONT) = ($opt{'font-fixed'}) x 2;

# Make bold font.
for my $fn (qw/font-fixed font-var/) {
    $opt{"$fn-bold"} = font_medium_to_bold_it($MainWindow, $opt{$fn});
}


my $telescope;
if (defined $opt{tel}) {
    $telescope = uc $opt{tel};
}
else {
    my $w = $MainWindow->Toplevel;
    $w->withdraw;
    $telescope = OMP::Util::Client->determine_tel($w);
    $w->destroy if Exists($w);
    die "Unable to determine telescope. Exiting.\n"
        unless defined $telescope;
}

# CONTENTCOLOUR controls the colour of the text comments and entries
# for an observation. It assumes that OBS comments status is an integer
# starting at 0 (Good)
my $HEADERCOLOUR = 'midnightblue';
#                      good    questionable   bad     rejected     junk
my @CONTENTCOLOUR = ('#000000', '#ff7e00', '#ff3333', '#0000ff', '#ff00ff');
my $HIGHLIGHTBACKGROUND = '#CCCCFF';
my $BACKGROUND1 = '#D3D3D3';
my $BACKGROUND2 = '#DDDDDD';
my $BACKGROUNDMSB = '#CCFFCC';
my $FOREGROUNDMSB = '#000000';
my $SCANFREQ = 300000;  # scan every five minutes

$user = get_userid();

create_main_window();

full_rescan($ut, $telescope);

MainLoop();

sub get_userid {
    my $w = $MainWindow->Toplevel;
    $w->withdraw;
    my $user = OMP::Util::Client->determine_user($dbb, $w);
    throw OMP::Error::Authentication('Unable to obtain valid user name')
        unless defined $user;
    $w->destroy if Exists($w);
    return $user;
}

sub create_main_window {
    $MainWindow->title('OMP Observation Log Tool');
    $MainWindow->geometry($opt{'geometry'});

    # $mainFrame contains the entire frame.
    my $mainFrame = $MainWindow->Frame;

    # $buttonbarFrame contains buttons that do various tasks
    my $buttonbarFrame = $mainFrame->Frame(
        -relief => 'groove',
        -borderwidth => 2,
    );

    # $buttonRescan is the button that rescans for new observations and comments.
    my $buttonRescan = $buttonbarFrame->Button(
        -text => 'Rescan',
        -command => sub {
            full_rescan($ut, $telescope);
        },
        -font => $opt{'font-var'},
    );

    # $buttonDumpText is the button that dumps the current listing to disk.
    my $buttonDumpText = $buttonbarFrame->Button(
        -text => 'Dump Text',
        -command => sub {
            dump_to_disk();
        },
        -font => $opt{'font-var'},
    );

    # $buttonVerbose is the button that switches between short and long display.
    my $buttonVerbose = $buttonbarFrame->Checkbutton(
        -text => 'Short/Long Display',
        -variable => \$verbose,
        -command => sub {
            redraw(undef, $current_instrument, $verbose);
        },
        -font => $opt{'font-var'},
    );

    # $labelUT is a label that tells the UT date
    my $labelUT = $buttonbarFrame->Label(
        -textvariable => \$utdisp,
        -font => $opt{'font-var-bold'},
    );

    # $buttonHelp is the button that brings up a help dialogue.
    #  my $buttonHelp = $buttonbarFrame->Button(
    #      -text => 'Help',
    #      -command => \&help,
    #  );

    # $notebook holds the pages for content
    my $nbFrame = $mainFrame->Frame();
    $notebook = $nbFrame->NoteBook();

    my $adjuster = $mainFrame->Adjuster();

    # Shift log frame
    my $shiftFrame = $mainFrame->Frame();
    create_shiftlog_widget($shiftFrame);

    my $optionsFrame = $mainFrame->Frame();
    create_options_widget($optionsFrame);

    $mainFrame->pack(
        -side => 'top',
        -fill => 'both',
        -expand => 1
    );

    $buttonbarFrame->pack(
        -side => 'top',
        -fill => 'x'
    );

    $optionsFrame->pack(
        -side => 'bottom',
        -fill => 'x',
        -expand => 1,
    );

    $shiftFrame->pack(
        -side => 'bottom',
        -fill => 'both',
        -expand => 1
    );

    $adjuster->packAfter($shiftFrame, -side => 'bottom');

    $nbFrame->pack(
        -side => 'bottom',
        -fill => 'both',
        -expand => 1,
    );

    $buttonRescan->pack(-side => 'left');
    $buttonDumpText->pack(-side => 'left');

    # $buttonHelp->pack( -side => 'right' );
    $labelUT->pack(-side => 'right');
    $buttonVerbose->pack(-side => 'right');

    $notebook->pack(
        -side => 'top',
        -fill => 'both',
        -expand => 1,
    );

    $MainWindow->deiconify();
    $MainWindow->raise();
}

sub new_instrument {
    my $instrument = shift;
    my $obsgrp = shift;
    my $verbose = shift;

    if (exists $notebook_contents{$instrument}) {
        $notebook->delete($instrument);
        delete $notebook_contents{$instrument};
        delete $notebook_headers{$instrument};
    }

    # Create a new page.
    my $nbPage = $notebook->add(
        $instrument,
        -label => $instrument,
        -raisecmd => \&page_raised,
    );

    # Add a header to the page.
    my $nbPageFrame = $nbPage->Frame();
    my $nbHeader = $nbPageFrame->Text(
        -wrap => 'none',
        -relief => 'flat',
        -foreground => $HEADERCOLOUR,
        -height => 2,
        -font => $LISTFONT,
        -takefocus => 0,
    );

    my $nbContent = $nbPageFrame->Scrolled(
        'Text',
        -wrap => 'word',
        -scrollbars => 'oe',
        -height => 100,
        -font => $LISTFONT,
    );

    $notebook_contents{$instrument} = $nbContent;
    $notebook_headers{$instrument} = $nbHeader;

    # Pack the notebook.
    $nbPageFrame->pack(
        -side => 'bottom',
        -fill => 'x',
        -expand => 1,
    );
    $nbHeader->pack(
        -side => 'top',
        -fill => 'x',
    );
    $nbContent->pack(
        -expand => 1,
        -fill => 'both',
    );

    # Fill it with information from the ObsGroup
    my $header_printed = 0;

    $nbContent->configure(-state => 'normal');
    $nbContent->delete('0.0', 'end');

    # Set up a connection to the MSBDone database.
    my $msbdb = OMP::DB::MSBDone->new(DB => $dbb);

    if (defined($obsgrp)) {
        my $counter = 0;
        my ($old_checksum, $old_msbtid) = ('') x 2;

        foreach my $obs ($obsgrp->obs) {
            my %nightlog = $obs->nightlog(
                display => 'long',
                comments => 1,
            );
            my @comments = $obs->comments;
            my $status = 0;
            if (defined $comments[($#comments)]) {
                $status = $comments[($#comments)]->status;
            }

            # Draw the header, if necessary.
            if (! $header_printed && exists $nightlog{'_STRING_HEADER'}) {
                $nbHeader->configure(
                    -state => 'normal',
                    -font => $LISTFONT,
                );
                $nbHeader->delete('0.0', 'end');

                if ($verbose && exists($nightlog{'_STRING_HEADER_LONG'})) {
                    $nbHeader->insert('end', $nightlog{'_STRING_HEADER_LONG'});
                }
                else {
                    $nbHeader->insert('end', $nightlog{'_STRING_HEADER'});
                }

                # Clean up.
                $nbHeader->configure(
                    -state => 'disabled',
                    -font => $LISTFONT,
                );

                $header_printed = 1;
            }

            # In case msbtid column is missing or has no value (calibration), use checksum.
            my $checksum = $obs->checksum;

            my $msbtid = $obs->msbtid;
            my $has_msbtid = defined $msbtid && length $msbtid;

            my ($is_new_checksum, $is_new_msbtid);

            if ($has_msbtid) {
                $is_new_msbtid = $msbtid ne ''
                    && $msbtid ne $old_msbtid;

                $old_msbtid = $msbtid
                    if $is_new_msbtid;

                # Reset to later handle case of 'calibration' since checksum 'CAL' never
                # changes.
                $old_checksum = '';
            }
            else {
                $is_new_checksum = !(
                    $old_checksum eq $checksum
                    ||
                    # Title is produced for TimeGap object elsewhere.
                    UNIVERSAL::isa($obs, 'OMP::Info::Obs::TimeGap')
                );

                $old_checksum = $checksum
                    if $is_new_checksum;
            }

            my ($index, $otag, $start);

            # If the current MSB differs from the MSB to which this
            # observation belongs, we need to insert text denoting the start
            # of the MSB. Ignore blank MSBTIDS.
            if ($checksum && ($is_new_msbtid || $is_new_checksum)) {
                # Retrieve the MSB title.
                unless (exists $msbtitles{$checksum}) {
                    my $title = $msbdb->titleMSB($checksum);
                    $msbtitles{$checksum} = $title // 'Unknown MSB';
                }

                $index = $counter;
                $otag = 'o' . $index;
                $start = $nbContent->index('insert');
                $nbContent->insert('end',
                    'Beginning of MSB titled: ' . $msbtitles{$checksum} . "\n");

                $nbContent->tag(
                    'configure', $otag,
                    -background => $BACKGROUNDMSB,
                    -foreground => $FOREGROUNDMSB,
                    -font => $LISTFONT,
                );

                # Get any activity associated with this MSB accept
                my $history;
                try {
                    $history = $msbdb->historyMSBtid($msbtid)
                        if $has_msbtid;
                }
                otherwise {
                    my $E = shift;
                    print $E;
                };

                my @comments;
                if (defined $history) {
                    @comments = $history->comments;

                    for my $c (@comments) {
                        my $author = $c->author;

                        # we should never get undef author
                        my $name = (defined $author ? $author->name : "<UNKNOWN>");
                        my $status_text = OMP::DB::MSBDone::status_to_text($c->status);
                        $nbContent->insert('end',
                            "  $status_text at " . $c->date . " UT by $name : " . $c->text . "\n");
                    }
                }

                foreach my $tag ($nbContent->tag('names', $start)) {
                    $nbContent->tag('remove', $tag, $start, 'insert');
                }

                $nbContent->tag('add', $otag, $start, 'insert');
                $nbContent->tag(
                    'configure', $otag,
                    -background => $BACKGROUNDMSB,
                    -foreground => $FOREGROUNDMSB,
                    -font => $LISTFONT,
                );

                # Binding to add comment to start/status of MSB
                if ($checksum ne 'CAL') {
                    $nbContent->tag(
                        'bind', $otag,
                        '<Double-Button-1>' => [
                            \&RaiseMSBComment, $obs,
                            $msbtitles{$checksum}, @comments
                        ]
                    );

                    bind_mouse_highlight(
                        $nbContent, $otag,
                        'bg-hi' => $HIGHLIGHTBACKGROUND,
                        'fg-hi' => $FOREGROUNDMSB,
                        'bg' => $BACKGROUNDMSB,
                        'fg' => $FOREGROUNDMSB,
                    );
                }

                $counter ++;
            }

            # Take a local copy of the index for callbacks
            $index = $counter;

            # Generate the tag name based on the index.
            $otag = 'o' . $index;

            # Get the reference position
            $start = $nbContent->index('insert');

            # Insert the line
            if ($verbose && exists $nightlog{'_STRING_LONG'}) {
                $nbContent->insert('end', $nightlog{'_STRING_LONG'} . "\n");
            }
            else {
                $nbContent->insert('end', $nightlog{'_STRING'} . "\n");
            }

            # Remove all the tags at this position.
            foreach my $tag ($nbContent->tag('names', $start)) {
                $nbContent->tag('remove', $tag, $start, 'insert');
            }

            # Create a new tag.
            $nbContent->tag('add', $otag, $start, 'insert');

            # Configure the new tag.
            my $bgcolour;
            if ($counter % 2) {
                $bgcolour = $BACKGROUND1;
            }
            else {
                $bgcolour = $BACKGROUND2;
            }

            if ($counter % 2) {
                $nbContent->tag(
                    'configure', $otag,
                    -foreground => $CONTENTCOLOUR[$status],
                    -background => $bgcolour,
                    -font => $LISTFONT,
                );
            }
            else {
                $nbContent->tag(
                    'configure', $otag,
                    -foreground => $CONTENTCOLOUR[$status],
                    -background => $bgcolour,
                    -font => $LISTFONT,
                );
            }

            # Bind the tag to double-left-click
            $nbContent->tag('bind', $otag,
                '<Double-Button-1>' => [\&RaiseComment, $obs, $index]);

            # Do some mouse-over colour changing.
            bind_mouse_highlight(
                $nbContent, $otag,
                'bg-hi' => $HIGHLIGHTBACKGROUND,
                'fg-hi' => $CONTENTCOLOUR[$status],
                'bg' => $bgcolour,
                'fg' => $CONTENTCOLOUR[$status],
            );

            # And increment the counter.
            $counter ++;
        }
    }

    # Bind the mousewheel.
    BindMouseWheel($nbContent);

    # And disable the text widget.
    $nbContent->configure(-state => 'disable');

    $nbContent->see('end');

    $notebook->raise($instrument);
}

sub page_raised {
    $current_instrument = $notebook->raised();
}

sub redraw {
    my $widget = shift;
    my $current = shift;
    my $verbose = shift;

    foreach my $inst (keys %notebook_contents) {
        $notebook->delete($inst);
        delete $notebook_contents{$inst};
    }

    foreach my $inst (keys %obs) {
        try {
            new_instrument($inst, $obs{$inst}, $verbose);
        }
        catch OMP::Error with {
            my $E = shift;
            print "Could not process instrument $inst: $E\n";
        }
        otherwise {
            my $E = shift;
            print "Could not process instrument $inst: $E\n";
        };
    }

    if ((defined $current) && (exists $notebook_contents{$current})) {
        $notebook->raise($current);
    }
    elsif ((defined $lastinst) && (exists $notebook_contents{$lastinst})) {
        $notebook->raise($lastinst);
    }

    populate_shiftlog_widget();
}

sub rescan {
    my $ut = shift;
    my $telescope = shift;

    try {
        my $grp = OMP::Info::ObsGroup->new(
            ADB => $arcdb,
            telescope => $telescope,
            date => $ut,
            ignorebad => 1,
        );
        unless ($grp->numobs) {
            # No longer raise an error for there being no observations -- just set
            # up the dummy "NONE" instrument.  We don't need to call new_instrument
            # (to lay out the window) if we're not opening a dialog box.
            %obs = (NONE => undef);
        }
        else {
            my $gaplength = OMP::Config->getData('timegap');
            $grp->locate_timegaps($gaplength);

            %obs = $grp->groupby('instrument');
            grp_to_ref($grp);

            # Kluge to work around the case where
            # obs object doesn't have an instrument defined
            delete $obs{''};
            throw OMP::Error("Instrument is undefined for all observations.")
                unless (scalar(keys %obs));

            my @sorted_obs = sort {$b->startobs <=> $a->startobs} $grp->obs;

            $lastinst = $sorted_obs[0]->instrument;
        }
    }
    catch OMP::Error with {
        my $Error = shift;
        require Tk::DialogBox;
        new_instrument('NONE', undef, 1);
        my $dbox = $MainWindow->DialogBox(
            -title => 'Error',
            -buttons => ['OK'],
        );

        my $label = $dbox->add('Label', -text => 'Error: ' . $Error->{-text})->pack;
        my $but = $dbox->Show;

        # Add logging.
        OMP::General->log_message("OMP::Error in obslog.pl/rescan:\n text: "
            . $Error->{'-text'}
            . "\n file: " . $Error->{'-file'}
            . "\n line: " . $Error->{'-line'});

        undef %obs;
    }
    otherwise {
        my $Error = shift;
        require Tk::DialogBox;
        new_instrument('NONE', undef, 1);
        my $dbox = $MainWindow->DialogBox(
            -title => 'Error',
            -buttons => ['OK'],
        );

        my $label = $dbox->add('Label', -text => "Error: " . $Error->{-text})->pack;
        my $but = $dbox->Show;

        # Add logging.
        OMP::General->log_message("General error in obslog.pl/rescan:\n text: "
            . $Error->{'-text'}
            . "\n file: " . $Error->{'-file'}
            . "\n line: " . $Error->{'-line'});
    };

    update_shiftlog_comments();

    $id->cancel if defined($id);

    if ($ut eq $currentut) {
        $id = $MainWindow->after($SCANFREQ, sub {
            full_rescan($ut, $telescope);
        });
    }
}

# Perform a full rescan/redraw sequence.
sub full_rescan {
    my $ut = shift;
    my $telescope = shift;

    # It is here, instead of running it once at the beginning, as current date may
    # change during use, which would cause files to be searched only at the start.
    update_search_options($ut, $telescope);
    rescan($ut, $telescope);
    redraw(undef, $current_instrument, $verbose);
}

# Handy wrapper around window re-draw for instrument of given OMP::Info::Obs
# object, re-scan, and closing of a given window.
sub redraw_rescan_close_window {
    my ($obs, $window) = @_;

    redraw(undef, uc($obs->instrument), $verbose);

    rescan_close_window($window);
    return;
}

# Handy wrapper around re-scan and closing of a given window.
sub rescan_close_window {
    my ($window) = @_;

    $id->cancel if defined $id;

    $id = $MainWindow->after($SCANFREQ, sub {
        full_rescan($ut, $telescope);
    }) if $ut eq $currentut;

    CloseWindow($window);
    return;
}

sub dump_to_disk {
    my $current = $notebook->raised;
    my $contentHeader = $notebook_headers{$current};
    my $contentBody = $notebook_contents{$current};
    my $header = $contentHeader->get('0.0', 'end');
    my $text = $contentBody->get('0.0', 'end');
    my $filename = "$ut-$current.log";

    open(my $fh, '>', $filename)
        or return;    # just a quickie, need a better way to handle this
    print $fh $header;
    print $fh $text;
    close $fh;

    my $dbox = $MainWindow->DialogBox(
        -title => 'File Saved',
        -buttons => ['OK'],
    );

    my $label = $dbox->add('Label', -text => 'Data has been saved in ' . $filename)->pack;
    my $but = $dbox->Show;
}

# Display the comment window and allow for editing, etc, etc, etc.
sub RaiseComment {
    my $widget = shift;
    my $obs = shift;
    my $index = shift;

    my $status;
    my $scrolledComment;

    $id->cancel if defined $id;

    my @comments = $obs->comments;
    $status = $obs->status;

    my $CommentWindow = $MainWindow->Toplevel();
    $CommentWindow->title('OMP Observation Log Tool Commenting System');

    # $commentFrame contains the entire frame.
    my $commentFrame = $CommentWindow->Frame->pack(
        -side => 'top',
        -fill => 'both',
        -expand => 1,
    );

    my $contentFrame = $commentFrame->Frame->pack(
        -side => 'top',
        -fill => 'x',
    );

    my $entryFrame = $commentFrame->Frame(-relief => 'groove')->pack(
        -side => 'top',
        -fill => 'both',
        -expand => 1,
    );

    my $buttonFrame = $commentFrame->Frame->pack(
        -side => 'bottom',
        -fill => 'x',
    );

    # $commentHeader contains the header information
    my $contentHeader = $contentFrame->Text(
        -wrap => 'none',
        -relief => 'flat',
        -foreground => $HEADERCOLOUR,
        -height => 1,
        -font => $HEADERFONT,
        -takefocus => 0,
        -state => 'disabled',
    )->pack(
        -side => 'top',
        -fill => 'x',
    );

    # $contentObs contains the observation info
    my $contentObs = $contentFrame->Scrolled(
        'Text',
        -wrap => 'word',
        -relief => 'flat',
        -height => 5,
        -font => $LISTFONT,
        -takefocus => 0,
        -state => 'disabled',
        -scrollbars => 'oe',
    )->pack(
        -side => 'top',
        -fill => 'x',
    );

    # $scrolledComment is the text area that will be used for comment entry.
    $scrolledComment = $entryFrame->Scrolled(
        'Text',
        -wrap => 'word',
        -height => 10,
        -font => $opt{'font-var'},
        -scrollbars => 'oe',
    )->pack(
        -side => 'bottom',
        -expand => 1,
        -fill => 'both',
    );

    my $radioFrame = $entryFrame->Frame->pack(
        -side => 'top',
        -fill => 'x',
    );

    # $textStatus displays the string "Status:"
    my $textStatus = $radioFrame->Label(
        -text => 'Status: ',
        -font => $opt{'font-var'},
    )->pack(
        -side => 'left',
    );

    if (UNIVERSAL::isa($obs, 'OMP::Info::Obs::TimeGap')) {
        my $radioWeather = $radioFrame->Radiobutton(
            -text => 'weather',
            -value => OMP__TIMEGAP_WEATHER,
            -variable => \$status,
            -font => $opt{'font-var'},
        )->pack(
            -side => 'left',
        );
        my $radioInstrument = $radioFrame->Radiobutton(
            -text => 'instrument',
            -value => OMP__TIMEGAP_INSTRUMENT,
            -variable => \$status,
            -font => $opt{'font-var'},
        )->pack(
            -side => 'left',
        );
        my $radioFault = $radioFrame->Radiobutton(
            -text => 'fault',
            -value => OMP__TIMEGAP_FAULT,
            -variable => \$status,
            -font => $opt{'font-var'},
        )->pack(
            -side => 'left',
        );
        my $radioLastProject = $radioFrame->Radiobutton(
            -text => 'last proj.',
            -value => OMP__TIMEGAP_PREV_PROJECT,
            -variable => \$status,
            -font => $opt{'font-var'},
        )->pack(
            -side => 'left',
        );
        my $radioNextProject = $radioFrame->Radiobutton(
            -text => 'next proj.',
            -value => OMP__TIMEGAP_NEXT_PROJECT,
            -variable => \$status,
            -font => $opt{'font-var'},
        )->pack(
            -side => 'left',
        );

        # Second row of buttons...
        my $radioFrame2 = $entryFrame->Frame->pack(
            -side => 'top',
            -fill => 'x',
        );

        my $textStatus2 = $radioFrame2->Label(
            -text => '            ',
        )->pack(
            -side => 'left',
        );
        my $radioNotDriver = $radioFrame2->Radiobutton(
            -text => 'observer not driver',
            -value => OMP__TIMEGAP_NOT_DRIVER,
            -variable => \$status,
            -font => $opt{'font-var'},
        )->pack(
            -side => 'left',
        );
        my $radioScheduled = $radioFrame2->Radiobutton(
            -text => 'scheduled downtime',
            -value => OMP__TIMEGAP_SCHEDULED,
            -variable => \$status,
            -font => $opt{'font-var'},
        )->pack(
            -side => 'left',
        );
        my $radioOverhead = $radioFrame2->Radiobutton(
            -text => 'queue overhead',
            -value => OMP__TIMEGAP_QUEUE_OVERHEAD,
            -variable => \$status,
            -font => $opt{'font-var'},
        )->pack(
            -side => 'left',
        );
        my $radioLogistics = $radioFrame2->Radiobutton(
            -text => 'logistics',
            -value => OMP__TIMEGAP_LOGISTICS,
            -variable => \$status,
            -font => $opt{'font-var'},
        )->pack(
            -side => 'left',
        );
        my $radioUnknown = $radioFrame->Radiobutton(
            -text => 'unknown',
            -value => OMP__TIMEGAP_UNKNOWN,
            -variable => \$status,
            -font => $opt{'font-var'},
        )->pack(
            -side => 'left',
        );
    }
    else {
        my $radioGood = $radioFrame->Radiobutton(
            -text => 'good',
            -value => OMP__OBS_GOOD,
            -variable => \$status,
            -font => $opt{'font-var'},
        )->pack(
            -side => 'left',
        );
        my $radioBad = $radioFrame->Radiobutton(
            -text => 'bad',
            -value => OMP__OBS_BAD,
            -variable => \$status,
            -font => $opt{'font-var'},
        )->pack(
            -side => 'left',
        );
        my $radioJunk = $radioFrame->Radiobutton(
            -text => 'junk',
            -value => OMP__OBS_JUNK,
            -variable => \$status,
            -font => $opt{'font-var'},
        )->pack(
            -side => 'left',
        );
        my $radioQuestionable = $radioFrame->Radiobutton(
            -text => 'questionable',
            -value => OMP__OBS_QUESTIONABLE,
            -variable => \$status,
            -font => $opt{'font-var'},
        )->pack(
            -side => 'left',
        );
        my $radioRejected = $radioFrame->Radiobutton(
            -text => 'rejected',
            -value => OMP__OBS_REJECTED,
            -variable => \$status,
            -font => $opt{'font-var'},
        )->pack(-side => 'left',);

    }

    # $textUser displays the current user id.
    my $textUser = $radioFrame->Label(
        -text => 'Current user: ' . $user->userid,
        -font => $opt{'font-var-bold'},
    )->pack(
        -side => 'left',
    );

    # $buttonSave is the button that allows the user to save the comment
    # to the database.
    my $buttonSave = $buttonFrame->Button(
        -text => 'Save',
        -command => sub {
            my $t = $scrolledComment->get('0.0', 'end');
            SaveComment($status, $t, $user, $obs, $index);
            redraw_rescan_close_window($obs, $CommentWindow);
        },
        -font => $opt{'font-var-bold'},
    )->pack(
        -side => 'left',
        -anchor => 'n',
    );

    # $buttonCancel is the button that closes the window without saving
    # any changes.
    my $buttonCancel = $buttonFrame->Button(
        -text => 'Cancel',
        -command => sub {
            rescan_close_window($CommentWindow);
        },
        -font => $opt{'font-var-bold'},
    )->pack(
        -side => 'left',
        -anchor => 'n',
    );

    if ((uc $telescope) eq 'UKIRT') {
        my $buttonGuiding = $buttonFrame->Button(
            -text => 'Lost Guiding',
            -command => sub {
                my $t = 'Lost guiding, repeating observation.';
                my $status = OMP__OBS_BAD;
                SaveComment($status, $t, $user, $obs, $index);
                redraw_rescan_close_window($obs, $CommentWindow);
            },
            -font => $opt{'font-var'},
        )->pack(
            -side => 'right',
            -anchor => 'n',
        );
        my $buttonZeroCountdown = $buttonFrame->Button(
            -text => 'Zero Countdown',
            -command => sub {
                my $t = 'Zero countdown problem, repeating group.';
                my $status = OMP__OBS_BAD;
                SaveComment($status, $t, $user, $obs, $index);
                redraw_rescan_close_window($obs, $CommentWindow);
            },
            -font => $opt{'font-var'},
        )->pack(
            -side => 'right',
            -anchor => 'n',
        );
    }

    # Get the observation information.
    my %nightlog = $obs->nightlog(
        display => 'long',
        comments => 1,
    );

    # Insert the header information.
    $contentHeader->configure(-state => 'normal');
    $contentHeader->delete('0.0', 'end');
    $contentHeader->insert('end', $nightlog{'_STRING_HEADER'});
    $contentHeader->configure(-state => 'disabled');

    # Insert the observation information.
    $contentObs->configure(-state => 'normal');
    $contentObs->delete('0.0', 'end');
    $contentObs->insert('end', $nightlog{'_STRING'});
    $contentObs->configure(-state => 'disabled');

    # Get a comment for this observation and user (if one exists)
    # and pre-fill the entry box.
    foreach my $comment ($obs->comments) {
        if ($comment->author->userid eq $user->userid) {
            $scrolledComment->delete('0.0', 'end');
            $scrolledComment->insert('end', $comment->text);
            last;
        }
    }
}

# Display the multiple observation comment window and allow for
# editing, etc, etc, etc.
sub RaiseMultiComment {
    my $status;
    my $observations = '';
    my $scrolledComment;
    my $instrument;

    my @insts = keys %obs;

    my $CommentWindow = $MainWindow->Toplevel();
    $CommentWindow->title(
        'OMP Observation Log Tool Multiple Observation Commenting System');

    # $commentFrame contains the entire frame.
    my $commentFrame = $CommentWindow->Frame->pack(
        -side => 'top',
        -fill => 'both',
        -expand => 1,
    );

    my $obsFrame = $commentFrame->Frame->pack(
        -side => 'top',
        -fill => 'x',
    );
    my $obsLabel = $obsFrame->Label(
        -text => 'Observations: ',
        -font => $opt{'font-var'},
    )->pack(
        -side => 'left',
    );
    my $obsEntry = $obsFrame->Entry(
        -textvariable => \$observations,
    )->pack(
        -side => 'left',
    );
    my $obsExamp = $obsFrame->Label(
        -text => 'e.g. 10-12 or 10-12,14',
        -font => $opt{'font-var'},
    )->pack(
        -side => 'left',
    );

    my $instFrame = $commentFrame->Frame->pack(
        -side => 'top',
        -fill => 'x',
    );
    my $instLabel = $instFrame->Label(
        -text => 'Instrument: ',
        -font => $opt{'font-var'},
    )->pack(
        -side => 'left',
    );
    my @instRadios;
    foreach my $i (0 .. $#insts) {
        $instRadios[$i] = $instFrame->Radiobutton(
            -text => $insts[$i],
            -value => $insts[$i],
            -variable => \$instrument,
            -font => $opt{'font-var'},
        )->pack(
            -side => 'left',
        );

        if ($#insts == 0) {
            $instrument = $insts[0];
        }
    }

    my $entryFrame = $commentFrame->Frame(
        -relief => 'groove',
    )->pack(
        -side => 'top',
        -fill => 'both',
        -expand => 1,
    );

    my $buttonFrame = $commentFrame->Frame->pack(
        -side => 'bottom',
        -fill => 'x',
    );

    # $scrolledComment is the text area that will be used for comment entry.
    $scrolledComment = $entryFrame->Scrolled(
        'Text',
        -wrap => 'word',
        -height => 10,
        -scrollbars => 'oe',
        -font => $opt{'font-var'},
    )->pack(
        -side => 'bottom',
        -expand => 1,
        -fill => 'both',
    );

    my $radioFrame = $entryFrame->Frame->pack(
        -side => 'top',
        -fill => 'x',
    );

    # $textStatus displays the string "Status:"
    my $textStatus = $radioFrame->Label(
        -text => 'Status: ',
        -font => $opt{'font-var'},
    )->pack(
        -side => 'left',
    );
    my $radioGood = $radioFrame->Radiobutton(
        -text => 'good',
        -value => OMP__OBS_GOOD,
        -variable => \$status,
        -font => $opt{'font-var'},
    )->pack(
        -side => 'left',
    );
    my $radioBad = $radioFrame->Radiobutton(
        -text => 'bad',
        -value => OMP__OBS_BAD,
        -variable => \$status,
        -font => $opt{'font-var'},
    )->pack(
        -side => 'left',
    );
    my $radioJunk = $radioFrame->Radiobutton(
        -text => 'junk',
        -value => OMP__OBS_JUNK,
        -variable => \$status,
        -font => $opt{'font-var'},
    )->pack(
        -side => 'left',
    );
    my $radioQuestionable = $radioFrame->Radiobutton(
        -text => 'questionable',
        -value => OMP__OBS_QUESTIONABLE,
        -variable => \$status,
        -font => $opt{'font-var'},
    )->pack(
        -side => 'left',
    );
    my $radioRejected = $radioFrame->Radiobutton(
        -text => 'rejected',
        -value => OMP__OBS_REJECTED,
        -variable => \$status,
        -font => $opt{'font-var'},
    )->pack(
        -side => 'left',
    );

    # $textUser displays the current user id.
    my $textUser = $radioFrame->Label(
        -text => 'Current user: ' . $user->userid,
        -font => $opt{'font-var-bold'},
    )->pack(
        -side => 'left',
    );

    # $buttonSave is the button that allows the user to save the comment
    # to the database.
    my $buttonSave = $buttonFrame->Button(
        -text => 'Save',
        -command => sub {
            my $t = $scrolledComment->get('0.0', 'end');
            SaveMultiComment($status, $t, $observations, $user, $instrument);
            full_rescan($ut, $telescope);
            if ($currentut eq $ut) {
                $id = $MainWindow->after($SCANFREQ, sub {
                    full_rescan($ut, $telescope);
                });
            }
            CloseWindow($CommentWindow);
        },
        -font => $opt{'font-var-bold'},
    )->pack(
        -side => 'left',
        -anchor => 'n',
    );

    # $buttonCancel is the button that closes the window without saving
    # any changes.
    my $buttonCancel = $buttonFrame->Button(
        -text => 'Cancel',
        -command => sub {
            rescan_close_window($CommentWindow);
        },
        -font => $opt{'font-var-bold'},
    )->pack(
        -side => 'left',
        -anchor => 'n',
    );

    if ((uc $telescope) eq 'UKIRT') {
        my $buttonGuiding = $buttonFrame->Button(
            -text => 'Lost Guiding',
            -command => sub {
                my $t = 'Lost guiding, repeating observation.';
                my $status = OMP__OBS_BAD;
                SaveMultiComment($status, $t, $observations, $user, $instrument);
                full_rescan($ut, $telescope);
                if ($currentut eq $ut) {
                    $id = $MainWindow->after($SCANFREQ, sub {
                        full_rescan($ut, $telescope);
                    });
                }
                CloseWindow($CommentWindow);
            },
            -font => $opt{'font-var'},
        )->pack(
            -side => 'right',
            -anchor => 'n',
        );
        my $buttonZeroCountdown = $buttonFrame->Button(
            -text => 'Zero Countdown',
            -command => sub {
                my $t = 'Zero countdown problem, repeating group.';
                my $status = OMP__OBS_BAD;
                SaveMultiComment($status, $t, $observations, $user, $instrument);
                full_rescan($ut, $telescope);
                if ($currentut eq $ut) {
                    $id = $MainWindow->after($SCANFREQ, sub {
                        full_rescan($ut, $telescope);
                    });
                }
                CloseWindow($CommentWindow);
            },
            -font => $opt{'font-var'},
        )->pack(
            -side => 'right',
            -anchor => 'n',
        );
    }
}

# Display form to enter comment (mainly) to specify reason for change in MSB status.
sub RaiseMSBComment {
    my (undef, $obs, $title, @comment) = @_;

    $id->cancel if defined $id;

    my $CommentWindow = $MainWindow->Toplevel();
    $CommentWindow->title("OMP MSB Log Tool: $title");

    # $commentFrame contains the entire frame.
    my $commentFrame = $CommentWindow->Frame->pack(
        -side => 'top',
        -fill => 'both',
        -expand => 1,
    );

    my $contentFrame = $commentFrame->Frame->pack(
        -side => 'top',
        -fill => 'x',
    );

    my $entryFrame = $commentFrame->Frame->pack(
        -side => 'top',
        -fill => 'both',
        -expand => 1,
    );

    my $buttonFrame = $commentFrame->Frame->pack(
        -side => 'bottom',
        -fill => 'x',
    );

    my $titleFrame = $contentFrame->Text(
        -wrap => 'none',
        -relief => 'flat',
        -foreground => $HEADERCOLOUR,
        -height => 1,
        -font => $HEADERFONT,
        -takefocus => 0,
        -state => 'disabled',
    )->pack(
        -side => 'top',
        -fill => 'x',
    );

    my $summaryFrame = $contentFrame->Scrolled(
        'Text',
        -wrap => 'word',
        -relief => 'flat',
        -font => $opt{'font-var'},
        -takefocus => 0,
        -state => 'disabled',
        -scrollbars => 'oe',
    )->pack(
        -side => 'top',
        -fill => 'x',
    );

    {
        # Summary height for the UKIRT telescope is the default, in case
        # $obs->telescope gives something unknown.
        my %sum_height = (
            'JCMT' => 5,
            'UKIRT' => 7,
        );
        my $tel = uc $obs->telescope eq 'JCMT' ? 'JCMT' : 'UKIRT';
        $summaryFrame->configure(-height => $sum_height{$tel});
    }

    my $histLabel = $entryFrame->Label(
        -text => 'History:',
        -font => $HEADERFONT,
    )->pack(
        -side => 'top',
        -anchor => 'nw'
    );

    my $histText = $entryFrame->Scrolled(
        'Text',
        -wrap => 'word',
        -height => 1,
        -scrollbars => 'oe',
        -state => 'disabled',
        -borderwidth => 0,
        -font => $opt{'font-var'},
    )->pack(
        -side => 'top',
        -fill => 'x',
    );

    my $userLabel = $entryFrame->Label(
        -text => 'Current user: ' . $user->userid,
        -font => $opt{'font-var-bold'},
    )->pack(
        -side => 'top',
        -anchor => 'nw',
    );

    # (Current) User's comments.
    my $userComment = $entryFrame->Scrolled(
        'Text',
        -wrap => 'word',
        -height => 10,
        -scrollbars => 'oe',
        -font => $opt{'font-var'},
    )->pack(
        -expand => 1,
        -side => 'top',
        -fill => 'both',
    );

    # $buttonSave is the button that allows the user to save the comment
    # to the database.
    my $buttonSave = $buttonFrame->Button(
        -text => 'Save',
        -command => sub {
            SaveMSBComment($obs, $user, $userComment->get('0.0', 'end'));
            redraw_rescan_close_window($obs, $CommentWindow);
        },
        -font => $opt{'font-var-bold'},
    )->pack(
        -side => 'left',
        -anchor => 'n',
    );

    # $buttonCancel is the button that closes the window without saving
    # any changes.
    my $buttonCancel = $buttonFrame->Button(
        -text => 'Cancel',
        -command => sub {
            rescan_close_window($CommentWindow);
        },
        -font => $opt{'font-var-bold'},
    )->pack(
        -side => 'left',
        -anchor => 'n',
    );

    # Clear junk if any.
    $_->delete('0.0', 'end') for $titleFrame, $summaryFrame, $userComment;

    for my $conf ([$titleFrame, "MSB: $title"],
            [$summaryFrame, $obs->summary('text')]) {
        $conf->[0]->configure(
            -state => 'normal',
            -font => $opt{'font-var'},
        );
        $conf->[0]->insert('end', $conf->[1]);
        $conf->[0]->configure(
            -state => 'disabled',
            -font => $opt{'font-var'},
        );
    }

    # Add old comments if any.
    #
    # Separator between parts of same OMP::Info::Comments object.
    my $sep = "\n";

    #  Separator between two O::I::C objects.
    my $comment_sep = $sep . '-' x 50 . $sep;

    my $hist = '';
    foreach my $c (@comment) {
        my $text = $c->text;
        my $status = $c->status;

        # Start of next Comment object.
        $hist .= $comment_sep
            if $hist;

        $hist .= '* ' . $c->author->name . ':'
            if $c->author->name;

        $hist .= $sep . OMP::DB::MSBDone::status_to_text($status)
            if $status;

        $hist .= ($status ? ', ' : $sep) . $c->date . ' UT'
            if $c->date;

        $hist .= $sep . $text
            if $text;
    }
    $hist =~ s/\s+$//;

    unless ($hist) {
        for my $w ($histLabel, $histText) {
            $w->destroy if Tk::Exists($w);
        }
    }
    else {
        my ($min, $max) = (5, 8);
        my $rows = ($hist =~ tr/\n//);
        $rows = $min >= $rows
            ? $min
            : $max <= $rows
                ? $max
                : $rows;
        $histText->configure(-height => $rows,);

        $histText->configure(-state => 'normal');
        $histText->delete('0.0', 'end');
        $histText->insert('end', $hist);
        $histText->configure(-state => 'disable');
    }

    return;
}

sub help {
}

sub SaveComment {
    my $status = shift;
    my $text = shift;
    my $user = shift;
    my $obs = shift;
    my $index = shift;

    chomp $text;

    # Add the comment to the database
    my $comment = OMP::Info::Comment->new(
        author => $user,
        text => $text,
        status => $status
    );

    my $odb = OMP::DB::Obslog->new(DB => $dbb);
    $odb->addComment($comment, $obs);

    # Add the comment to the observation.
    my @obsarray;
    push @obsarray, $obs;
    $odb->updateObsComment(\@obsarray);
    $obs = $obsarray[0];

    # And let's not forget to update the status of the observation.
    $obs->status($status);
}

sub SaveMultiComment {
    my $status = shift;
    my $text = shift;
    my $observations = shift;
    my $user = shift;
    my $instrument = shift;

    return if ! defined $status
        || ! defined $observations
        || ! defined $user
        || ! defined $instrument;

    chomp $text;

    my $comment = OMP::Info::Comment->new(
        author => $user,
        text => $text,
        status => $status
    );

    my $odb = OMP::DB::Obslog->new(DB => $dbb);

    my @obs = ();
    @obs = split ',', $observations;

    # Convert a:b or a-b to a..b
    for (my $i = 0; $i <= $#obs; $i ++) {
        if ($obs[$i] =~ /([:-])/) {
            my ($start, $end) = split /$1/, $obs[$i];
            my @junk = $start .. $end;
            splice @obs, $i, 1, @junk;
            $i += $#junk;
        }
    }

    foreach my $obsnum (@obs) {
        my $startobs = $obs_ref{$obsnum}{$instrument}{STARTOBS};
        my $obsid = $obs_ref{$obsnum}{$instrument}{OBSID};

        next unless defined $startobs;

        # print "will insert comment for $instrument #$obsnum $startobs $obsid\n";

        my $obs = OMP::Info::Obs->new(
            runnr => $obsnum,
            instrument => $instrument,
            startobs => $startobs,
            telescope => $telescope,
            obsid => $obsid,
        );

        $odb->addComment($comment, $obs);
    }

    # use Data::Dumper;
    # print Dumper \@obs;

    # print "status: $status\ntext: $text\nobservations: $observations\nuser: $user\n";
}

sub SaveMSBComment {
    my ($obs, $user, $text) = @_;

    throw OMP::Error::FatalError('Cannot save: Need user id.')
        unless $user;

    throw OMP::Error::FatalError(
        'Cannot save: Need OMP::Info::Obs object with project id and MSB checksum.')
        unless $obs->checksum
        && $obs->projectid;

    my $db = OMP::DB::MSBDone->new(
        'ProjectID' => $obs->projectid,
        'DB' => $dbb,
    );

    $text = OMP::Info::Comment->new(
        'author' => $user,
        'text' => $text,
        'tid' => $obs->msbtid,
    );

    $db->addMSBcomment($obs->checksum, $text);

    return;
}

sub CloseWindow {
    my $window = shift;
    $window->destroy if Exists($window);
}

sub InvalidUTDate {
    my $string = shift;
    print "Invalid UT date: $string\n";
}

# Mousewheel binding from Mastering Perl/Tk, pp 370-371.
sub BindMouseWheel {
    my ($w) = @_;

    if ($^O eq 'MSWin32') {
        $w->bind('<MouseWheel>' => [
            sub {
                $_[0]->yview('scroll', - ($_[1] / 120) * 3, 'units')
            },
            Ev('D')
        ]);
    }
    else {
        $w->bind('<4>' => sub {
            $_[0]->yview('scroll', -3, 'units') unless $Tk::strictMotif;
        });
        $w->bind('<5>' => sub {
            $_[0]->yview('scroll', +3, 'units') unless $Tk::strictMotif;
        });
    }
}

# Do some mouse-over colour changing given a widget, tag and a hash of
# colors for highlight & normal views.
sub bind_mouse_highlight {
    my ($widget, $tag, %color) = @_;

    $widget->tag(
        'bind', $tag,
        '<Any-Enter>' => sub {
            shift->tag(
                'configure', $tag,
                -background => $color{'bg-hi'},
                -foreground => $color{'fg-hi'},
                -relief => 'raised',
                -borderwidth => 1,
            );
        });

    $widget->tag(
        'bind', $tag,
        '<Any-Leave>' => sub {
            shift->tag(
                'configure', $tag,
                -background => $color{'bg'},
                -foreground => $color{'fg'},
                -relief => 'flat',
            );
        });

    return;
}

# ShiftLog

sub create_shiftlog_widget {
    my $w = shift;

    # Create a holder frame
    my $shiftlog = $w->Frame()->pack(
        -side => 'top',
        -expand => 1,
        -fill => 'both',
    );

    my $topbar = $shiftlog->Frame->pack(
        -side => 'top',
        -expand => 0,
        -fill => 'x',
    );

    # Create the text widget so that we can store the reference
    $shiftcommentText = $shiftlog->Scrolled(
        'Text',
        -height => 6,
        -scrollbars => 'oe',
        -font => $opt{'font-var'},
    )->pack(
        -side => 'bottom',
        -expand => 1,
        -fill => 'both',
    );

    # This variable controls whether we are in Local time or UT
    # Options are "LocalTime" and "UT"
    my $TZ = "LocalTime";

    # A label.
    $topbar->Label(
        -text => "Shift comments. ",
        -font => $opt{'font-var'},
    )->pack(
        -side => 'left',
    );
    $topbar->Label(
        -textvariable => \$utdisp,
        -font => $opt{'font-var-bold'},
    )->pack(
        -side => 'left',
    );

    # Button to add a new comment.
    $topbar->Button(
        -text => 'Add New Shift Comment',
        -command => sub {
            raise_shift_comment();
        },
        -font => $opt{'font-var'},
    )->pack(
        -side => 'right',
    );

    # Button to add comments for multiple observations.
    $topbar->Button(
        -text => 'Multi-Observation Comment',
        -command => sub {
            RaiseMultiComment();
        },
        -font => $opt{'font-var'},
    )->pack(
        -side => 'right',
    );

    BindMouseWheel($shiftcommentText);

    $shiftcommentText->configure(
        -state => 'disable',
        -font => $opt{'font-var'},
    );
    $shiftcommentText->see('end');
}

sub update_shiftlog_comments {
    my $sdb = OMP::ShiftDB->new(DB => $dbb);
    my $query = OMP::ShiftQuery->new(HASH => {
        date => {value => $ut, delta => 1},
        telescope => $telescope,
    });

    try {
        @shiftcomments = $sdb->getShiftLogs($query);
    }
    catch OMP::Error with {
        my $Error = shift;
        require Tk::DialogBox;
        my $dbox = $MainWindow->DialogBox(
            -title => 'Error',
            -buttons => ['OK'],
        );
        my $label = $dbox->add(
            'Label',
            -text => 'Error: ' . $Error->{-text},
            -font => $opt{'font-var'},
        )->pack;
        my $but = $dbox->Show;

        # Add logging.
        OMP::General->log_message("General error in obslog.pl/rescan:\n text: "
            . $Error->{'-text'}
            . "\n file: " . $Error->{'-file'}
            . "\n line: " . $Error->{'-line'});

        undef @shiftcomments;
    }
    otherwise {
        my $Error = shift;
        require Tk::DialogBox;
        my $dbox = $MainWindow->DialogBox(
            -title => 'Error',
            -buttons => ['OK'],
        );

        my $label = $dbox->add(
            'Label',
            -text => "Error: " . $Error->{-text},
            -font => $opt{'font-var'},
        )->pack;
        my $but = $dbox->Show;

        # Add logging.
        OMP::General->log_message("General error in obslog.pl/rescan:\n text: "
            . $Error->{'-text'}
            . "\n file: " . $Error->{'-file'}
            . "\n line: " . $Error->{'-line'});
    };
}

sub populate_shiftlog_widget {
    # Update list of comments.
    update_shiftlog_comments();

    # Clear and enable the widget.
    $shiftcommentText->configure(-state => 'normal');
    $shiftcommentText->delete('1.0', 'end');
    my $tagnames = $shiftcommentText->tagNames();
    foreach my $tagname (@$tagnames) {
        next if $tagname eq 'sel';
        $shiftcommentText->tagDelete($tagname);
    }

    # Set up a counter for tag names.
    my $counter = 0;

    # Loop over comments
    for my $c (@shiftcomments) {
        # Take a local copy of the index for callbacks.
        my $index = $counter;

        # Generate the tag name based on the index.
        my $ctag = 'c' . $index;

        #Get the reference position.
        my $start = $shiftcommentText->index('insert');

        my $date = $c->date;
        my $username = $c->author->name;
        my $text = OMP::Display->format_text($c->text, $c->preformatted);

        my $insertstring = $date->datetime . "UT by $username\n$text\n";

        # Insert the string.
        $shiftcommentText->insert('end', $insertstring);
        $shiftcommentText->configure(-font => $opt{'font-fixed-bold'});

        # Remove all tags at this position.
        foreach my $tag ($shiftcommentText->tag('names', $start)) {
            $shiftcommentText->tag('delete', $tag, $start, 'insert');
        }

        # Create a new tag.
        $shiftcommentText->tag('add', $ctag, $start, 'insert');

        # Configure the new tag.
        my $bgcolour;
        if ($counter % 2) {
            $bgcolour = $BACKGROUND1;
        }
        else {
            $bgcolour = $BACKGROUND2;
        }
        $shiftcommentText->tag('configure', $ctag, -background => $bgcolour,);

        if ((uc $user->userid) eq (uc $c->author->userid)) {
            # Bind the tag to double-left-click.
            $shiftcommentText->tag('bind', $ctag,
                '<Double-Button-1>' => [\&raise_shift_comment, $c, $index]);

            # Do some mouse-over colour changing.
            $shiftcommentText->tag(
                'bind', $ctag,
                '<Any-Enter>' => sub {
                    shift->tag(
                        'configure', $ctag,
                        -background => $HIGHLIGHTBACKGROUND,
                        -foreground => $CONTENTCOLOUR[0],
                        -relief => 'raised',
                        -borderwidth => 1,
                    );
                });

            $shiftcommentText->tag(
                'bind', $ctag,
                '<Any-Leave>' => sub {
                    shift->tag(
                        'configure', $ctag,
                        -background => $bgcolour,
                        -foreground => $CONTENTCOLOUR[0],
                        -relief => 'flat',
                    );
                });
        }

        # Increment the counter.
        $counter ++;
    }

    $shiftcommentText->configure(
        -state => 'disable',
        -font => $opt{'font-var'},
    );
    $shiftcommentText->see('end');
}

sub save_shift_comment {
    my $w = shift;
    my $commenttext = shift;
    my $TZ = shift;
    my $time = shift;

    return unless $commenttext =~ /\w/;

    # Use current date if the field is blank
    my $date;

    if (defined $time && $time =~ /\d/a) {
        # Now need to parse the time (either as UT or local time)
        my $islocal = ($TZ eq 'UT' ? 0 : 1);
        $date = OMP::DateTools->parse_date($time, $islocal);

        # if it did not parse tell people
        unless (defined $date) {
            # popup the error and return
            require Tk::Dialog;
            my $dialog = $w->Dialog(
                -text => 'Error parsing the date string. Please fix. Should be YYYY-MM-DDTHH:MM:SS',
                -title => 'Error parsing time',
                -buttons => ['Abort'],
                -bitmap => 'error',
                -font => $opt{'font-var'},
            );

            $dialog->Show;
            return;
        }
    }
    else {
        $date = gmtime();
    }

    # Now create the comment
    my $comment = OMP::Info::Comment->new(
        author => $user,
        date => $date,
        text => $commenttext,
    );

    # And add it to the system
    my $sdb = OMP::ShiftDB->new(DB => $dbb);
    $sdb->enterShiftLog($comment, $telescope);
}

sub raise_shift_comment {
    my $widget = shift;
    my $comment = shift;
    my $index = shift;

    my $TZ = 'LocalTime';
    my $RefTime;

    my $ShiftCommentWindow = $MainWindow->Toplevel();
    $ShiftCommentWindow->title('OMP Shift Log Tool Commenting System');

    my $commentFrame = $ShiftCommentWindow->Frame->pack(
        -side => 'top',
        -fill => 'both',
        -expand => 1,
    );

    my $contentFrame = $commentFrame->Frame->pack(
        -side => 'top',
        -fill => 'x',
    );

    my $entryFrame = $commentFrame->Frame(
        -relief => 'groove',
    )->pack(
        -side => 'top',
        -fill => 'both',
        -expand => 1,
    );

    my $buttonFrame = $commentFrame->Frame->pack(
        -side => 'bottom',
        -fill => 'x',
    );

    my $scrolledComment = $entryFrame->Scrolled(
        'Text',
        -wrap => 'word',
        -height => 10,
        -scrollbars => 'oe',
        -takefocus => 1,
        -font => $opt{'font-var'},
    )->pack(
        -side => 'bottom',
        -expand => 1,
        -fill => 'both',
    );

    my $infoText = $entryFrame->Label(
        -text => 'Comment from ' . $user->name . ':',
        -font => $opt{'font-var'},
    )->pack(
        -side => 'left',
    );

    my $buttonSave = $buttonFrame->Button(
        -text => 'Save',
        -command => sub {
            my $t = $scrolledComment->get('0.0', 'end',);
            save_shift_comment($entryFrame, $t, $TZ, $RefTime);
            populate_shiftlog_widget();
            CloseWindow($ShiftCommentWindow);
        },
        -font => $opt{'font-var-bold'},
    )->pack(
        -side => 'left',
        -anchor => 'n',
    );

    my $buttonCancel = $buttonFrame->Button(
        -text => 'Cancel',
        -command => sub {
            CloseWindow($ShiftCommentWindow);
        },
        -font => $opt{'font-var-bold'},
    )->pack(
        -side => 'left',
        -anchor => 'n',
    );

    # Time section
    my $buttonTZLocal = $buttonFrame->Radiobutton(
        -variable => \$TZ,
        -text => 'Local Time',
        -value => 'LocalTime',
        -font => $opt{'font-var'},
    )->pack(
        -side => 'right',
    );
    my $buttonTZUT = $buttonFrame->Radiobutton(
        -variable => \$TZ,
        -text => 'UT',
        -value => 'UT',
        -font => $opt{'font-var'},
    )->pack(
        -side => 'right',
    );
    my $timeText = $buttonFrame->Entry(
        -textvariable => \$RefTime,
        -width => 20,
        -font => $opt{'font-var'},
    )->pack(
        -side => 'right',
    );
    $buttonFrame->Label(
        -text => 'Comment time: ',
        -font => $opt{'font-var'},
    )->pack(
        -side => 'right',
    );

    # Need to populate the time field
    my $update_shift_comment_time = make_update_shift_comment_time(
        \$TZ, \$RefTime);
    $update_shift_comment_time->();

    my $repeatid = $ShiftCommentWindow->repeat(
        1000, $update_shift_comment_time);

    if (defined($comment)) {
        # Insert the comment text into the box.
        $scrolledComment->insert('end',
            OMP::Display->format_text($comment->text, $comment->preformatted));

        # And the comment time (which is always UT) into the box. Disable
        # the update and don't let the user update the time either.
        $TZ = 'UT';
        $RefTime = $comment->date->ymd . 'T' . $comment->date->hms;
        $repeatid->cancel;
        $buttonTZLocal->configure(-state => 'disable');
        $buttonTZUT->configure(-state => 'disable');
        $timeText->configure(-state => 'disable');
    }

    $scrolledComment->focus();
}

sub make_update_shift_comment_time {
    my $TZRef = shift;
    my $RefTimeRef = shift;

    # Need two lexicals to allow us to track previous values
    my $PrevTime;
    my $PrevTZ;

    return sub {
        my $TZ = $$TZRef;
        my $RefTime = $$RefTimeRef;

        # If we have switched time zones, we should also synch prevtime with
        # reftime
        $PrevTime = $RefTime if (defined $PrevTZ && $TZ ne $PrevTZ);

        # Need to do a check to make sure we do not override a time
        # that has been edited
        if (defined($RefTime) && $RefTime ne $PrevTime) {
            return;
        }

        # Get the current time
        my $time;
        if ($TZ eq 'UT') {
            $time = gmtime;
        }
        else {
            $time = localtime;
        }

        # Store the new values for later reference
        $PrevTZ = $TZ;
        $$RefTimeRef = $time->datetime;
        $PrevTime = $$RefTimeRef;
    };
}

sub create_options_widget {
    my $w = shift;

    # Create a holder frame
    my $options = $w->Frame()->pack(
        -side => 'top',
        -expand => 1,
        -fill => 'x',
    );

    my $topline = $options->Frame->pack(
        -side => 'top',
        -expand => 1,
        -fill => 'x',
    );

    my $bottomline = $options->Frame->pack(
        -side => 'bottom',
        -expand => 1,
        -fill => 'x',
    );

    # Fill in the top line.
    $topline->Label(
        -text => 'Current user:',
        -width => 15,
        -font => $opt{'font-var'},
    )->pack(
        -side => 'left',
    );

    my $RefUser = $user->userid;
    $topline->Entry(
        -textvariable => \$RefUser,
        -width => 20,
        -font => $opt{'font-var-bold'},
    )->pack(
        -side => 'left',
    );

    $topline->Button(
        -text => 'Set User',
        -command => sub {
            set_user(\$RefUser, $w);
            $RefUser = $user->userid;
            populate_shiftlog_widget();
        },
        -width => 10,
        -font => $opt{'font-var'},
    )->pack(
        -side => 'left',
    );

    $topline->Label(
        -text => 'Current telescope:',
        -font => $opt{'font-var'},
    )->pack(
        -side => 'left',
    );

    # Fill in the bottom line.
    $bottomline->Label(
        -text => 'Current UT:',
        -width => 15,
        -font => $opt{'font-var'},
    )->pack(
        -side => 'left',
    );

    my $RefUT = $ut;
    $bottomline->Entry(
        -textvariable => \$RefUT,
        -width => 20,
        -font => $opt{'font-var-bold'},
    )->pack(
        -side => 'left',
    );

    $bottomline->Button(
        -text => 'Set UT',
        -command => sub {
            set_UT(\$RefUT, $w);
        },
        -width => 10,
        -font => $opt{'font-var'},
    )->pack(
        -side => 'left',
    );

    # Create radiobuttons for the available telescopes
    my $tel = OMP::Config->getData('defaulttel');
    my @tels;
    if (ref($tel) ne 'ARRAY') {
        push @tels, $tel;
    }
    else {
        push @tels, @$tel;
    }
    my @telwid;
    my $newTel = $telescope;
    foreach my $ttel (@tels) {
        $bottomline->Radiobutton(
            -text => $ttel,
            -value => $ttel,
            -variable => \$newTel,
            -command => sub {
                set_telescope(\$ttel, $w);
            },
            -font => $opt{'font-var'},
        )->pack(
            -side => 'left',
        );
    }
}

sub set_user {
    my $RefUser = shift;
    my $w = shift;

    my $udb = OMP::UserDB->new(DB => $dbb);
    my $newUser = $udb->getUser($$RefUser);
    if (defined($newUser)) {
        $user = $newUser;
    }
    else {
        # we've got an error in the user ID
        require Tk::DialogBox;
        my $dbox = $w->DialogBox(-title => 'User ID error',);

        my $txt = $dbox->add(
            'Label',
            -text => 'User ID '
                . $$RefUser
                . " does not exist in database\nUser ID not changed.",
            -font => $opt{'font-var'},
        )->pack;

        my $but = $dbox->Show;
    }

    # We don't need to rescan just for changing the user.
}

sub set_UT {
    my $RefUT = shift;
    my $w = shift;

    my $newUT = $$RefUT;

    my $UTdate = OMP::DateTools->parse_date($newUT);

    unless (defined $UTdate) {
        # we've got an error in the date
        require Tk::DialogBox;
        my $dbox = $w->DialogBox(-title => 'Date error',);

        my $txt = $dbox->add(
            'Label',
            -text => "Error parsing date. Please ensure date\nis in YYYY-MM-DD format.",
        )->pack;

        my $but = $dbox->Show;
    }
    else {
        $ut = $UTdate->ymd;
        $utdisp = "Current UT date: $ut";

        full_rescan($ut, $telescope);

        $id->cancel if defined($id);
        if ($ut eq $currentut) {
            $id = $MainWindow->after($SCANFREQ, sub {
                full_rescan($ut, $telescope);
            });
        }
    }
}

sub set_telescope {
    my $RefTel = shift;
    my $tel = $$RefTel;

    # Only do the switch if the telescope they clicked on is different
    # from the currently displayed telescope.
    if ((uc $tel) ne (uc $telescope)) {
        $telescope = $tel;

        full_rescan($ut, $telescope);

        $id->cancel if defined($id);
        if ($ut eq $currentut) {
            $id = $MainWindow->after($SCANFREQ, sub {
                full_rescan($ut, $telescope);
            });
        }
    }
}

sub update_search_options {
    my ($date, $tel) = @_;

    my $today_ukirt = ($date eq $currentut) && (lc $tel eq 'ukirt');

    my ($disk, $db) = @opt{qw/disk database/};

    if ($today_ukirt || ($disk && $db) || ! ($disk || $db)) {
        $arcdb->search_files();
        $arcdb->search_db_skip_today();
        return;
    }

    return $arcdb->search_only_db() if $db;

    return $arcdb->search_only_files() if $disk;
}

sub grp_to_ref {
    my $grp = shift;

    %obs_ref = ();

    foreach my $obs ($grp->obs) {
        $obs_ref{$obs->runnr}{$obs->instrument}{STARTOBS} = $obs->startobs;
        $obs_ref{$obs->runnr}{$obs->instrument}{OBSID} = $obs->obsid;
    }
}


# Derive other fonts.
sub font_medium_to_bold_it {
    my ($ui, $med) = @_;

    my $font = font_parse($ui, $med);
    $font->configure('-weight' => 'bold', '-slant' => 'italic');
    return $font;
}

sub font_parse {
    my ($ui, $in) = @_;

    return $ui->fontCreate($ui->fontActual($in));
}

__END__

=head1 AUTHORS

Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>,
Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2015 East Asian Observatory.
Copyright (C) 2008-2013 Science and Technology Facilities Council.
Copyright (C) 2002-2007 Particle Physics and Astronomy Research Council.
All Rights Reserved.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful,but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 59 Temple
Place,Suite 330, Boston, MA  02111-1307, USA

=cut
