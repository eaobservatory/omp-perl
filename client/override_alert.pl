#!/local/perl/bin/perl -X

=head1 NAME

override_alert - Provide alerts for override MSBs.

=head1 SYNOPSIS

override_alert
override_alert -tel ukirt

=head1 DESCRIPTION

This program displays a list of all project IDs that have submitted an
MSB and whose TAG priority is 0. When a new MSB has been submitted to
the database the program window will blink in an attempt to get the user's
attention.

=head1 OPTIONS

The following command-line options are supported:

=over 4

=item B<-tel>

Specify the telescope to find alerts for. If the telescope can be determined
from the domain name it will be used automatically. If the telescope cannot
be determined from the domain and this option has not been specified a popup
window will request the telescope from the supplied list.

=item B<-version

Report the version number.

=item B<-help>

A help message.

=item B<-man>

This manual page.

=back

=cut

use strict;

my $DEBUG = 0;

# Colours for backgrounds.
my @BACKGROUND = qw/ #DDDDDD #D3D3D3 /;
my $HIGHLIGHTBACKGROUND = '#FFCCCC';

# Scan frequency in milliseconds.
my $SCANFREQ = 300000; # Five minutes.

BEGIN {
  use Tk;
  use Tk::Toplevel;

  use Getopt::Long;
  use Pod::Usage;

  use FindBin;
  use constant OMPLIB => "$FindBin::RealBin/..";
  use lib OMPLIB;

  use OMP::Audio;
  use OMP::Error qw/ :try /;
  use OMP::General;
  use OMP::MSBQuery;
  use OMP::MSBServer;

  $ENV{'OMP_DIR'} = OMPLIB unless exists $ENV{'OMP_DIR'};

}

END {
  OMP::General->log_message( "Closing override_alert program." );
}

OMP::General->log_message( "Starting up override_alert program..." );

$| = 1;
my $MainWindow = new MainWindow;;
my %seen_msbs;
my $textWidget;
my $id;

my ( %opt, $help, $man, $version );
my $status = GetOptions( "tel=s" => \$opt{'tel'},
                         "help" => \$help,
                         "man" => \$man,
                         "version" => \$version,
                       );

pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

if( $version ) {
  my $id = '$Id$ ';
  print "override_alert - Provide alerts for overrides\n";
  print " CVS revision: $id\n";
  exit;
}


# Get the telescope.
my $telescope;
if( defined( $opt{'tel'} ) ) {
  $telescope = uc( $opt{'tel'} );
} else {
  my $w = $MainWindow->Toplevel;
  $w->withdraw;
  $telescope = OMP::General->determine_tel( $w );
  $w->destroy if Exists( $w );
  die "Unable to determine telescope. Exiting.\n" unless defined $telescope;
}

&create_main_window();

&scan_for_msbs();

MainLoop();

sub create_main_window {
  $MainWindow;
  $MainWindow->title("Override Alerts");
  $MainWindow->geometry('580x200');

# mainFrame contains the entire frame.
  my $mainFrame = $MainWindow->Frame;

# buttonbarFrame contains buttons that do various tasks.
  my $buttonbarFrame = $mainFrame->Frame( -relief => 'groove',
                                          -borderwidth => 2,
                                        );

# exitButton is the button that exits the program.
  my $exitButton = $buttonbarFrame->Button( -text => 'EXIT',
                                            -command => 'exit',
                                          );

# rescanButton is the button that rescans for new MSBs.
  my $rescanButton = $buttonbarFrame->Button( -text => 'Rescan',
                                              -command => sub {
                                                scan_for_msbs();
                                              },
                                            );

# textWidget contains the list of project IDs.
  $textWidget = $mainFrame->Scrolled("Text",
                                     -scrollbars => 'osoe',
                                     -wrap => 'none',
                                    );

  $mainFrame->pack( -side => 'top',
                    -fill => 'both',
                    -expand => 1,
                  );
  $buttonbarFrame->pack( -side => 'top',
                         -fill => 'both',
                         -expand => 0,
                       );
  $exitButton->pack( -side => 'left' );
  $rescanButton->pack( -side => 'right' );
  $textWidget->pack( -side => 'top',
                     -fill => 'both',
                     -expand => 1,
                   );
}

