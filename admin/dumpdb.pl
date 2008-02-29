#!/local/bin/perl

# Dump the contents of the omp tables to disk
# [excluding the sciprog, user, obs and msb tables]

# The sciprog table is excluded because there are problems
# with text truncation for large science programs and we
# have a special dumpsciprog routine specifically for this.
# We might be able to overcome this by using
#
#   SET TEXTSIZE 330000000
#
# on sybase.

use warnings;
use strict;

# Pick up the OMP database
use FindBin;
use lib "$FindBin::RealBin/..";
use OMP::DBbackend;
use Storable qw(nstore);
use File::Copy;
use Time::Piece;

my $dumpdir = "/omp-cache/tables";

chdir $dumpdir
  or die "Error changing to directory $dumpdir: $!\n";

# Connect
my $db = new OMP::DBbackend;
my $dbh = $db->handle;

my @tab = @ARGV || qw/
                      ompfault
                      ompfaultassoc
                      ompfaultbody
                      ompfeedback
                      ompmsbdone
                      ompobs
                      ompobslog
                      ompproj
                      ompprojqueue
                      ompprojuser
                      ompshiftlog
                      omptimeacct
                      ompuser
                    /;

foreach my $tab (@tab) {
  my $ref = $dbh->selectall_arrayref("SELECT * FROM $tab")
    or die "Cannot select on $tab: ". $DBI::errstr;

  # rename the previous dump
  if (-e $tab) {
    rename($tab, $tab . "_2")
      or die "Cannot rename previous dump file: $!\n";
  }
  nstore($ref, "$tab");

  # Take a permanent copy of the old dump if it is larger than
  # the new dump.
  my $old = $tab . '_2';

  if (-e $old) {
    my @new_dump = stat($tab);
    my @old_dump = stat($old);
    if ($old_dump[7] > $new_dump[7]) {
      my $date = localtime;
      copy($old, $tab . "_" . $date->strftime("%Y%m%d_%H_%M_%S"))
        or die "Cannot copy '$tab' to '$old': $!\n";

      # If new dump is less than 75 percent of old dump size
      # send a warning
      if (@new_dump / @old_dump * 100 < 75) {
        my $msg = MIME::Lite->new(
                                  From => "dumpdb.pl <kynan\@jach.hawaii.edu>",
                                  To => "kynan\@jach.hawaii.edu",
                                  Subject => "Warning: table $tab has shrunken significantly",
                                  Data => "New size is $new_dump[7].  Was previously $old_dump[7].  This could mean an accidental deletion has occurred.",
                                 );

        MIME::Lite->send("smtp", "mailhost", Timeout => 30);
        $msg->send;
      }
    }
  }
}

$dbh->disconnect;

