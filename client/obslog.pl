#!/local/bin/perl

use strict;

my ($MW, $VERSION, $BAR, $STATUS);

# Add to @INC for OMP and ORAC libraries.
#use lib '/home/bradc/development/omp/msbserver';
use lib '/jac_sw/omp/msbserver';

BEGIN {

# set up the intial Tk "status loading" window and load in the Tk modules

# use lib qw( /local/perl-5.6/lib/site_perl/5.6.0/i686-linux/ );
	use Tk;
	use Tk::ProgressBar;
#  use Tk::NoteBook;
  use Data::Dumper;

  use OMP::Constants;

  use Time::Piece qw/ :override /;

}

# global variables
my $MainWindow;
my $obslog;  # refers to the object that holds the obslog information
my %obs; # keys are instruments, values are arrays of Info::Obs objects
my $ut;
  { my $time = gmtime;
    $ut = $time->ymd;
#    $ut = '2002-08-14';
  };
my $contentHeader;
my $contentBody;

my $HEADERCOLOUR = 'midnightblue';
my $HEADERFONT = '-*-Courier-Medium-R-Normal--*-120-*-*-*-*-*-*';
my $CONTENTCOLOUR = qw/ black brown red /;
my $CONTENTFONT = '-*-Courier-Medium-R-Normal--*-120-*-*-*-*-*-*';
my $LISTFONT = '-*-Courier-Medium-R-Normal--*-120-*-*-*-*-*-*';
my $HIGHLIGHTBACKGROUND = '#CCFFCC';
my $BREAK = 92; # Number of characters to display for observation summary
                # before linewrapping.
my $SCANFREQ = 300000;  # scan every five minutes

$VERSION = sprintf "%d %03d", q$Revision$ =~ /(\d+)\.(\d+)/;

&display_loading_status();

&create_main_window();

&full_rescan('SCUBA',$ut,\%obs);

$MainWindow->repeat($SCANFREQ, sub { full_rescan('SCUBA',$ut,\%obs); });
MainLoop();

