#!/local/perl/bin/perl -XT
use strict;

# Deliver the OMP fault RSS feed

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

use CGI;
use XML::RSS;

use OMP::Config;
use OMP::FaultServer;
use OMP::General;

# Fault system URL
my $base_url = OMP::Config->getData('omp-url') . OMP::Config->getData('cgidir');

# Retrieve faults for the last 24 hours
my $today = OMP::General->today;
my $xml = "<FaultQuery><date delta='-1'>$today</date><isfault>1</isfault></FaultQuery>";
my $faults = OMP::FaultServer->queryFaults($xml, 'object');

# Create the RSS channel
my $rss = new XML::RSS(version => '1.0');
$rss->channel(title => "OMP Fault System",
	      link => $base_url . "/queryfault.pl",
	      description => "OMP Fault System",
	     );

# Add faults to the channel
for my $fault (@$faults) {
  my $title = $fault->category ." - ". $fault->subject;
  my $link = $base_url ."/viewfault.pl?id=". $fault->id;

  # Use snippet of fault body as the item description
  my $desc = substr($fault->responses->[0]->text, 0, 87);

  $rss->add_item(title => $title,
		 description => $desc,
		 link => $link,
		);
}

# Output the XML file
my $q = new CGI;
print $q->header(-type=>'text/xml');
print $rss->as_string;