sub scan_for_msbs {
  my $class = "OMP::MSBServer";
#  my $xml = "<MSBQuery><telescope>$telescope</telescope><priority><max>0</max></priority><disableconstraint>observability</disableconstraint></MSBQuery>";
  my $xml = "<MSBQuery><telescope>$telescope</telescope><priority><max>0</max></priority></MSBQuery>";
  my $E;
  my @results;
  try {
    my $query = new OMP::MSBQuery( XML => $xml,
                                   MaxCount => 100,
                                 );
    my $db = new OMP::MSBDB( DB => $class->dbConnection );
    @results = $db->queryMSB( $query, 'object' );
  } catch OMP::Error with {
    $E = shift;
    print "OMP Error: " . $E->{'-text'} . "\n";
  } otherwise {
    $E = shift;
    print "Error: " . $E->{'-text'} . "\n";
  };
  $class->throwException( $E ) if defined( $E );

  my %returned_checksums;
  my %new_checksums;

  # Find MSBs that we haven't seen yet.
  foreach my $msb ( @results ) {
    my $checksum = $msb->checksum;
    $returned_checksums{ $checksum }++;
    if( ! $seen_msbs{$checksum} ) {
      $seen_msbs{$checksum} = $msb;
      $new_checksums{$checksum}++;
      print "MSB with checksum $checksum is new!\n" if $DEBUG;
    }
  }

  # Purge MSBs from our seen list that aren't in the returned list.
  foreach my $checksum ( keys %seen_msbs ) {
    if( ! $returned_checksums{$checksum} ) {
      delete $seen_msbs{$checksum};
      print "MSB with checksum $checksum is no longer returned from database. Purging.\n" if $DEBUG;
    }
  }

  # Set up some formatting tags.
  $textWidget->tagConfigure('new_msb',
                            -background => $HIGHLIGHTBACKGROUND,
                           );
  $textWidget->tagConfigure('boldnew_msb',
                            -background => $HIGHLIGHTBACKGROUND,
                            -font => [ -weight => 'bold' ],
                           );
  for( my $i = 0; $i < scalar( @BACKGROUND ); $i++ ) {
    $textWidget->tagConfigure("bg$i",
                              -background => $BACKGROUND[$i],
                             );
    $textWidget->tagConfigure("boldbg$i",
                              -background => $BACKGROUND[$i],
                              -font => [ -weight => 'bold' ],
                             );
  }

  # And display the MSBs.
  $textWidget->delete('1.0', 'end');
  my $start = $textWidget->index('insert');
  my $bgindex = 0;
  foreach my $checksum ( sort keys %seen_msbs ) {
    if( $new_checksums{$checksum} ) {
      $textWidget->insert('end',
                          "Project ID: " . $seen_msbs{$checksum}->projectid . "\n",
                          'boldnew_msb');
      $textWidget->insert('end',
                          "$seen_msbs{$checksum}",
                          'new_msb');
    } else {
      $textWidget->insert('end',
                          "Project ID: " . $seen_msbs{$checksum}->projectid . "\n",
                          "boldbg$bgindex"
                         );
      $textWidget->insert('end',
                          "$seen_msbs{$checksum}",
                          "bg$bgindex"
                         );
    }
    $bgindex = $bgindex ? 0 : 1;
  }

  # Do the audio alert, but only if there are new MSBs.
  if( scalar( keys( %new_checksums ) ) > 0 ) {
    OMP::Audio->play( 'override_alert.wav' );
  }

  # Set up the loop to do this again.
  $id->cancel unless ! defined( $id );
  $id = $MainWindow->after($SCANFREQ, sub { scan_for_msbs(); } );

}

=head1 AUTHORS

Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2005 Particle Physics and Astronomy Research Council.
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
