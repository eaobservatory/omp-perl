use strict;

use Test::More tests => 3 + 9 * 2
  + 12        # obsid sequence
  + 9 * 3     # sanity check
  + 1 + 9 * 3 # accept & check...
  + 1 + 8 * 3
  + 1 + 8 * 3
  + 1 + 5 * 3
  + 1 + 4 * 3
  + 1 + 3 * 3
  + 1 + 2 * 3
  + 1 + 2 * 3
  + 1 + 2 * 3;

use IO::File;
use Data::Dumper;

use OMP::Config;
use OMP::SpServer;
use OMP::MSBDB;
use OMP::MSBQuery;

use PASSWORD qw/staff_password/;

my %prog = (
  'Raster 1' => {remaining => 1, nobs => 1},
  'Raster 2' => {remaining => 2, nobs => 2},
  'Raster 3' => {remaining => 3, nobs => 1},
  'Or Pong 1' => {remaining => 1, 'or' => 1, nobs => 1},
  'Or Pong 2' => {remaining => 2, 'or' => 1, nobs => 2},
  'Or Pong 3' => {remaining => 3, 'or' => 1, nobs => 1},
  'Or Daisy 1' => {remaining => 1, 'or' => 1, nobs => 1},
  'Or Daisy 2' => {remaining => 2, 'or' => 1, nobs => 2},
  'Or Daisy 3' => {remaining => 3, 'or' => 1, nobs => 1},
  );

# Or folder numbers in the above list have the following select numbers:
my %or_select = (
  1 => 3,
);

my $cf = OMP::Config->new();
$cf->configDatabase('/jac_sw/etc/ompsite-dev.cfg');
my $db = OMP::DBbackend->new();

# Disable writing the science programme to the cache directory.  We don't
# want to do this anyway from the test script, and if we let it try to do
# it, it is likely to fail and send warning emails to the OMP list.
delete $cf->{'omp'}->{'sciprog_cachedir'};
delete $cf->{'omp-dev'}->{'sciprog_cachedir'};

my $project = 'TJ04';

die 'Not using test database' unless {$db->loginhash()}->{'database'}
                                  eq 'devomp';

my $msbdb = new OMP::MSBDB(Password => staff_password(),
                           ProjectID => $project,
                           DB => $db);

ok($msbdb, 'Log in to MSB DB');

my $xml; {
        local $/ = undef;
        my $fh = new IO::File('store-accept.xml');
        $xml = <$fh>;
        close $fh;
}

die 'Not using the correct project ID'
  unless $xml =~ /<projectID>$project<\/projectID>/;

# Delete old program before re-inserting so that we can
# check that the obsid fields increment correctly.
eval {
  $msbdb->removeSciProg();
};
is($@, '', 'Delete old science program');

my $res = OMP::SpServer->storeProgram($xml, staff_password(), 1);
ok(ref $res, 'Store science program');


my $query = new OMP::MSBQuery(XML => '<MSBQuery>
  <projectid full="1">' . $project . '</projectid>
  <!-- <disableconstraint>remaining</disableconstraint> -->
  <disableconstraint>allocation</disableconstraint>
  <disableconstraint>observability</disableconstraint>
  <disableconstraint>zoa</disableconstraint>
</MSBQuery>');
my @results = $msbdb->queryMSB($query, 'object');
#print Dumper(\@results); exit(0);

my $obsid = undef;

# Check that we have the correct set of MSBs, and store
# their checksums for future reference.
#
# Fetch in the correct sequence so that we can check the obsid fields.
foreach my $msb (sort {$a->{'msbid'} <=> $b->{'msbid'}} @results) {
  my $title = $msb->title();

  next unless exists $prog{$title};
  pass('Find MSB by title: ' . $title);

  $prog{$title}->{'checksum'} = $msb->checksum();

  if (exists $prog{$title}->{'or'}) {
    like($msb->checksum(), qr/O$/, 'checksum ends with O');
  }
  else {
    unlike($msb->checksum(), qr/O$/, 'checksum does not end with O');
  }

  foreach my $obs (@{$msb->{'observations'}}) {
    if (defined $obsid) {
      is($obs->{'obsid'}, ++ $obsid, 'obsid in correct sequence '
                                   . $obs->{'obsid'});
    }
    else {
      $obsid = $obs->{'obsid'};
      ok($obsid > 0, 'positive value for first obsid ' . $obsid);
    }
  }
}

foreach my $title (keys %prog) {
  fail('Find MSB by title: ' . $title)
    unless exists $prog{$title}->{'checksum'};
}

# Initial sanity check
compare_db();

# Now simulate observations
do_msb('Raster 2');  compare_db();
do_msb('Or Pong 1'); compare_db(); # 8 left
do_msb('Or Pong 2'); compare_db();
do_msb('Or Pong 3'); compare_db(); # 5 left
do_msb('Raster 2');  compare_db(); # 4 left
do_msb('Or Pong 2'); compare_db(); # 3 left
do_msb('Raster 1');  compare_db(); # 2 left
do_msb('Or Pong 3'); compare_db();
do_msb('Raster 3');  compare_db();


# Mark MSB as done and adjust our %prog table accordingly.
# Logic here written without looking at the OMP classes to 
# avoid potentially copying errors accross.
# Runs 1 test.
sub do_msb {
  my $title = shift;

  if (exists $prog{$title} and exists $prog{$title}->{'checksum'}) {
    my $checksum = $prog{$title}->{'checksum'};

    if (exists $prog{$title}->{'or'}) {
      my $or = $prog{$title}->{'or'};
      delete $prog{$title}->{'or'};
      $prog{$title}->{'checksum'} =~ s/O$//;

      unless (-- $or_select{$or}) {
        foreach my $msb (keys %prog) {
          delete $prog{$msb} if exists $prog{$msb}->{'or'}
                                and $prog{$msb}->{'or'} == $or;
        }
      }
    }

    unless (-- $prog{$title}->{'remaining'}) {
              delete $prog{$title};
    }

    eval {
      $msbdb->doneMSB($checksum, {adjusttime => 0});
    };

    is($@, '', 'Accept MSB in database');
  }
  else {
    fail('Can not find MSB to accept');
  }
}

# Queries the database and compares the results with our table.
# If successful, runs 2 tests per MSB remaining.
sub compare_db {
  @results = $msbdb->queryMSB($query, 'object');

  my %titles = map {$_ => 1} keys %prog;

  foreach my $msb (@results) {
    my $title = $msb->title();

    if (exists $prog{$title}) {
      is($prog{$title}->{'remaining'}, $msb->remaining(),
        'compare remaining of '.$title);
      is($prog{$title}->{'checksum'}, $msb->checksum(),
        'compare checksum of '.$title);
      is($prog{$title}->{'nobs'}, scalar @{$msb->{'observations'}},
        'check numner of observations for ' . $title);
      delete $titles{$title};
    }
    else {
      fail('MSB ' . $title . ' should not be in database');
    }
  }

  foreach my $title (keys %titles) {
    fail('MSB ' . $title . ' missing from the database');
  }
}
