#!/local/perl/bin/perl -X

=head1 NAME

obslog - Review and comment on observations and timegaps for observing runs.

=head1 SYNOPSIS

  obslog
  obslog -ut 2002-12-10
  obslog -tel jcmt
  obslog -ut 2002-10-05 -tel ukirt
  obslog --help

=head1 DESCRIPTION

This program allows you to review and comment on observations and timegaps
for a night of observing. It allows for changing the status of an observation
(good, questionable, or bad) or the underlying reason for a timegap (unknown,
weather, or fault). It also supports multiple instruments via a tabbed window
interface.

=head1 OPTIONS

The following options are supported:

=over 4

=item B<-ut>

Override the UT date used for the report. By default the current date
is used.  The UT can be specified in either YYYY-MM-DD or YYYYMMDD format.
If the supplied date is not parseable, the current date will be used.

=item B<-tel>

Specify the telescope to use for the report. If the telescope can
be determined from the domain name it will be used automatically.
If the telescope can not be determined from the domain and this
option has not been specified a popup window will request the
telescope from the supplied list (assume the list contains more
than one telescope).

=item B<-version>

Report the version number.

=item B<-help>

A help message.

=item B<-man>

This manual page.

=back

=cut

use strict;

my ($VERSION, $BAR, $STATUS);

BEGIN {

# set up the intial Tk "status loading" window and load in the Tk modules

  use Tk;
  use Tk::Toplevel;
  use Tk::NoteBook;
  use Tk::ProgressBar;

  use Getopt::Long;

  use FindBin;
  use constant OMPLIB => "$FindBin::RealBin/..";
  use lib OMPLIB;

  use OMP::Constants;
  use OMP::General;
  use OMP::Config;
  use OMP::Error qw/ :try /;
  use OMP::CommentServer;

  use Time::Piece qw/ :override /;
  use Pod::Usage;

  use File::Spec;
  $ENV{'OMP_CFG_DIR'} = File::Spec->catdir( OMPLIB, "cfg" )
    unless exists $ENV{'OMP_CFG_DIR'};

}

# global variables
$| = 1;
my $MainWindow; # The Toplevel frame for obslog itself
my $obslog;  # refers to the object that holds the obslog information
my %obs; # keys are instruments, values are ObsGroup objects
my @shiftcomments; # Shiftlog comments.
my %notebook_contents; # All the notebook content windows
my %notebook_headers; # All the notebook header windows
my $notebook; # The widget that holds the tabbed windows.
my $shiftcommentText; # The widget that holds shiftlog comments.
my $lastinst; # The instrument of the most recent observation.
my $current_instrument; # The instrument currently displayed.
my $verbose; # Long or short output
my $id;

my ( %opt, $help, $man, $version );
my $status = GetOptions("ut=s" => \$opt{ut},
                        "tel=s" => \$opt{tel},
                        "help" => \$help,
                        "man" => \$man,
                        "version" => \$version,
                       );

pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

if( $version ) {
    my $id = '$Id$ ';
  print "obslog - Observation reporting tool\n";
  print " CVS revision: $id\n";
  exit;
}

my $ut = OMP::General->determine_utdate( $opt{ut} )->ymd;
my $currentut = OMP::General->today;
my $utdisp = "Current UT date: $ut";

my $user;

# Create a mainwindow that can be shared by everyone
# we have found that creating two MainWindow's sometimes leads
# to core dumps on some X servers
my $MW = new MainWindow;
$MW->withdraw; # hide it

my $telescope;
if(defined($opt{tel})) {
  $telescope = uc($opt{tel});
} else {
  my $w = $MW->Toplevel;
  $w->withdraw;
  $telescope = OMP::General->determine_tel( $w );
  $w->destroy if Exists($w);
  die "Unable to determine telescope. Exiting.\n" unless defined $telescope;
}

my $HEADERCOLOUR = 'midnightblue';
my $HEADERFONT = '-*-Courier-Medium-R-Normal--*-120-*-*-*-*-*-*';
my @CONTENTCOLOUR = qw/ black brown red /;
my $CONTENTFONT = '-*-Courier-Medium-R-Normal--*-120-*-*-*-*-*-*';
my $LISTFONT = '-*-Courier-Medium-R-Normal--*-120-*-*-*-*-*-*';
my $HIGHLIGHTBACKGROUND = '#CCCCFF';
my $BACKGROUND1 = '#D3D3D3';
my $BACKGROUND2 = '#DDDDDD';
my $BREAK = 92; # Number of characters to display for observation summary
                # before linewrapping.
my $SCANFREQ = 300000;  # scan every five minutes

$VERSION = sprintf "%d %03d", q$Revision$ =~ /(\d+)\.(\d+)/;

&display_loading_status();

$user = &get_userid();

&create_main_window();

&full_rescan($ut, $telescope);

MainLoop();

