#!/local/bin/perl -X

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
is used.

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

my ($MW, $VERSION, $BAR, $STATUS);

BEGIN {

# set up the intial Tk "status loading" window and load in the Tk modules

  use Tk;
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
my $MainWindow;
my $obslog;  # refers to the object that holds the obslog information
my %obs; # keys are instruments, values are ObsGroup objects
my %notebook_contents; # All the notebook content windows
my %notebook_headers; # All the notebook header windows
my $notebook; # The widget that holds the tabbed windows.
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

my $telescope;
if(defined($opt{tel})) {
  $telescope = uc($opt{tel});
} else {
  my $w = new MainWindow;
  $w->withdraw;
  $telescope = OMP::General->determine_tel( $w );
  $w->destroy;
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
	$MW = new MainWindow();
	$MW->positionfrom('user');
	$MW->geometry('+40+40');
	$MW->title('Observation Log Utility');
	$MW->resizable(0,0);
	$MW->iconname('obslog');
	$STATUS = $MW->Label(qw(-width 40 -anchor w -foreground blue),
											 -text => "Obslog $VERSION ...");
	$STATUS->grid(-row => 0, -column => 0, -sticky => 'w');
	$BAR = $MW->ProgressBar(-from =>0, -to=>100,
													-width=>15, -length=>270,
													-blocks => 20, -anchor => 'w',
													-colors => [0, 'blue'],
													-relief => 'sunken',
													-borderwidth => 3,
													-troughcolor => 'grey',
												 )->grid(-sticky => 's');
	$MW->update;

  use subs 'update_status';

  update_status 'Loading Obslog modules', 10, $MW, $STATUS, $BAR;

  # Tk
  require Tk::Radiobutton;
  require Tk::Dialog;

  eval 'use OMP::ObslogDB';
  die "Error loading OMP::ObslogDB: $@" if $@;
  eval 'use OMP::ObsQuery';
  die "Error loading OMP::ObsQuery: $@" if $@;

  update_status 'Loading Archive modules', 25, $MW, $STATUS, $BAR;

  eval 'use OMP::ArchiveDB';
  die "Error loading OMP::ArchiveDB: $@" if $@;
  eval 'use OMP::ArcQuery';
  die "Error loading OMP::ArcQuery: $@" if $@;

  update_status 'Loading Shiftlog modules', 50, $MW, $STATUS, $BAR;

  eval 'use OMP::ShiftDB';
  die "Error loading OMP::ShiftDB: $@" if $@;
  eval 'use OMP::ShiftQuery';
  die "Error loading OMP::ShiftQuery: $@" if $@;

  update_status 'Loading Info modules', 60, $MW, $STATUS, $BAR;

  eval 'use OMP::Info::Obs';
  die "Error loading OMP::Info::Obs: $@" if $@;
  eval 'use OMP::Info::Comment';
  die "Error loading OMP::Info::Comment: $@" if $@;

  update_status 'Loading Time::Piece modules', 65, $MW, $STATUS, $BAR;

  eval 'use Time::Piece qw/ :override /';
  die "Error loading Time::Piece: $@" if $@;

  update_status 'Loading DBbackend modules', 75, $MW, $STATUS, $BAR;

  eval 'use OMP::DBbackend';
  die "Error loading OMP::DBbackend: $@" if $@;
  eval 'use OMP::DBbackend::Archive';
  die "Error loading OMP::DBbackend::Archive: $@" if $@;

  update_status 'Complete', 99, $MW, $STATUS, $BAR;
  sleep 1;
  $STATUS->destroy if Exists($STATUS);
  $BAR->destroy if Exists($BAR);
  $MW->destroy if Exists($MW);

}

sub get_userid {
   my $MW = new MainWindow;
   my $user = OMP::General->determine_user( $MW );
   throw OMP::Error::Authentication("Unable to obtain valid user name")
     unless defined $user;
   $MW->destroy if Exists($MW);
   return $user;
}

sub create_main_window {
  $MainWindow = MainWindow->new;
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

  foreach my $obs( $obsgrp->obs ) {
    my %nightlog = $obs->nightlog('long');
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
    $nbContent->tag('configure', $otag,
                    -foreground => $CONTENTCOLOUR[$status],
                   );

    my $bgcolour;
    if( $counter % 2 ) {
      $bgcolour = $BACKGROUND1;
    } else {
      $bgcolour = $BACKGROUND2;
    }

    if($counter % 2) {
      $nbContent->tag('configure', $otag,
                      -background => $bgcolour,
                     );
    } else {
      $nbContent->tag('configure', $otag,
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
                                     qw/ -relief raised
                                     -borderwidth 1 /); } );

    $nbContent->tag('bind', $otag, '<Any-Leave>' =>
                    sub { shift->tag('configure', $otag,
                                     -background => $bgcolour,
                                     qw/ -relief flat /); } );

    # And increment the counter.
    $counter++;
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
    my $dbox = $MainWindow->DialogBox( -title => "Error",
                                       -buttons => ["OK"],
                                     );

    my $label = $dbox->add( 'Label',
                            -text => "Error: " . $Error->{-text} )->pack;
    my $but = $dbox->Show;
    undef %obs;
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
  };

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
  $CommentWindow->geometry('680x300');

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

  # $textStatus displays the string "Status:"
  my $textStatus = $entryFrame->Label( -text => 'Status: ' )->pack( -side => 'left',
                                                                    -anchor => 'n',
                                                                  );

  if( UNIVERSAL::isa( $obs, "OMP::Info::Obs::TimeGap" ) ) {
    my $radioWeather = $entryFrame->Radiobutton( -text => 'weather',
                                                 -value => OMP__TIMEGAP_WEATHER,
                                                 -variable => \$status,
                                               )->pack( -side => 'left',
                                                        -anchor => 'n',
                                                      );
    my $radioInstrument = $entryFrame->Radiobutton( -text => 'instrument',
                                                    -value => OMP__TIMEGAP_INSTRUMENT,
                                                    -variable => \$status,
                                                  )->pack( -side => 'left',
                                                           -anchor => 'n',
                                                         );
    my $radioFault = $entryFrame->Radiobutton( -text => 'fault',
                                               -value => OMP__TIMEGAP_FAULT,
                                               -variable => \$status,
                                             )->pack( -side => 'left',
                                                      -anchor => 'n',
                                                    );
    my $radioLastProject = $entryFrame->Radiobutton( -text => 'last proj.',
                                                     -value => OMP__TIMEGAP_PREV_PROJECT,
                                                     -variable => \$status,
                                                   )->pack( -side => 'left',
                                                            -anchor => 'n',
                                                          );
    my $radioNextProject = $entryFrame->Radiobutton( -text => 'next proj.',
                                                     -value => OMP__TIMEGAP_NEXT_PROJECT,
                                                     -variable => \$status,
                                                   )->pack( -side => 'left',
                                                            -anchor => 'n',
                                                          );
    my $radioUnknown = $entryFrame->Radiobutton( -text => 'unknown',
                                                 -value => OMP__TIMEGAP_UNKNOWN,
                                                 -variable => \$status,
                                               )->pack( -side => 'left',
                                                        -anchor => 'n',
                                                      );

  } else {
    my $radioGood = $entryFrame->Radiobutton( -text => 'good',
                                              -value => OMP__OBS_GOOD,
                                              -variable => \$status,
                                            )->pack( -side => 'left',
                                                     -anchor => 'n',
                                                   );
    my $radioBad = $entryFrame->Radiobutton( -text => 'bad',
                                             -value => OMP__OBS_BAD,
                                             -variable => \$status,
                                           )->pack( -side => 'left',
                                                    -anchor => 'n',
                                                  );
    my $radioQuestionable = $entryFrame->Radiobutton( -text => 'questionable',
                                                      -value => OMP__OBS_QUESTIONABLE,
                                                      -variable => \$status,
                                                    )->pack( -side => 'left',
                                                             -anchor => 'n',
                                                           );

  }

  # $textUser displays the current user id.
  my $textUser = $entryFrame->Label( -text => "Current user: " . $user->userid )->pack( -side => 'left',
                                                                                        -anchor => 'n',
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

  # Get the observation information.
  my %nightlog = $obs->nightlog('long');

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
  my $shiftlog = $w->Frame()->pack(-side => 'top', -expand => 1, -fill => 'x');

  my $topbar = $shiftlog->Frame->pack(-side => 'top',-expand => 1, 
				      -fill => 'x');

  # Create the text widget so that we can store the reference
  my $text = $shiftlog->Text(-height => 4)->pack(-side=>'bottom',-expand=> 1,
						-fill => 'x');

  # This variable controls whether we are in Local time or UT
  # Options are "LocalTime" and "UT"
  my $TZ = "LocalTime";

  # Now create the topbar
  # First a label
  $topbar->Label(-text => "Time Stamp:")->pack(-side=>'left');

  # Now the entry widget with the current time
  my $RefTime;
  $topbar->Entry(-textvariable => \$RefTime,
		   -width => 20)->pack(-side=>'left');


  # Radio button allows siwtching between UT and local time
  $topbar->Radiobutton(-variable => \$TZ,
		       -text => "Local Time",
		       -value => 'LocalTime',
		      )->pack(-side=>'left');
  $topbar->Radiobutton(-variable => \$TZ,
		       -text => "UT",
		       -value => "UT",
		      )->pack(-side=>'left');

  # Popup all the comments for the night
  $topbar->Button(-text => 'Submit Shift Comment',
		  -command => sub {submit_shift_comment($text, $user,
			       \$RefTime, $TZ, $telescope)},
		 )->pack(-side => 'right');

  # Submit this comment
  # We use a closure so that we can capture the lexicals
  # without having to pass in references
  $topbar->Button(-text => 'View all shift Comments',
		  -command => sub { view_shift_comments($w,$ut, $telescope) },
		 )->pack(-side => 'right');

  # Need to populate the time field
  # We use closures rather than array ref for passing arguments
  # so that we do not need to pass in references for all arguments
  &update_shift_comment_time($TZ, \$RefTime);
  $w->repeat(1000, sub { update_shift_comment_time($TZ,\$RefTime) } );

}

# Need to lexicals to allow us to track previous values
my $PrevTime;
my $PrevTZ;

# Pass in reference to reftime since we need to change it in the gui
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

sub submit_shift_comment {
  my $textw = shift;
  my $user = shift;
  my $RefTimeRef = shift;
  my $TZ = shift;
  my $tel = shift;

  # Dereferenece
  my $time = $$RefTimeRef;

  # Need to read the contents of the Text widget
  my $content = $textw->get('0.0','end');

  # Abort if no content
  return unless $content =~ /\w/;

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
      my $dialog = $textw->Dialog( -text => "Error parsing the date string. Please fix. Should be YYYY-MM-DDTHH:MM:SS",
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
					text => $content );

  # And add it to the system
  OMP::CommentServer->addShiftLog( $comment, $tel );

  # And clear the text widget
  $textw->delete('0.0','end');

  # And set previous time so that the update will begin again
  $PrevTime = $time;

}

# Retrieve all the comments and display them
sub view_shift_comments {
  my $w = shift;
  my $ut = shift;
  my $telescope = shift;
  my @comments = OMP::CommentServer->getShiftLog( $ut, $telescope );

  my $T = $w->Toplevel;

  my $Frame = $T->Frame->pack();

  my $textw = $Frame->Scrolled('Text',
			       -width =>80, -wrap => 'word', -height => 15,
			       -scrollbars => 'e',
			 )->pack(-side=>'top');

  my $button = $Frame->Button( -text => "Close", -command => sub {$T->destroy}
			     )->pack(-side=>'right');

  # Loop over comments
  for my $c (@comments) {
    my $date = $c->date;
    my $user = $c->author->name;
    my $text = $c->text;

    $textw->insert('end', $date->datetime . "UT by $user\n");
    $textw->insert('end', "$text\n\n");

  }

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
                    -command => sub { set_user( \$RefUser, $w ) },
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

Copyright (C) 2002-2003 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut
