#!perl

# Test the OMP::SciProg class

use warnings;
use strict;
use Test;

BEGIN { plan tests => 96 }

use OMP::SciProg;
use OMP::MSBDB;

# Filename
my $file = "test.xml";

my $obj = new OMP::SciProg( FILE => $file );

ok($obj);


# Strings
# Read the data handle
local $/ = undef;
my $xml = <DATA>;

my $sp = new OMP::SciProg( XML => $xml );
ok($sp);

print "# Project ID: ", $sp->projectID, "\n";

# Test stringify by comparing the original with
# the stringified form
my @stringified = split /\n/, "$sp";
my @lines = split /\n/,$xml;

#for my $i (0..$#stringified) {
#  ok($stringified[$i], $lines[$i]);
#}


# See how many MSBs we have
my @msbs = $sp->msb;
print "# Number of MSBs: ",scalar(@msbs), "\n";
ok(scalar(@msbs), 2);


# Go through the MSBs to see what we can find out about them
for my $msb (@msbs) {
  print "# Remaining to observe: ", $msb->remaining,"\n";
  $msb->remaining(-4);
  print "# Remaining to observe: ", $msb->remaining,"\n";

  print "# Checksum: ",$msb->checksum,"\n";
}

print scalar($sp->summary);

# Store it
my $db = new OMP::MSBDB( Password => "junk", ProjectID => $sp->projectID );
$db->storeSciProg( SciProg => $sp );

# and fetch it
my $newsp = $db->fetchSciProg;

print "# Compare science programs\n";
ok("$sp", "$newsp");


# Some XML
__DATA__
<?xml version="1.0" encoding="ISO-8859-1"?>
<SpProg>
  <projectID>M01BU53</projectID>
  <SpTelescopeObsComp id="0">
    <ItemData name="new" package="gemini.sp.obsComp" subtype="targetList" type="oc"/>
    <MetaData>
      <unique>true</unique>
      <gui>
        <collapsed>false</collapsed>
      </gui>
    </MetaData>
    <base>
      <target type="science">
        <targetName></targetName>
        <hmsdegSystem type="J2000">
          <c1>0:00:00</c1>
          <c2>0:00:00</c2>
        </hmsdegSystem>
      </target>
    </base>
  </SpTelescopeObsComp>
  <SpMSB remaining="1">
    <SpTelescopeObsCompRef idref="0"/>
    <ItemData name="new" package="gemini.sp" subtype="msb" type="og"/>
    <MetaData>
      <gui>
        <collapsed>false</collapsed>
      </gui>
    </MetaData>
    <SpSiteQualityObsComp>
      <ItemData name="new" package="gemini.sp.obsComp" subtype="schedInfo" type="oc"/>
      <seeing>1</seeing>
      <MetaData>
        <unique>true</unique>
        <gui>
          <collapsed>false</collapsed>
        </gui>
      </MetaData>
      <tauBand>1</tauBand>
    </SpSiteQualityObsComp>
    <SpTelescopeObsComp>
      <ItemData name="new" package="gemini.sp.obsComp" subtype="targetList" type="oc"/>
      <MetaData>
        <unique>true</unique>
        <gui>
          <collapsed>false</collapsed>
          <selectedTelescopePos>Base</selectedTelescopePos>
        </gui>
      </MetaData>
      <base>
        <target type="science">
          <targetName>NGC Test</targetName>
          <hmsdegSystem type="J2000">
            <c1>00:00:00</c1>
            <c2>+00:00:00</c2>
          </hmsdegSystem>
        </target>
      </base>
    </SpTelescopeObsComp>
    <SpObs done="0" remaining="1" msb="false">
      <ItemData name="new" package="gemini.sp" subtype="none" type="ob"/>
      <MetaData>
        <gui>
          <collapsed>false</collapsed>
        </gui>
      </MetaData>
      <standard>false</standard>
      <SpIterFolder>
        <ItemData name="new" package="gemini.sp.iter" subtype="none" type="if"/>
        <MetaData>
          <gui>
            <collapsed>false</collapsed>
          </gui>
        </MetaData>
        <SpIterObserve>
          <ItemData name="new" package="gemini.sp.iter" subtype="observe" type="ic"/>
          <repeatCount>1</repeatCount>
          <MetaData>
            <gui>
              <collapsed>false</collapsed>
            </gui>
          </MetaData>
        </SpIterObserve>
      </SpIterFolder>
    </SpObs>
  </SpMSB>
    <SpObs done="0" remaining="22" msb="true">
      <ItemData name="new" package="gemini.sp" subtype="none" type="ob"/>
      <MetaData>
        <gui>
          <collapsed>false</collapsed>
        </gui>
      </MetaData>
      <standard>false</standard>
      <SpIterFolder>
        <ItemData name="new" package="gemini.sp.iter" subtype="none" type="if"/>
        <MetaData>
          <gui>
            <collapsed>false</collapsed>
          </gui>
        </MetaData>
        <SpIterObserve>
          <ItemData name="new" package="gemini.sp.iter" subtype="observe" type="ic"/>
          <repeatCount>1</repeatCount>
          <MetaData>
            <gui>
              <collapsed>false</collapsed>
            </gui>
          </MetaData>
        </SpIterObserve>
      </SpIterFolder>
    </SpObs>
</SpProg>