sub display_loading_status {
        my $w = $MW->Toplevel;
	$w->positionfrom('user');
	$w->geometry('+40+40');
	$w->title('Observation Log Utility');
	$w->resizable(0,0);
	$w->iconname('obslog');
	$STATUS = $w->Label(qw(-width 40 -anchor w -foreground blue),
											 -text => "Obslog $VERSION ...");
	$STATUS->grid(-row => 0, -column => 0, -sticky => 'w');
	$BAR = $w->ProgressBar(-from =>0, -to=>100,
													-width=>15, -length=>270,
													-blocks => 20, -anchor => 'w',
													-colors => [0, 'blue'],
													-relief => 'sunken',
													-borderwidth => 3,
													-troughcolor => 'grey',
												 )->grid(-sticky => 's');
	$w->update;

  use subs 'update_status';

  update_status 'Loading Obslog modules', 10, $w, $STATUS, $BAR;

  # Tk
  require Tk::Radiobutton;
  require Tk::Dialog;

  eval 'use OMP::ObslogDB';
  die "Error loading OMP::ObslogDB: $@" if $@;
  eval 'use OMP::ObsQuery';
  die "Error loading OMP::ObsQuery: $@" if $@;

  update_status 'Loading Archive modules', 25, $w, $STATUS, $BAR;

  eval 'use OMP::ArchiveDB';
  die "Error loading OMP::ArchiveDB: $@" if $@;
  eval 'use OMP::ArcQuery';
  die "Error loading OMP::ArcQuery: $@" if $@;

  update_status 'Loading Shiftlog modules', 50, $w, $STATUS, $BAR;

  eval 'use OMP::ShiftDB';
  die "Error loading OMP::ShiftDB: $@" if $@;
  eval 'use OMP::ShiftQuery';
  die "Error loading OMP::ShiftQuery: $@" if $@;

  update_status 'Loading Info modules', 60, $w, $STATUS, $BAR;

  eval 'use OMP::Info::Obs';
  die "Error loading OMP::Info::Obs: $@" if $@;
  eval 'use OMP::Info::Comment';
  die "Error loading OMP::Info::Comment: $@" if $@;

  update_status 'Loading Time::Piece modules', 65, $w, $STATUS, $BAR;

  eval 'use Time::Piece qw/ :override /';
  die "Error loading Time::Piece: $@" if $@;

  update_status 'Loading DBbackend modules', 75, $w, $STATUS, $BAR;

  eval 'use OMP::DBbackend';
  die "Error loading OMP::DBbackend: $@" if $@;
  eval 'use OMP::DBbackend::Archive';
  die "Error loading OMP::DBbackend::Archive: $@" if $@;

  update_status 'Complete', 99, $w, $STATUS, $BAR;
  sleep 1;
  $STATUS->destroy if Exists($STATUS);
  $BAR->destroy if Exists($BAR);
  $w->destroy if Exists($w);

}

sub get_userid {
   my $w = $MW->Toplevel;
   $w->withdraw;
   my $user = OMP::General->determine_user( $w );
   throw OMP::Error::Authentication("Unable to obtain valid user name")
     unless defined $user;
   $w->destroy if Exists($w);
   return $user;
}

sub create_main_window {
  $MainWindow = $MW->Toplevel;
  $MainWindow->title("OMP Observation Log Tool");
  $MainWindow->geometry('785x450');

# $mainFrame contains the entire frame.
  my $mainFrame = $MainWindow->Frame;

# $buttonbarFrame contains buttons that do various tasks
  my $buttonbarFrame = $mainFrame->Frame( -relief => 'groove',
                                          -borderwidth => 2
                                        );

# $buttonExit is the button that exits the program.
  my $buttonExit = $buttonbarFrame->Button( -text => 'EXIT',
                                            -command => 'exit'
                                          );

# $buttonRescan is the button that rescans for new observations and
# comments.
  my $buttonRescan = $buttonbarFrame->Button( -text => 'Rescan',
                                              -command => sub{ 
                                                full_rescan( $ut, $telescope );
                                              },
                                            );

# $buttonDumpText is the button that dumps the current listing to disk.
  my $buttonDumpText = $buttonbarFrame->Button( -text => 'Dump Text',
                                                -command => sub {
                                                  dump_to_disk();
                                                },
                                              );

# $buttonVerbose is the button that switches between short and long display.
  my $buttonVerbose = $buttonbarFrame->Checkbutton( -text => 'Short/Long Display',
                                                    -variable => \$verbose,
                                                    -command => sub {
                                                      redraw( undef,
                                                              $current_instrument,
                                                              $verbose );
                                                    },
                                                  );

# $labelUT is a label that tells the UT date
  my $labelUT = $buttonbarFrame->Label( -textvariable => \$utdisp,
                                      );

# $buttonHelp is the button that brings up a help dialogue.
#  my $buttonHelp = $buttonbarFrame->Button( -text => 'Help',
#                                            -command => \&help
#                                          );

# $notebook holds the pages for content
  my $nbFrame = $mainFrame->Frame( );
  $notebook = $nbFrame->NoteBook( );

  # Shiftlog frame
  my $shiftFrame = $mainFrame->Frame();
  create_shiftlog_widget( $shiftFrame );

  my $optionsFrame = $mainFrame->Frame();
  create_options_widget( $optionsFrame );

  $mainFrame->pack( -side => 'top',
                    -fill => 'both',
                    -expand => 1
                  );

  $buttonbarFrame->pack( -side => 'top',
                         -fill => 'x'
                       );

  $optionsFrame->pack( -side => 'bottom',
                       -fill => 'x',
                       -expand => 1,
                     );

  $shiftFrame->pack( -side => 'bottom',
		   -fill => 'x',
		   -expand => 1);

  $nbFrame->pack( -side => 'bottom',
                  -fill => 'both',
                  -expand => 1,
                );

  $buttonExit->pack( -side => 'left' );
  $buttonRescan->pack( -side => 'left' );
  $buttonDumpText->pack( -side => 'left' );
#  $buttonHelp->pack( -side => 'right' );
  $labelUT->pack( -side => 'right' );
  $buttonVerbose->pack( -side => 'right' );

  $notebook->pack( -side => 'top',
                   -fill => 'both',
                   -expand => 1,
                 );


}

sub update_status {
  die 'Wrong # args: Should be (text, barsize, frame,label, bar)'
    unless scalar(@_) == 5;
  my($status_text, $something, $w, $status, $bar) = @_;

  $status->configure(-text => "$status_text ...");
  $bar->value($something);
  $w->update;
} # end update_status

