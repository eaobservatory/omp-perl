#!/local/bin/perl

# List the full contents of the 3 OMP tables

use warnings;
use strict;

use Data::Dumper;

# Pick up the OMP database
use FindBin;
use lib "$FindBin::RealBin/..";
use OMP::DBbackend;

# Maximum length of text displayed from a column
use constant LONGEST => 40;

# Connect
my $db = new OMP::DBbackend;
my $dbh = $db->handle;

my @tab;
(@ARGV) and @tab = @ARGV or
  @tab = qw/ompproj ompmsb ompobs ompsciprog ompfeedback ompmsbdone 
  ompfault ompfaultbody ompuser ompsupuser ompcoiuser/;

foreach my $tab (@tab) {
  my $ref = $dbh->selectall_arrayref("SELECT * FROM $tab",{ Columns=>{} })
    or die "Cannot select on $tab: ". $DBI::errstr;

  print "\nTABLE: $tab\n";
  my @columns = sort keys %{$ref->[0]};
  print "COLUMNS: ",join(",",@columns),"\n";

  for my $row (@$ref) {
    my @full;
    for my $col (@columns) {
      my $entry = $row->{$col};
      $entry = '' unless defined $entry;
      $entry =~ s/\s+$//;
      push(@full, $entry);
    }
    # strip long entries
    @full = map {  $_ = "<LONG>" if length($_) > LONGEST; $_ } @full;
    print join(",",@full),"\n";
  }

}

$dbh->disconnect;
