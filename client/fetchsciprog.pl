#!/bin/env perl

# This is an example SOAP program retrieval

use SOAP::Lite;
use Data::Dumper;

my $PROJECT = "U/UHS/UHSJ16";
my $PASSWORD = "YOURPASSWORD";

my $sps = SOAP::Lite->new(
                          uri => "http://www.jach.hawaii.edu/OMP::SpServer",
                          proxy => "http://omp.jach.hawaii.edu/cgi-bin/spsrv.pl",
                         );

my $reply = $sps->fetchProgram( $PROJECT, $PASSWORD );

soap_reply( $reply );

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