sub display_loading_status {
	$MW = MainWindow->new;
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

sub create_main_window {
  $MainWindow = MainWindow->new;
  $MainWindow->title("OMP Observation Log Tool");
  $MainWindow->geometry('640x350');

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
                                              -command => [ \&full_rescan, 'SCUBA',$ut,\%obs ],
                                            );

# $buttonOptions is the button that allows the user to modify options.
  my $buttonOptions = $buttonbarFrame->Button( -text => 'Options',
                                               -command => \&options
                                             );

# $buttonHelp is the button that brings up a help dialogue.
  my $buttonHelp = $buttonbarFrame->Button( -text => 'Help',
                                            -command => \&help
                                          );

# $contentFrame holds the content (header and observations)
  my $contentFrame = $MainWindow->Frame;

# $contentHeader holds the header
  $contentHeader = $contentFrame->Text( -wrap => 'none',
                                        -relief => 'flat',
                                        -foreground => $HEADERCOLOUR,
                                        -height => 1,
                                        -font => $HEADERFONT,
                                        -takefocus => 0,
                                        -state => 'disabled',
                                      );

  $contentBody = $contentFrame->Scrolled('Text',
                                         -wrap => 'word',
                                         -scrollbars => 'oe',
                                         -state => 'disabled',
                                        );

  $mainFrame->pack( -side => 'top',
                    -fill => 'both',
                    -expand => 1
                  );
  $buttonbarFrame->pack( -side => 'top',
                         -fill => 'x'
                       );
  $buttonExit->pack( -side => 'left' );
  $buttonRescan->pack( -side => 'left' );
  $buttonOptions->pack( -side => 'left' );
  $buttonHelp->pack( -side => 'right' );

  $contentFrame->pack( -side => 'top',
                       -fill => 'both',
                       -expand => 1
                     );
  $contentHeader->pack( -side => 'top',
                        -fill => 'both',
                      );
  $contentBody->pack( -expand => 1,
                      -fill => 'both',
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

#sub new_instrument {
#
#  my $notebook = shift;
#  my $instrument = shift;
#
#  if( ( $notebook->raised ) eq "" ) {
#    $notebook_current = 0;
#  } else {
#    $notebook_current += 1;
#  }
#  $notebook_names[$notebook_current] = $instrument;
#
#  # Create a new page.
#  my $nbPage = $notebook->add( $notebook_names[$notebook_current],
#                               -label => $notebook_names[$notebook_current],
#                               -raisecmd => \&page_raised
#                             );
#
#  # Add a header to the page.
#  my $nbPageFrame = $nbPage->Frame;
#  my $nbHeader = $nbPageFrame->Text( -wrap => 'none',
#                                     -relief => 'flat',
#                                     -foreground => 'midnightblue',
#                                     -height => 2,
#                                     -font => $LISTFONT,
#                                     -takefocus => 0
#                                   );
#
#  my $nbContent = $nbPageFrame->Scrolled('Text',
#                                         -wrap => 'none',
#                                         -scrollbars => 'oe',
#                                        );
#
#  # Pack the notebook.
#  $nbPageFrame->pack( -side => 'top',
#                      -fill => 'both',
#                      -expand => 1
#                    );
#  $nbHeader->pack( -side => 'top',
#                   -fill => 'x',
#                 );
#  $nbContent->pack( -expand => 1,
#                    -fill => 'both'
#                  );
#
#  $notebook->raise( $notebook_names[$notebook_current] );
#  &page_raised;
#}

sub page_raised { }

sub redraw {
  my $inst = shift;
  my $obs_arrayref = shift;

  my $header_printed = 0;

  # Clear the contents of the text window
  $contentBody->configure( -state => 'normal');
  $contentBody->delete('0.0','end');

  my $counter = 0;

  foreach my $obs (@$obs_arrayref) {
    my %nightlog = $obs->nightlog;

    # Draw the header, if necessary.
    if(!$header_printed) {

      # Clear the header.
      $contentHeader->configure( -state => 'normal');
      $contentHeader->delete('0.0', 'end');

      # Insert the line.
      $contentHeader->insert('end', $nightlog{'_STRING_HEADER'});

      # Clean up.
      $contentHeader->configure( -state => 'disabled' );
      $header_printed = 1;
    }

    # Take a local copy of the index for callbacks
    my $index = $counter;

    # Generate the tag name based on the index.
    my $otag = "o" . $index;

    # Get the reference position
    my $start = $contentBody->index('insert');

    # Insert the line
    $contentBody->insert('end', $nightlog{'_STRING'} . "\n");

    # Remove all the tags at this position.
    foreach my $tag ($contentBody->tag('names', $start)) {
      $contentBody->tag('remove', $tag, $start, 'insert');
    }

    # Create a new tag.
    $contentBody->tag('add', $otag, $start, 'insert');

    # Configure the new tag.
    $contentBody->tag('configure', $otag,
                      -foreground => 'black',
                     );

    # Bind the tag to double-left-click
    $contentBody->tag('bind', $otag, '<Double-Button-1>' =>
                      sub {
                        RaiseComment( $obs );
                        } );

    # Do some funky mouse-over colour changing.
    $contentBody->tag('bind', $otag, '<Any-Enter>' =>
                      sub { shift->tag('configure', $otag,
                                        -background => $HIGHLIGHTBACKGROUND,
                                       qw/ -relief raised
                                           -borderwidth 1 /); } );

    $contentBody->tag('bind', $otag, '<Any-Leave>' =>
                      sub { shift->tag('configure', $otag,
                                       -background => undef,
                                       qw/ -relief flat /); } );


    # And increment the counter.
    $counter++;
  }

  # And disable the text widget.
  $contentBody->configure( -state => 'disable' );

  # And scroll down to the bottom.
  $contentBody->see('end');

}

sub rescan {
  my $inst = shift;
  my $ut = shift;

  # Form the XML.
  my $xml = "<ArcQuery><instrument>$inst</instrument><date delta=\"1\">$ut</date></ArcQuery>";

  # Form the query.
  my $arcquery = new OMP::ArcQuery( XML => $xml );

  # Grab the results.
  my $adb = new OMP::ArchiveDB( DB => new OMP::DBbackend::Archive );
  my @result = $adb->queryArc( $arcquery );

  # Add the comments.
  my $odb = new OMP::ObslogDB( DB => new OMP::DBbackend );
  $odb->updateObsComment( \@result );

  # And return the results.
  return @result;

}


# Perform a full rescan/redraw sequence.
sub full_rescan {
  my $inst = shift;
  my $ut = shift;
  my $hashref = shift;

  my @result = rescan($inst, $ut);

  redraw($inst,\@result);

  $hashref->{$inst} = @result;
}

# Display the comment window and allow for editing, etc, etc, etc.
sub RaiseComment {
  my $obs = shift;
return;
  my $status;
  if(defined($obs->comments->[0])) {
    $status = $obs->comments->[0]->status;
  } else {
    $status = OMP__OBS_GOOD;
  }

  my $CommentWindow = MainWindow->new;
  $CommentWindow->title("OMP Observation Log Tool Commenting");
  $CommentWindow->geometry('+40+40');

  # $commentFrame contains the entire frame.
  my $commentFrame = $CommentWindow->Frame;

  my $contentFrame = $commentFrame->Frame;

  # $commentHeader contains the header information
  my $commentHeader = $contentFrame->Text( -wrap => 'none',
                                           -relief => 'flat',
                                           -foreground => $HEADERCOLOUR,
                                           -height => 1,
                                           -font => $HEADERFONT,
                                           -takefocus => 0,
                                           -state => 'disabled',
                                         );

  # $commentBody contains the content
  my $commentBody = $contentFrame->Text( -wrap => 'word',
                                         -relief => 'flat',
                                         -height => 2,
                                         -font => $CONTENTFONT,
                                         -takefocus => 0,
                                         -state => 'disabled',
                                       );

  my $buttonFrame = $commentFrame->Frame;

  # $buttonSave is the button that allows the user to save the comment
  # to the database.
  my $buttonSave = $buttonFrame->Button( -text => 'Save',
                                          -command => sub { print "save"; },
                                        );

  # $buttonCancel is the button that closes the window without saving
  # any changes.
  my $buttonCancel = $buttonFrame->Button( -text => 'Cancel',
                                            -command => sub { print "cancel"; },
                                          );

  my $entryFrame = $commentFrame->Frame;

  # $textStatus displays the string "Status:"
  my $textStatus = $entryFrame->Label( -text => 'Status: ' );

  # $radioGood is the radio button for the status value 'good'
  my $radioGood = $entryFrame->Radiobutton( -text => 'good',
                                            -value => OMP__OBS_GOOD,
                                            -variable => \$status,
                                          );

  # $radioQuestionable is the radio button for the status value 'questionable'
  my $radioQuestionable = $entryFrame->Radiobutton( -text => 'questionable',
                                                    -value => OMP__OBS_QUESTIONABLE,
                                                    -variable => \$status,
                                                  );

  # $radioBad is the radio button for the status value 'bad'
  my $radioBad = $entryFrame->Radiobutton( -text => 'bad',
                                           -value => OMP__OBS_BAD,
                                           -variable => \$status,
                                         );

  # $scrolledComment is the text area that will be used for comment entry.
  my $scrolledComment = $entryFrame->Scrolled( 'Text',
                                               -wrap => 'none',
                                               -scrollbars => 'oe',
                                             );

  # Pack them all together.
  $commentFrame->pack( -side => 'top',
                       -fill => 'both',
                       -expand => 1,
                     );
$contentFrame->pack( -side => 'top',
                     -fill => 'x',
                   );
$entryFrame->pack( -side => 'top',
                   -fill => 'x',
                 );
$buttonFrame->pack( -side => 'bottom',
                    -fill => 'x',
                  );

$commentHeader->pack( -side => 'top',
                      -fill => 'x',
                    );
$commentBody->pack( -side => 'top',
                    -fill => 'x',
                  );

$textStatus->pack( -side => 'left',
                 );
$radioGood->pack( -side => 'left',
                );
$radioQuestionable->pack( -side => 'left',
                        );
$radioBad->pack( -side => 'left',
               );
$scrolledComment->pack( -side => 'bottom',
                        -fill => 'x',
                      );

  print "will display observation " . $obs->runnr . "\n";
}

sub options { }

sub help { }
