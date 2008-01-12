#!/local/perl/bin/perl -XT
#
# WWW Observing Remotely Facility (WORF)
#  Data File Download tool (DFD)
#
# http://www.jach.hawaii.edu/JACpublic/UKIRT/software/worf/
#
# Requirements:
#  TBD
#
# Author: Brad Cavanagh (b.cavanagh@jach.hawaii.edu)

use strict;

# Standard initialisation (not much shorter than the previous
# code but no longer has the module path hard-coded)
BEGIN {
  my $retval = do "./omp-cgi-init.pl";
  unless ($retval) {
    warn "couldn't parse omp-cgi-init.pl: $@" if $@;
    warn "couldn't do omp-cgi-init.pl: $!"    unless defined $retval;
    warn "couldn't run omp-cgi-init.pl"       unless $retval;
    exit;
  }
}

# Bring in ORAC modules so we can figure out where the files
# are, depending on the instrument.

use lib qw( /ukirt_sw/oracdr/lib/perl5 /jcmt_sw/oracdr/lib/perl5 );
use ORAC::Inst::Defn qw/orac_configure_for_instrument/;

# Set up various variables.

my @instruments = ( "cgs4", "ircam", "michelle", "ufti", "scuba" );
my $query = new CGI;

my $ut;
  {
    my ($sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdist) = gmtime(time);
    $ut = ($year + 1900) . pad($month + 1, "0", 2) . pad($day, "0", 2);

# for demo purposes only
#    $ut = "20020310";
  }

# Set up and verify $query variables. We will only have filename and
# instrument to check.

my ($q_file, $q_instrument);

if($query->param('file')) {

# The 'file' parameter must be just a filename. No pipes, slashes, or
# other weird characters that can allow for shell manipulation. If it
# doesn't match the proper format, set it to an empty string.

  my $t_file = $query->param('file');
  $t_file =~ s/[^a-zA-Z0-9\._]//g;

  if($t_file =~ /^[a-zA-Z]{1,2}\d{8}_\w+\.sdf$/) {
    $q_file = $t_file;
  } else {
    $q_file = '';
  }
} else {
  $q_file = '';
}

if($query->param('instrument')) {

# The 'instrument' parameter must match one of the strings listed
# in the @instrument array. If it doesn't, set it to an empty string.
  
  # first, strip out anything that's not a letter or a number
  
  my $t_instrument = $query->param('instrument');
  $t_instrument =~ s/[^a-zA-Z0-9]//g;
  
  # this parameter needs to match exactly one of the strings listed
  # in @instruments
  
  my $match = 0;
  
  foreach my $t_inst (@instruments) {
    if($t_instrument eq $t_inst) {
      $q_instrument = $t_inst;
      $match = 1;
    }
  }
  if ($match == 0) {
    $q_instrument = "";
  }
} else {
  $q_instrument = '';
}

# Only do something if both $q_file and $q_instrument are not
# empty strings.

if( ( length( $q_file . '' ) != 0 ) &&
    ( length( $q_instrument . '' ) != 0 ) ) {

# Now this is the real meat. Configure %ENV using
# ORAC::Inst::Defn::orac_configure_for_instrument.
  
  my %options;
  $options{'ut'} = $ut;
  orac_configure_for_instrument( uc( $q_instrument ), \%options );

  my $filepath = $ENV{"ORAC_DATA_OUT"};

  open(my $fh, '<', qq{$filepath/$q_file}) or die "Could not open file $filepath" . "/" . "$q_file: $!";
  {
    undef $/;
    $data = <$fh>;
  }

  print $query->header(-type => 'image/x-ndf');
  print $data;

  close $fh;
}

sub pad {
  my ($string, $character, $endlength) = @_;
  my $result = ($character x ($endlength - length($string))) . $string;
}
