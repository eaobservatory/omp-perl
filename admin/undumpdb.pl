#!/local/perl-5.6/bin/perl

# UnDump the contents of the Database
# from disk

use 5.006;
use strict;
use warnings;

use Data::Dumper;

# Pick up the OMP database
use FindBin;
use lib "$FindBin::RealBin/..";
use Storable qw(retrieve);

use OMP::DBbackend;
use OMP::BaseDB;

my $db = new OMP::BaseDB( DB => new OMP::DBbackend );

my $dumpdir = "/DSS/omp-cache/tables";

chdir $dumpdir
  or die "Error changing to directory $dumpdir: $!\n";

# Define the name and position of any TEXT columns (array index)
my %text_column = (
		   ompmsbdone => {comment => 8},
		   ompfeedback => {text => 9},
		   ompfaultbody => {text => 5},
		   ompshiftlog => {text => 3},
		   ompobslog => {commenttext => 8},
		  );

# Define the position of an identity column so we can ignore
# it and let sybase generate a new ID for the row
my %identity_column = (
		       ompfeedback => 0,
		       ompfaultbody => 0,
		       ompmsbdone => 0,
		       ompshiftlog => 0,
		       ompobslog => 0,
		       ompfaultassoc => 0,
		      );


my @tab;
(@ARGV) and @tab = @ARGV or
  @tab = qw/ompproj ompfeedback ompmsbdone ompfault ompfaultbody ompfaultassoc ompsupuser ompcoiuser ompuser/;

for my $tab (@tab) {
  my $restore = retrieve($tab);
#  print Dumper($restore);

  # Need to lock the database since we are writing
  $db->_db_begin_trans;
  $db->_dblock;

  for my $row (@$restore) {

    # Prepare the fields for insertion
    my @data = @$row;

    if (exists $text_column{$tab}) {
      for my $column (keys %{$text_column{$tab}}) {
	my $column_pos = $text_column{$tab}->{$column};
	my $text = $data[$column_pos];
	$data[$column_pos] = {TEXT => $text, COLUMN => $column};
      }
    }

    # shift off the first column if it's an IDENTITY field
    shift @data if exists $identity_column{$tab};

    # Do the insert
    $db->_db_insert_data($tab, @data);

  }

  # End transaction
  $db->_dbunlock;
  $db->_db_commit_trans;

}


