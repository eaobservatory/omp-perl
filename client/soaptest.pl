#!perl

# Test the OMP::SciProg class

use warnings;
use strict;
use SOAP::Lite;
use OMP::SpServer;

# Strings
# Read the data handle
local $/ = undef;
my $xml = <DATA>;

print SOAP::Lite
  -> uri('http://www.jach.hawaii.edu/OMP::SpServer')
  -> proxy('http://www-private.jach.hawaii.edu:81/cgi-bin/spsrv.pl')
  -> storeProgram($xml,"junk")
  -> result;

#my $result = OMP::SpServer->storeProgram($xml,"junk");
#print "Result: $result\n";
#print OMP::SpServer->fetchProgram("M01BU54", "junk");


# Some XML
__DATA__
<?xml version="1.0" encoding="ISO-8859-1"?>
<SpProg>
  <projectID>M01BH01</projectID>
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
    <SpObs remaining="3" msb="true">
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
    <SpObs remaining="4" msb="true">
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
          <repeatCount>2</repeatCount>
          <MetaData>
            <gui>
              <collapsed>false</collapsed>
            </gui>
          </MetaData>
        </SpIterObserve>
      </SpIterFolder>
    </SpObs>
</SpProg>
