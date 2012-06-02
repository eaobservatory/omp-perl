use strict;

use Test::More tests => 3
  + 5
  + (1 + 5 * 3) * 5;

use IO::File;

use OMP::Config;
use OMP::SpServer;
use OMP::MSBDB;
use OMP::MSBQuery;

use PASSWORD qw/staff_password/;

my %prog = (
  'Raster 1' => {remaining => 1},
  'Daisy 1'  => {remaining => 1},
  'Jiggle 1' => {remaining => 2},
  'Pong 1'   => {remaining => 2},
  'Pong 2'   => {remaining => 3},
  );

# Or folder numbers in the above list have the following select numbers:
my %or_select = (
  1 => 3,
);

my $cf = OMP::Config->new();
$cf->configDatabase('/jac_sw/etc/ompsite-dev.cfg');
my $db = OMP::DBbackend->new();

my $project = 'TJ04';

die 'Not using test database' unless {$db->loginhash()}->{'database'}
                                  eq 'devomp';

my $msbdb = new OMP::MSBDB(Password => staff_password(),
                           ProjectID => $project,
                           DB => $db);

ok($msbdb, 'Log in to MSB DB');

my $xml; {
        local $/ = undef;
        my $fh = new IO::File('store-alter.xml');
        $xml = <$fh>;
        close $fh;
}

die 'Not using the correct project ID'
  unless $xml =~ /<projectID>$project<\/projectID>/;



# Delete old program before re-inserting.
eval {
  $msbdb->removeSciProg();
};
is($@, '', 'Delete old science program');

my $res = OMP::SpServer->storeProgram($xml, staff_password(), 1);
ok(ref $res, 'Store science program');

my $query = new OMP::MSBQuery(XML => '<MSBQuery>
  <projectid full="1">' . $project . '</projectid>
  <disableconstraint>remaining</disableconstraint>
  <disableconstraint>allocation</disableconstraint>
  <disableconstraint>observability</disableconstraint>
</MSBQuery>');
my @results = $msbdb->queryMSB($query, 'object');

# Check that we have the correct set of MSBs, and store
# their checksums for future reference.
foreach my $msb (@results) {
  my $title = $msb->title();

  unless (exists $prog{$title}) {
        fail('Find MSB by title: ' . $title . ' (extra)');
        next;
  }

  pass('Find MSB by title: ' . $title);

  $prog{$title}->{'checksum'} = $msb->checksum();
  $prog{$title}->{'msbid'} = $msb->msbid();

  unless (1 == scalar @{$msb->{'observations'}}) {
    fail('Check that there is one observation');
    $prog{$title}->{'obsid'} = 'MISSING';
    next;
  }

  $prog{$title}->{'obsid'} = $msb->{'observations'}->[0]->{'obsid'};
}

foreach my $title (keys %prog) {
  fail('Find MSB by title: ' . $title . ' (missing)')
    unless exists $prog{$title}->{'checksum'};
}



# Perform tests on alterations:

set_field('Daisy 1', 'priority', 40);
$res = OMP::SpServer->storeProgram($xml, staff_password(), 1);
ok(ref $res, 'Store altered program');
check_changed('Daisy 1');

set_field('Pong 1', 'noiseCalculationTau', 0.12);
$res = OMP::SpServer->storeProgram($xml, staff_password(), 1);
ok(ref $res, 'Store altered program');
check_changed('Pong 1');


set_field('Raster 1', 'rest_freq', '3.52E11');
$res = OMP::SpServer->storeProgram($xml, staff_password(), 1);
ok(ref $res, 'Store altered program');
check_changed('Raster 1');

set_field('Jiggle 1', 'PA', 45);
$res = OMP::SpServer->storeProgram($xml, staff_password(), 1);
ok(ref $res, 'Store altered program');
check_changed('Jiggle 1');

set_field('Pong 2', 'c1', '12:34:56');
$res = OMP::SpServer->storeProgram($xml, staff_password(), 1);
ok(ref $res, 'Store altered program');
check_changed('Pong 2');


# Mangle XML to try to alter the named field.
# Only certain fields are supported.
sub set_field {
        my ($title, $field, $value) = @_;

        my @output = ();
        my @msb = ();
        my $msbtitle = undef;

        foreach my $line (split "\n", $xml) {

          if ($line =~ /<\/?SpMSB/) {
            foreach (@msb) {
              if (defined $msbtitle and $msbtitle eq $title) {
                if ($field eq 'rest_freq') {
                  s/$field="[^"]*"/$field="$value"/;
                }
                else {
                  s/<$field>[^<]*<\/$field>/<$field>$value<\/$field>/;
                }
              }

              push @output, $_;
            }
            @msb = ();
            $msbtitle = undef;
          }

          if ($line =~ /<title>([^<]*)<\/title>/ and not defined $msbtitle) {
            $msbtitle = $1;
          }

          push @msb, $line;
        }

        push @output, $_ foreach @msb;
        $xml = join "\n", @output;
}

# Checks that the specified MSB changed,
# and the others didn't
# 3 tests per MSB if successful
sub check_changed {
  my ($msbtitle) = @_;
  my @results = $msbdb->queryMSB($query, 'object');
  my %titles = map {$_ => 1} keys %prog;

  foreach my $msb (@results) {
    my $title = $msb->title();

    if (exists $prog{$title}) {
      delete $titles{$title};

      my $obsid = (1 == scalar @{$msb->{'observations'}})
        ? $msb->{'observations'}->[0]->{'obsid'} : 'MISSING';

      if ($msbtitle eq $title) {
        isnt($prog{$title}->{'checksum'}, $msb->checksum(), 'Checksum changed (' . $title . ')');
        isnt($prog{$title}->{'msbid'}, $msb->msbid(), 'MSB id changed (' . $title . ')');
        isnt($prog{$title}->{'obsid'}, $obsid, 'OBS id changed (' . $title . ')');

        $prog{$title}->{'checksum'} = $msb->checksum();
        $prog{$title}->{'msbid'} = $msb->msbid();
        $prog{$title}->{'obsid'} = $obsid;
      }
      else {
        is($prog{$title}->{'checksum'}, $msb->checksum(), 'Checksum unchanged (' . $title . ')');
        is($prog{$title}->{'msbid'}, $msb->msbid(), 'MSB id unchanged (' . $title . ')');
        is($prog{$title}->{'obsid'}, $obsid, 'OBS id unchanged (' . $title . ')');
      }
    }
    else {
      fail('Check MSB by title: ' . $title . ' (extra)');
      next;

    }

  }

  foreach my $title (keys %titles) {
    fail('Check MSB by title: ' . $title . ' (missing)');
  }
}
