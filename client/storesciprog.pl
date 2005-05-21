
use strict;
use Data::Dumper;
use SOAP::Lite;
use OMP::SpServer;

#my $sps = new SOAP::Lite(
#                          uri =>'http://www.jach.hawaii.edu/OMP::SpServer',
#                        proxy => 'http://omp-dev.jach.hawaii.edu/cgi-bin/spsrv.pl',
#                         );

my $sps = "OMP::SpServer";

local $/ = undef;
my $file = '/home/timj/elements.xml';
my $file = '/net/kalani/export/ukirtdata/omp-cache/sciprogs/U_03B_J3.xml';
$file = 'xxx.xml';
open my $fh, "<$file";
my $xml = <$fh>;

my $reply = $sps->storeProgram( $xml, "pohoiki" ,1);

soap_reply($reply);


exit;

sub soap_reply {
  my $answer = shift;
#  print Dumper($answer);
#  return;
  if (ref($answer)) {
    if (ref($answer) eq 'ARRAY') {
      print $answer->[0];
      print Dumper( $answer );
    } elsif (ref($answer) eq 'HASH') {
      print Dumper( $answer );
    } elsif (UNIVERSAL::isa($answer,"SOAP::Data")) {
      print Dumper( $answer );
      print "SOAP::Data\n";
    } elsif ($answer->fault) {
      print $answer->faultcode . ": " . $answer->faultstring;
    } else {
      print $answer->result;
    }
  } else {
    print $answer;
  }
}