sub new_instrument {
  my $instrument = shift;
  my $obsgrp = shift;
  my $verbose = shift;

  if( exists( $notebook_contents{$instrument} ) ) {
    $notebook->delete( $instrument );
    delete($notebook_contents{$instrument});
    delete($notebook_headers{$instrument});
  }

  # Create a new page.
  my $nbPage = $notebook->add( $instrument,
                               -label => $instrument,
                               -raisecmd => \&page_raised,
                             );

  # Add a header to the page.
  my $nbPageFrame = $nbPage->Frame( );
  my $nbHeader = $nbPageFrame->Text( -wrap => 'none',
                                     -relief => 'flat',
                                     -foreground => 'midnightblue',
                                     -height => 2,
                                     -font => $LISTFONT,
                                     -takefocus => 0
                                   );

  my $nbContent = $nbPageFrame->Scrolled('Text',
                                         -wrap => 'word',
                                         -scrollbars => 'oe',
                                         -height => 100,
                                        );

  $notebook_contents{$instrument} = $nbContent;
  $notebook_headers{$instrument} = $nbHeader;
  # Pack the notebook.
  $nbPageFrame->pack( -side => 'bottom',
                      -fill => 'x',
                      -expand => 1,
                    );
  $nbHeader->pack( -side => 'top',
                   -fill => 'x',
                 );
  $nbContent->pack( -expand => 1,
                    -fill => 'both'
                  );

  # Fill it with information from the ObsGroup
  my $header_printed = 0;

  $nbContent->configure( -state => 'normal' );
  $nbContent->delete('0.0','end');

  my $counter = 0;

  if( defined( $obsgrp ) ) {
    foreach my $obs( $obsgrp->obs ) {
      my %nightlog = $obs->nightlog(display => 'long',
                                  comments => 1, );
      my @comments = $obs->comments;
      my $status = 0;
      if ( defined($comments[($#comments)]) ) {
        $status = $comments[($#comments)]->status;
      }

      # Draw the header, if necessary.
      if( !$header_printed && exists($nightlog{'_STRING_HEADER'})) {
        $nbHeader->configure( -state => 'normal' );
        $nbHeader->delete('0.0','end');

        if( $verbose && exists($nightlog{'_STRING_HEADER_LONG'})) {
          $nbHeader->insert('end', $nightlog{'_STRING_HEADER_LONG'});
        } else {
          $nbHeader->insert('end', $nightlog{'_STRING_HEADER'});
        }

        # Clean up.
        $nbHeader->configure( -state => 'disabled' );
        $header_printed = 1;
      }

      # Take a local copy of the index for callbacks
      my $index = $counter;

      # Generate the tag name based on the index.
      my $otag = "o" . $index;

      # Get the reference position
      my $start = $nbContent->index('insert');

      # Insert the line
      if( $verbose && exists($nightlog{'_STRING_LONG'}) ) {
        $nbContent->insert('end', $nightlog{'_STRING_LONG'} . "\n");
      } else {
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
      if( $counter % 2 ) {
        $bgcolour = $BACKGROUND1;
      } else {
        $bgcolour = $BACKGROUND2;
      }

      if($counter % 2) {
        $nbContent->tag('configure', $otag,
                        -foreground => $CONTENTCOLOUR[$status],
                        -background => $bgcolour,
                       );
      } else {
        $nbContent->tag('configure', $otag,
                        -foreground => $CONTENTCOLOUR[$status],
                        -background => $bgcolour,
                       );
      }

      # Bind the tag to double-left-click
      $nbContent->tag('bind', $otag, '<Double-Button-1>' =>
                      [\&RaiseComment, $obs, $index] );

      # Do some funky mouse-over colour changing.
      $nbContent->tag('bind', $otag, '<Any-Enter>' =>
                      sub { shift->tag('configure', $otag,
                                       -background => $HIGHLIGHTBACKGROUND,
                                       -foreground => $CONTENTCOLOUR[$status],
                                       qw/ -relief raised
                                           -borderwidth 1 /); } );

      $nbContent->tag('bind', $otag, '<Any-Leave>' =>
                      sub { shift->tag('configure', $otag,
                                       -background => $bgcolour,
                                       -foreground => $CONTENTCOLOUR[$status],
                                       qw/ -relief flat /); } );

      # And increment the counter.
      $counter++;
    }
  }

  # Bind the mousewheel.
  &BindMouseWheel($nbContent);

  # And disable the text widget.
  $nbContent->configure( -state => 'disable' );

  $nbContent->see('end');

  $notebook->raise( $instrument );
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
    delete($notebook_contents{$inst});
  }

  foreach my $inst (keys %obs) {
    new_instrument( $inst, $obs{$inst}, $verbose );
  }

  if( defined( $current ) && exists( $notebook_contents{$current}) ) {
    $notebook->raise($current);
  } elsif( defined( $lastinst ) && exists( $notebook_contents{$lastinst}) ) {
    $notebook->raise( $lastinst );
  }

  &populate_shiftlog_widget();

}

sub rescan {
  my $ut = shift;
  my $telescope = shift;

  try {
    my $grp = new OMP::Info::ObsGroup( telescope => $telescope,
                                       date => $ut,
                                     );
    if(!$grp->numobs) {
      throw OMP::Error("There are no observations available for this night.");
    }
    my $gaplength = OMP::Config->getData( 'timegap' );
    $grp->locate_timegaps( $gaplength );

    %obs = $grp->groupby('instrument');

    my @sorted_obs = sort {
      $b->startobs <=> $a->startobs
    } $grp->obs;

    $lastinst = $sorted_obs[0]->instrument;

  }
  catch OMP::Error with {
    my $Error = shift;
    require Tk::DialogBox;
    new_instrument( "NONE", undef, 1 );
    my $dbox = $MainWindow->DialogBox( -title => "Error",
                                       -buttons => ["OK"],
                                     );

    my $label = $dbox->add( 'Label',
                            -text => "Error: " . $Error->{-text} )->pack;
    my $but = $dbox->Show;

    # Add logging.
    OMP::General->log_message( "OMP::Error in obslog.pl/rescan:\n text: " . $Error->{'-text'} . "\n file: " . $Error->{'-file'} . "\n line: " . $Error->{'-line'});

    undef %obs;
  }
  otherwise {
    my $Error = shift;
    require Tk::DialogBox;
    new_instrument( "NONE", undef, 1 );
    my $dbox = $MainWindow->DialogBox( -title => "Error",
                                       -buttons => ["OK"],
                                     );

    my $label = $dbox->add( 'Label',
                            -text => "Error: " . $Error->{-text} )->pack;
    my $but = $dbox->Show;

    # Add logging.
    OMP::General->log_message( "General error in obslog.pl/rescan:\n text: " . $Error->{'-text'} . "\n file: " . $Error->{'-file'} . "\n line: " . $Error->{'-line'});

  };

  &update_shiftlog_comments;

  $id->cancel unless !defined($id);
  if( $ut eq $currentut ) {
    $id = $MainWindow->after($SCANFREQ, sub { full_rescan($ut, $telescope); });
  };

}

# Perform a full rescan/redraw sequence.
sub full_rescan {
  my $ut = shift;
  my $telescope = shift;

  rescan( $ut, $telescope );
  redraw( undef, $current_instrument, $verbose );

}

sub dump_to_disk {

  my $current = $notebook->raised;
  my $contentHeader = $notebook_headers{$current};
  my $contentBody = $notebook_contents{$current};
  my $header = $contentHeader->get('0.0', 'end');
  my $text = $contentBody->get('0.0', 'end');
  my $filename = "$ut-$current.log";
  open( FILE, ">" . $filename ) or return; # just a quickie, need a better way to handle this
  print FILE $header;
  print FILE $text;
  close FILE;
  my $dbox = $MainWindow->DialogBox( -title => "File Saved",
                                     -buttons => ["OK"],
                                   );
  my $label = $dbox->add( 'Label',
                          -text => "Data has been saved in " . $filename )->pack;
  my $but = $dbox->Show;
}

# Display the comment window and allow for editing, etc, etc, etc.
sub RaiseComment {

  my $widget = shift;
  my $obs = shift;
  my $index = shift;

#  my $obs = \$obsref;

  my $status;
  my $scrolledComment;

  $id->cancel unless !defined $id;

  my @comments = $obs->comments;
#  if(defined($comments[$#comments])) {
#    $status = $comments[$#comments]->status;
#  } else {
#    $status = OMP__OBS_GOOD;
#  }
  $status = $obs->status;

  my $CommentWindow = MainWindow->new;
  $CommentWindow->title("OMP Observation Log Tool Commenting System");
  $CommentWindow->geometry('760x300');

  # $commentFrame contains the entire frame.
  my $commentFrame = $CommentWindow->Frame->pack( -side => 'top',
                                                  -fill => 'both',
                                                  -expand => 1,
                                                );

  my $contentFrame = $commentFrame->Frame->pack( -side => 'top',
                                                 -fill => 'x',
                                               );

  my $entryFrame = $commentFrame->Frame( -relief => 'groove' )->pack( -side => 'top',
                                                                      -fill => 'x',
                                                                    );

  my $buttonFrame = $commentFrame->Frame->pack( -side => 'bottom',
                                                -fill => 'x',
                                              );

  # $commentHeader contains the header information
  my $contentHeader = $contentFrame->Text( -wrap => 'none',
                                           -relief => 'flat',
                                           -foreground => $HEADERCOLOUR,
                                           -height => 1,
                                           -font => $HEADERFONT,
                                           -takefocus => 0,
                                           -state => 'disabled',
                                         )->pack( -side => 'top',
                                                  -fill => 'x',
                                                );

  # $contentObs contains the observation info
  my $contentObs = $contentFrame->Scrolled( 'Text',
                                            -wrap => 'word',
                                            -relief => 'flat',
                                            -height => 5,
                                            -font => $CONTENTFONT,
                                            -takefocus => 0,
                                            -state => 'disabled',
                                            -scrollbars => 'oe',
                                          )->pack( -side => 'top',
                                                   -fill => 'x',
                                                 );

  # $scrolledComment is the text area that will be used for comment entry.
  $scrolledComment = $entryFrame->Scrolled( 'Text',
                                            -wrap => 'word',
                                            -height => 10,
                                            -scrollbars => 'oe',
                                          )->pack( -side => 'bottom',
                                                   -expand => 1,
                                                   -fill => 'x',
                                                 );

  my $radioFrame = $entryFrame->Frame->pack( -side => 'top',
                                             -fill => 'x',
                                           );

  # $textStatus displays the string "Status:"
  my $textStatus = $radioFrame->Label( -text => 'Status: ' )->pack( -side => 'left',
                                                                  );

  if( UNIVERSAL::isa( $obs, "OMP::Info::Obs::TimeGap" ) ) {
    my $radioWeather = $radioFrame->Radiobutton( -text => 'weather',
                                                 -value => OMP__TIMEGAP_WEATHER,
                                                 -variable => \$status,
                                               )->pack( -side => 'left',
                                                      );
    my $radioInstrument = $radioFrame->Radiobutton( -text => 'instrument',
                                                    -value => OMP__TIMEGAP_INSTRUMENT,
                                                    -variable => \$status,
                                                  )->pack( -side => 'left',
                                                         );
    my $radioFault = $radioFrame->Radiobutton( -text => 'fault',
                                               -value => OMP__TIMEGAP_FAULT,
                                               -variable => \$status,
                                             )->pack( -side => 'left',
                                                    );
    my $radioLastProject = $radioFrame->Radiobutton( -text => 'last proj.',
                                                     -value => OMP__TIMEGAP_PREV_PROJECT,
                                                     -variable => \$status,
                                                   )->pack( -side => 'left',
                                                          );
    my $radioNextProject = $radioFrame->Radiobutton( -text => 'next proj.',
                                                     -value => OMP__TIMEGAP_NEXT_PROJECT,
                                                     -variable => \$status,
                                                   )->pack( -side => 'left',
                                                          );

    # Second row of buttons...
    my $radioFrame2 = $entryFrame->Frame->pack( -side => 'top',
                                                -fill => 'x',
                                              );

    my $textStatus2 = $radioFrame2->Label( -text => '            ' )->pack( -side => 'left',
                                                                          );
    my $radioNotDriver = $radioFrame2->Radiobutton( -text => 'observer not driver',
                                                    -value => OMP__TIMEGAP_NOT_DRIVER,
                                                    -variable => \$status,
                                                  )->pack( -side => 'left',
                                                         );
    my $radioScheduled = $radioFrame2->Radiobutton( -text => 'scheduled downtime',
                                                    -value => OMP__TIMEGAP_SCHEDULED,
                                                    -variable => \$status,
                                                  )->pack( -side => 'left',
                                                         );
    my $radioOverhead = $radioFrame2->Radiobutton( -text => 'queue overhead',
                                                   -value => OMP__TIMEGAP_QUEUE_OVERHEAD,
                                                   -variable => \$status,
                                                 )->pack( -side => 'left',
                                                        );
    my $radioLogistics = $radioFrame2->Radiobutton( -text => 'logistics',
                                                    -value => OMP__TIMEGAP_LOGISTICS,
                                                    -variable => \$status,
                                                  )->pack( -side => 'left',
                                                         );
    my $radioUnknown = $radioFrame->Radiobutton( -text => 'unknown',
                                                 -value => OMP__TIMEGAP_UNKNOWN,
                                                 -variable => \$status,
                                               )->pack( -side => 'left',
                                                      );

  } else {
    my $radioGood = $radioFrame->Radiobutton( -text => 'good',
                                              -value => OMP__OBS_GOOD,
                                              -variable => \$status,
                                            )->pack( -side => 'left',
                                                   );
    my $radioBad = $radioFrame->Radiobutton( -text => 'bad',
                                             -value => OMP__OBS_BAD,
                                             -variable => \$status,
                                           )->pack( -side => 'left',
                                                  );
    my $radioQuestionable = $radioFrame->Radiobutton( -text => 'questionable',
                                                      -value => OMP__OBS_QUESTIONABLE,
                                                      -variable => \$status,
                                                    )->pack( -side => 'left',
                                                           );

  }

  # $textUser displays the current user id.
  my $textUser = $radioFrame->Label( -text => "Current user: " . $user->userid )->pack( -side => 'left',
                                                                                      );

  # $buttonSave is the button that allows the user to save the comment
  # to the database.
  my $buttonSave = $buttonFrame->Button( -text => 'Save',
                                         -command => sub {
                                           my $t = $scrolledComment->get( '0.0', 'end' );
                                           SaveComment( $status,
                                                        $t,
                                                        $user,
                                                        $obs,
                                                        $index );
                                           redraw( undef, uc($obs->instrument), $verbose );
                                           if(defined($id)) { $id->cancel; }
                                           if( $currentut eq $ut ) {
                                             $id = $MainWindow->after($SCANFREQ, sub { full_rescan($ut, $telescope); });
                                           };
                                           CloseWindow( $CommentWindow );
                                         },
                                       )->pack( -side => 'left',
                                                -anchor => 'n',
                                              );

  # $buttonCancel is the button that closes the window without saving
  # any changes.
  my $buttonCancel = $buttonFrame->Button( -text => 'Cancel',
                                           -command => sub {
                                             if(defined($id)) { $id->cancel; }
                                             if( $ut eq $currentut ) {
                                               $id = $MainWindow->after($SCANFREQ, sub { full_rescan($ut, $telescope); });
                                             };
                                             CloseWindow( $CommentWindow );
                                           },
                                         )->pack( -side => 'left',
                                                  -anchor => 'n',
                                                );

  if( uc( $telescope ) eq 'UKIRT' ) {
    my $buttonGuiding = $buttonFrame->Button( -text => 'Lost Guiding',
                                              -command => sub {
                                                my $t = "Lost guiding, repeating observation.";
                                                my $status = OMP__OBS_BAD;
                                                SaveComment( $status,
                                                             $t,
                                                             $user,
                                                             $obs,
                                                             $index );
                                                redraw( undef, uc( $obs->instrument ), $verbose );
                                                if( defined( $id ) ) { $id->cancel; }
                                                if( $currentut eq $ut ) {
                                                  $id = $MainWindow->after($SCANFREQ, sub { full_rescan( $ut, $telescope ); });
                                                };
                                                CloseWindow( $CommentWindow );
                                              },
                                            )->pack( -side => 'right',
                                                     -anchor => 'n',
                                                   );
    my $buttonZeroCountdown = $buttonFrame->Button( -text => 'Zero Countdown',
                                                    -command => sub {
                                                      my $t = "Zero countdown problem, repeating group.";
                                                      my $status = OMP__OBS_BAD;
                                                      SaveComment( $status,
                                                                   $t,
                                                                   $user,
                                                                   $obs,
                                                                   $index );
                                                      redraw( undef, uc( $obs->instrument ), $verbose );
                                                      if( defined( $id ) ) { $id->cancel; }
                                                      if( $currentut eq $ut ) {
                                                        $id = $MainWindow->after($SCANFREQ, sub { full_rescan( $ut, $telescope ); });
                                                      };
                                                      CloseWindow( $CommentWindow );
                                                    },
                                                  )->pack( -side => 'right',
                                                           -anchor => 'n',
                                                         );

  }

  # Get the observation information.
  my %nightlog = $obs->nightlog(display => 'long',
                                comments => 1, );

  # Insert the header information.
  $contentHeader->configure( -state => 'normal' );
  $contentHeader->delete( '0.0', 'end' );
  $contentHeader->insert( 'end', $nightlog{'_STRING_HEADER'} );
  $contentHeader->configure( -state => 'disabled' );

  # Insert the observation information.
  $contentObs->configure( -state => 'normal' );
  $contentObs->delete( '0.0', 'end' );
  $contentObs->insert( 'end', $nightlog{'_STRING'} );
  $contentObs->configure( -state => 'disabled' );

  # Get a comment for this observation and user (if one exists)
  # and pre-fill the entry box.
  foreach my $comment ( $obs->comments ) {
    if($comment->author->userid eq $user->userid) {
      $scrolledComment->delete( '0.0', 'end' );
      $scrolledComment->insert( 'end', $comment->text );
      last;
    }
  }

}

sub help { }

sub SaveComment {
  my $status = shift;
  my $text = shift;
  my $user = shift;
  my $obs = shift;
  my $index = shift;

  chomp $text;

  # Add the comment to the database
  my $comment = new OMP::Info::Comment( author => $user,
                                        text => $text,
                                        status => $status );

  my $odb = new OMP::ObslogDB( DB => new OMP::DBbackend );
  $odb->addComment( $comment, $obs );

  # Add the comment to the observation.
  my @obsarray;
  push @obsarray, $obs;
  $odb->updateObsComment( \@obsarray );
  $obs = $obsarray[0];

  # And let's not forget to update the status of the observation.
  $obs->status( $status );

}

sub CloseWindow {
  my $window = shift;
  $window->destroy if Exists($window);
}

sub InvalidUTDate {
  my $string = shift;
  print "Invalid UT date: $string\n";
}

sub BindMouseWheel {

# Mousewheel binding from Mastering Perl/Tk, pp 370-371.

  my($w) = @_;

  if ($^O eq 'MSWin32') {
    $w->bind('<MouseWheel>' =>
             [ sub { $_[0]->yview('scroll', -($_[1] / 120) * 3, 'units') },
                 Ev('D') ]
            );
  } else {
    $w->bind('<4>' => sub {
               $_[0]->yview('scroll', -3, 'units') unless $Tk::strictMotif;
             });
    $w->bind('<5>' => sub {
               $_[0]->yview('scroll', +3, 'units') unless $Tk::strictMotif;
             });
  }
} # end BindMouseWheel


################### S H I F T  L O G ############################

# ShiftLog

sub create_shiftlog_widget {
  my $w = shift;

  # Create a holder frame
  my $shiftlog = $w->Frame()->pack( -side => 'top',
                                    -expand => 1,
                                    -fill => 'x' );

  my $topbar = $shiftlog->Frame->pack( -side => 'top',
                                       -expand => 1,
                                       -fill => 'x' );

  # Create the text widget so that we can store the reference
  $shiftcommentText = $shiftlog->Scrolled( 'Text',
                                           -height => 6,
                                           -scrollbars => 'oe',
                                         )->pack( -side => 'bottom',
                                                  -expand => 1,
                                                  -fill => 'x');

  # This variable controls whether we are in Local time or UT
  # Options are "LocalTime" and "UT"
  my $TZ = "LocalTime";

  # A label.
  $topbar->Label( -text => "Shift Comments for $ut:" )->pack( -side => 'left' );

  # Button to add a new comment.
  $topbar->Button( -text => 'Add New Shift Comment',
                   -command => sub { raise_shift_comment() },
                 )->pack( -side => 'right' );

  &BindMouseWheel( $shiftcommentText );

  $shiftcommentText->configure( -state => 'disable' );

}

sub update_shiftlog_comments {

  try {
    @shiftcomments = OMP::CommentServer->getShiftLog( $ut, $telescope );
  }
  catch OMP::Error with {
    my $Error = shift;
    require Tk::DialogBox;
    my $dbox = $MainWindow->DialogBox( -title => "Error",
                                       -buttons => ["OK"],
                                     );
    my $label = $dbox->add( 'Label',
                            -text => "Error: " . $Error->{-text} )->pack;
    my $but = $dbox->Show;

    # Add logging.
    OMP::General->log_message( "General error in obslog.pl/rescan:\n text: " . $Error->{'-text'} . "\n file: " . $Error->{'-file'} . "\n line: " . $Error->{'-line'});

    undef @shiftcomments;

  }
  otherwise {
    my $Error = shift;
    require Tk::DialogBox;

    my $dbox = $MainWindow->DialogBox( -title => "Error",
                                       -buttons => ["OK"],
                                     );

    my $label = $dbox->add( 'Label',
                            -text => "Error: " . $Error->{-text} )->pack;
    my $but = $dbox->Show;

    # Add logging.
    OMP::General->log_message( "General error in obslog.pl/rescan:\n text: " . $Error->{'-text'} . "\n file: " . $Error->{'-file'} . "\n line: " . $Error->{'-line'});

  };

}

sub populate_shiftlog_widget {

  # Update list of comments.
  &update_shiftlog_comments;

  # Clear and enable the widget.
  $shiftcommentText->configure( -state => 'normal' );
  $shiftcommentText->delete( "1.0", 'end' );
  my $tagnames = $shiftcommentText->tagNames();
  foreach my $tagname ( @$tagnames ) {
    next if $tagname eq 'sel';
    $shiftcommentText->tagDelete( $tagname );
  }

  # Set up a counter for tag names.
  my $counter = 0;

  # Loop over comments
  for my $c (@shiftcomments) {

    # Take a local copy of the index for callbacks.
    my $index = $counter;

    # Generate the tag name based on the index.
    my $ctag = "c" . $index;

    #Get the reference position.
    my $start = $shiftcommentText->index('insert');

    my $date = $c->date;
    my $username = $c->author->name;
    my $text = OMP::General->html_to_plain( $c->text );

    my $insertstring = $date->datetime . "UT by $username\n$text\n";

    # Insert the string.
    $shiftcommentText->insert('end', $insertstring );

    # Remove all tags at this position.
    foreach my $tag ( $shiftcommentText->tag('names', $start ) ) {
      $shiftcommentText->tag('delete', $tag, $start, 'insert' );
    }

    # Create a new tag.
    $shiftcommentText->tag( 'add', $ctag, $start, 'insert' );

    # Configure the new tag.
    my $bgcolour;
    if( $counter % 2 ) {
      $bgcolour = $BACKGROUND1;
    } else {
      $bgcolour = $BACKGROUND2;
    }
    $shiftcommentText->tag( 'configure', $ctag,
                 -background => $bgcolour,
               );

    if( uc( $user->userid ) eq uc( $c->author->userid ) ) {

      # Bind the tag to double-left-click.
      $shiftcommentText->tag( 'bind', $ctag,
                              '<Double-Button-1>' => [\&raise_shift_comment, $c, $index] );

      # Do some funky mouse-over colour changing.
      $shiftcommentText->tag('bind', $ctag, '<Any-Enter>' =>
                             sub { shift->tag('configure', $ctag,
                                              -background => $HIGHLIGHTBACKGROUND,
                                              -foreground => $CONTENTCOLOUR[0],
                                              qw/ -relief raised
                                                  -borderwidth 1 /); } );

      $shiftcommentText->tag('bind', $ctag, '<Any-Leave>' =>
                             sub { shift->tag('configure', $ctag,
                                              -background => $bgcolour,
                                              -foreground => $CONTENTCOLOUR[0],
                                              qw/ -relief flat /); } );

    }

    # Increment the counter.
    $counter++;
  }

  $shiftcommentText->configure( -state => 'disable' );

}

sub save_shift_comment {
  my $w = shift;
  my $commenttext = shift;
  my $TZ = shift;
  my $time = shift;

  return unless $commenttext =~ /\w/;

  # Use current date if the field is blank
  my $date;

  if (defined $time && $time =~ /\d/) {
    # Now need to parse the time (either as UT or local time)
    my $islocal = ( $TZ eq 'UT' ? 0 : 1 );
    $date = OMP::General->parse_date( $time, $islocal );

    # if it did not parse tell people
    if (!defined $date) {
      # popup the error and return
      require Tk::Dialog;
      my $dialog = $w->Dialog( -text => "Error parsing the date string. Please fix. Should be YYYY-MM-DDTHH:MM:SS",
			       -title => "Error parsing time",
			       -buttons => ["Abort"],
			       -bitmap => 'error',
			     );

      $dialog->Show;
      return;
    }
  } else {
    $date = gmtime();
  }

  # Now create the comment
  my $comment = new OMP::Info::Comment( author => $user,
                                        date => $date,
                                        text => $commenttext );

  # And add it to the system
  OMP::CommentServer->addShiftLog( $comment, $telescope );

}

sub raise_shift_comment {
  my $widget = shift;
  my $comment = shift;
  my $index = shift;

  my $TZ = "LocalTime";
  my $RefTime;

  my $ShiftCommentWindow = MainWindow->new;
  $ShiftCommentWindow->title( "OMP Shift Log Tool Commenting System");
  $ShiftCommentWindow->geometry('760x190');

  my $commentFrame = $ShiftCommentWindow->Frame->pack( -side => 'top',
                                                       -fill => 'both',
                                                       -expand => 1,
                                                     );

  my $contentFrame = $commentFrame->Frame->pack( -side => 'top',
                                                 -fill => 'x',
                                               );

  my $entryFrame = $commentFrame->Frame( -relief => 'groove' )->pack( -side => 'top',
                                                                      -fill => 'x',
                                                                    );

  my $buttonFrame = $commentFrame->Frame->pack( -side => 'bottom',
                                                -fill => 'x',
                                              );

  my $scrolledComment = $entryFrame->Scrolled( 'Text',
                                               -wrap => 'word',
                                               -height => 10,
                                               -scrollbars => 'oe',
                                               -takefocus => 1,
                                             )->pack( -side => 'bottom',
                                                      -expand => 1,
                                                      -fill => 'x',
                                                    );

  my $infoText = $entryFrame->Label( -text => "Comment from " . $user->name . ":" )->pack( -side => 'left' );

  my $buttonSave = $buttonFrame->Button( -text => 'Save',
                                         -command => sub {
                                           my $t = $scrolledComment->get('0.0',
                                                                         'end',
                                                                        );
                                           save_shift_comment( $entryFrame, $t, $TZ, $RefTime );
                                           &populate_shiftlog_widget();
                                           CloseWindow( $ShiftCommentWindow );
                                         },
                                       )->pack( -side => 'left',
                                                -anchor => 'n',
                                              );

  my $buttonCancel = $buttonFrame->Button( -text => 'Cancel',
                                           -command => sub {
                                             CloseWindow( $ShiftCommentWindow );
                                           },
                                         )->pack( -side => 'left',
                                                  -anchor => 'n',
                                                );

  # Time section
  my $buttonTZLocal = $buttonFrame->Radiobutton( -variable => \$TZ,
                                                 -text => "Local Time",
                                                 -value => 'LocalTime',
                                               )->pack( -side => 'right' );
  my $buttonTZUT = $buttonFrame->Radiobutton( -variable => \$TZ,
                                              -text => "UT",
                                              -value => 'UT',
                                            )->pack( -side => 'right' );
  my $timeText = $buttonFrame->Entry( -textvariable => \$RefTime,
                                      -width => 20 )->pack( -side => 'right' );
  $buttonFrame->Label( -text => "Comment time: " )->pack( -side => 'right' );

  # Need to populate the time field
  # We use closures rather than array ref for passing arguments
  # so that we do not need to pass in references for all arguments
  &update_shift_comment_time($TZ, \$RefTime);
  my $repeatid = $ShiftCommentWindow->repeat(1000, sub { update_shift_comment_time($TZ,\$RefTime) } );

  if( defined( $comment ) ) {

    # Insert the comment text into the box.
    $scrolledComment->insert( 'end', OMP::General->html_to_plain( $comment->text ) );

    # And the comment time (which is always UT) into the box. Disable
    # the update and don't let the user update the time either.
    $TZ = "UT";
    $RefTime = $comment->date->ymd . "T" . $comment->date->hms;
    $repeatid->cancel;
    $buttonTZLocal->configure( -state => 'disable' );
    $buttonTZUT->configure( -state => 'disable' );
    $timeText->configure( -state => 'disable' );
  }

  $scrolledComment->focus();

}

# Need two lexicals to allow us to track previous values
my $PrevTime;
my $PrevTZ;

sub update_shift_comment_time {
  my $TZ = shift;
  my $RefTimeRef = shift;
  my $RefTime = $$RefTimeRef;

  # If we have switched time zones, we should also synch prevtime with
  # reftime
  $PrevTime = $RefTime if (defined $PrevTZ && $TZ ne $PrevTZ);

  # Need to do a check to make sure we do not override a time
  # that has been edited
  return unless (!defined $PrevTime ||
		 (defined $PrevTime && $RefTime eq $PrevTime));

  # Get the current time
  my $time;
  if ($TZ eq 'UT') {
    $time = gmtime;
  } else {
    $time = localtime;
  }

  # Store the new values for later reference
  $PrevTZ = $TZ;
  $$RefTimeRef = $time->datetime;
  $PrevTime = $$RefTimeRef;
}

######################### O P T I O N S #######################

sub create_options_widget {
  my $w = shift;

  # Create a holder frame
  my $options = $w->Frame()->pack( -side => 'top',
                                   -expand => 1,
                                   -fill => 'x',
                                 );

  my $topline = $options->Frame->pack( -side => 'top',
                                        -expand => 1,
                                        -fill => 'x',
                                      );

  my $bottomline = $options->Frame->pack( -side => 'bottom',
                                           -expand => 1,
                                           -fill => 'x',
                                         );

  # Fill in the top line.
  $topline->Label( -text => 'Current user:',
                   -width => 15,
                 )->pack( -side => 'left' );

  my $RefUser = $user->userid;
  $topline->Entry( -textvariable => \$RefUser,
                   -width => 20,
                 )->pack( -side => 'left' );

  $topline->Button( -text => 'Set User',
                    -command => sub { set_user( \$RefUser, $w );
                                      $RefUser = $user->userid;
                                      populate_shiftlog_widget();
 },
                    -width => 10,
                  )->pack( -side => 'left' );

  $topline->Label( -text => 'Current telescope:',
                 )->pack( -side => 'left',
                        );

  # Fill in the bottom line.
  $bottomline->Label( -text => 'Current UT:',
                      -width => 15,
                    )->pack( -side => 'left' );

  my $RefUT = $ut;
  $bottomline->Entry( -textvariable => \$RefUT,
                      -width => 20,
                    )->pack( -side => 'left' );

  $bottomline->Button( -text => 'Set UT',
                       -command => sub { set_UT( \$RefUT, $w ) },
                       -width => 10,
                     )->pack( -side => 'left' );

  # Create radiobuttons for the available telescopes
  my $tel = OMP::Config->getData( 'defaulttel' );
  my @tels;
  if(ref($tel) ne "ARRAY") {
    push @tels, $tel;
  } else {
    push @tels, @$tel;
  }
  my @telwid;
  my $newTel = $telescope;
  foreach my $ttel (@tels) {
    $bottomline->Radiobutton( -text => $ttel,
                              -value => $ttel,
                              -variable => \$newTel,
                              -command => sub { set_telescope( \$ttel, $w ) },
                            )->pack( -side => 'left' );
  }

}

sub set_user {
  my $RefUser = shift;
  my $w = shift;

  my $udb = new OMP::UserDB( DB => new OMP::DBbackend );
  my $newUser = $udb->getUser( $$RefUser );
  if( defined( $newUser ) ) {
    $user = $newUser;
  } else {
    # we've got an error in the user ID
    require Tk::DialogBox;
    my $dbox = $w->DialogBox( -title => "User ID error",
                            );

    my $txt = $dbox->add('Label',
                         -text => "User ID " . $$RefUser . " does not exist in database\nUser ID not changed.",
                        )->pack;
    my $but = $dbox->Show;
  }

  # We don't need to rescan just for changing the user.
}

sub set_UT {
  my $RefUT = shift;
  my $w = shift;

  my $newUT = $$RefUT;

  my $UTdate = OMP::General->parse_date( $newUT );

  if(!defined($UTdate)) {
    # we've got an error in the date
    require Tk::DialogBox;
    my $dbox = $w->DialogBox( -title => "Date error",
                            );

    my $txt = $dbox->add('Label',
                         -text => "Error parsing date. Please ensure date\nis in YYYY-MM-DD format.",
                        )->pack;
    my $but = $dbox->Show;
  } else {

    $ut = $UTdate->ymd;
    $utdisp = "Current UT date: $ut";

    full_rescan($ut, $telescope);

    $id->cancel unless !defined($id);
    if( $ut eq $currentut ) {
      $id = $MainWindow->after($SCANFREQ, sub { full_rescan($ut, $telescope); });
    };
  }

}

sub set_telescope {
  my $RefTel = shift;
  my $tel = $$RefTel;

  # Only do the switch if the telescope they clicked on is different
  # from the currently displayed telescope.
  if( uc($tel) ne uc($telescope) ) {

    $telescope = $tel;

    full_rescan( $ut, $telescope );

    $id->cancel unless !defined($id);
    if( $ut eq $currentut ) {
      $id = $MainWindow->after($SCANFREQ, sub { full_rescan($ut, $telescope); });
    };

  }

}

=head1 AUTHORS

Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>,
Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002-2005 Particle Physics and Astronomy Research Council.
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
