#!perl

# Test the OMP::SciProg class

use warnings;
use strict;
use SOAP::Lite;
use OMP::SpServer;
use OMP::MSBServer;

# Strings
# Read the data handle
local $/ = undef;
my $file = "/home/timj/my.xml";
open my $fh, "<$file" or die "Oops: $!";
my $xml = <$fh>;
close($fh);

#print SOAP::Lite
#  -> uri('http://www.jach.hawaii.edu/OMP::SpServer')
#  -> proxy('http://www-private.jach.hawaii.edu:81/cgi-bin/spsrv.pl')
#  -> fetchProgram("M01BU53","junk")
#  -> result;

my $msb = new SOAP::Lite(
			  uri =>'http://www.jach.hawaii.edu/OMP::MSBServer',
#			  proxy =>'http://www-private.jach.hawaii.edu:81/cgi-bin/msbsrvtj.pl',
			  proxy =>'http://www.jach.hawaii.edu/JAClocal/cgi-bin/msbsrv.pl',
#			  proxy =>'http://www-private.jach.hawaii.edu:81/cgi-bin/msbsrv.pl',
			 );

my $sp = new SOAP::Lite(
			  uri =>'http://www.jach.hawaii.edu/OMP::SpServer',
#			  proxy =>'http://www-private.jach.hawaii.edu:81/cgi-bin/spsrvtj.pl',
			  proxy =>'http://www.jach.hawaii.edu/JAClocal/cgi-bin/spsrv.pl',
#			  proxy =>'http://www-private.jach.hawaii.edu:81/cgi-bin/spsrv.pl',
			 );

#$sp = "OMP::SpServer";
$msb = "OMP::MSBServer";

#print $sp->fetchProgram("M01BTIM2", "junk");

#$sp->outputxml(1);

#my $answer = $msb->queryMSB("<MSBQuery><instrument>UFTI</instrument><wavelength><max>1.0</max></wavelength><projectid>M01BTJ</projectid></MSBQuery>",0);
#my $answer = $msb->queryMSB("<MSBQuery><projectid>M01BTJ</projectid></MSBQuery>",0);

#my $answer = $msb->queryMSB("<MSBQuery></MSBQuery>",5);


my $qxml = <<END;
<?xml version="1.0" encoding="ISO-8859-1"?>
<MSBQuery>
 <MOON/>
 <instruments> 
 <instrument>
   UFTI
</instrument>
</instruments>
</MSBQuery>
END

#print "XML: $qxml\n";

#my $answer = $msb->queryMSB($qxml,5);

#my $answer = $sp->programDetails("M01BTJ");

#my $answer = $msb->testServer;

# Get the science program
#my $sciprog = new OMP::SciProg( FILE => "test.xml" );
#my $xml = "$sciprog";

my $answer = $sp->storeProgram($xml, "stryboso");
#my $answer = $sp->fetchProgram("M01BTJ", "crionsda");

#my $answer = $msb->fetchMSB(8);
if (ref($answer)) {
  if (ref($answer) eq 'ARRAY') {
    print $answer->[0];
  }  elsif ($answer->fault) {
    print $answer->faultcode . ": " . $answer->faultstring;
  } else {
    print $answer->result;
  }
} else {
  print $answer;
}

#my $result = OMP::SpServer->storeProgram($xml,"junk");
#print "Result: $result\n";
#print OMP::SpServer->fetchProgram("M01BU54", "junk");


