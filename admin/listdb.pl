#!/local/bin/perl

# List the full contents of the 3 OMP tables

use warnings;
use strict;

use DBI;
use Data::Dumper;

my $DBserver = "SYB_UKIRT";
my $DBuser = "omp";
my $DBpwd  = "***REMOVED***";
my $DBdatabase = "archive";


my $dbh = DBI->connect("dbi:Sybase:server=${DBserver};database=${DBdatabase};timeout=120", $DBuser, $DBpwd)
  or die "Cannot connect: ". $DBI::errstr;

my @tab;
(@ARGV) and @tab = @ARGV or
  @tab = qw/ompproj ompmsb ompobs ompsciprog ompfeedback ompmsbdone/;

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
    @full = map {  $_ = "<LONG>" if length($_) > 32; $_ } @full;
    print join(",",@full),"\n";
  }

}

$dbh->disconnect;
