#!perl

# Test the behaviour of OMP::MSB objects.

# Copyright (C) 2002-2005 Particle Physics and Astronomy Research Council.
# All Rights Reserved.

# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation; either version 2 of the License, or (at your option) any later
# version.

# This program is distributed in the hope that it will be useful,but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
# PARTICULAR PURPOSE. See the GNU General Public License for more details.

# You should have received a copy of the GNU General Public License along with
# this program; if not, write to the Free Software Foundation, Inc., 59 Temple
# Place,Suite 330, Boston, MA  02111-1307, USA

use Test::More tests => 9;

use_ok( "OMP::SciProg" );
use_ok( "OMP::MSB" );


my $sp = new OMP::SciProg( XML => join("\n", <DATA>) );

my $msb = ( $sp->msb )[0];

is($msb->remaining, 2, "Test initial count");

ok(!$msb->isRemoved, "MSB is active");
$msb->msbRemove;
ok($msb->isRemoved, "MSB is removed");

$msb->unRemove;
is($msb->remaining, 2, "Active again");

$msb->remaining_inc(2);
is($msb->remaining, 4, "Inc by 2");

$msb->remaining( -1 );
is($msb->remaining, 3, "dec by 1");

$msb->hasBeenObserved;
is($msb->remaining, 2, "has been observed");


__DATA__
<?xml version="1.0" encoding="ISO-8859-1"?>
<SpProg type="pr" subtype="none">
  <title>Test program for OMP classes</title>
  <meta_gui_collapsed>false</meta_gui_collapsed>
  <country>UK</country>
  <projectID>TJ01</projectID>
  <meta_gui_filename>test.xml</meta_gui_filename>
  <pi>Tim Jenness</pi>
  <SpNote type="no" subtype="none">
    <note>This is a test program for the OMP server classes. It tries to
      cover some of the special cases including calibration
      observations, identical observations and MSB repeat counters
      greater than 1.  It will also attempt to experiment with the logic folders.</note>
    <meta_gui_collapsed>false</meta_gui_collapsed>
    <title>Test program</title>
  </SpNote>
  <SpSiteQualityObsComp id="4" type="oc" subtype="schedInfo">
    <seeing>
      <min>0.0</min>
      <max>0.4</max>
    </seeing>
    <meta_unique>true</meta_unique>
    <meta_gui_collapsed>false</meta_gui_collapsed>
    <csoTau>
      <min>0.0</min>
      <max>0.09</max>
    </csoTau>
  </SpSiteQualityObsComp>
  <SpMSB remaining="2" type="og" subtype="msb">
    <SpSiteQualityObsCompRef idref="0"/>
    <title>UFTI standards</title>
    <meta_gui_collapsed>false</meta_gui_collapsed>
    <priority>Low</priority>
    <estimatedDuration units="seconds">180.0</estimatedDuration>
    <elapsedTime>180.0</elapsedTime>
    <SpSiteQualityObsComp id="0" type="oc" subtype="schedInfo">
      <seeing>
        <min>0.0</min>
        <max>0.4</max>
      </seeing>
      <meta_unique>true</meta_unique>
      <meta_gui_collapsed>false</meta_gui_collapsed>
      <csoTau>
        <min>0.0</min>
        <max>0.09</max>
      </csoTau>
    </SpSiteQualityObsComp>
    <SpObs msb="false" optional="false" remaining="1" type="ob" subtype="none">
      <chainedToNext>false</chainedToNext>
      <estimatedDuration units="seconds">120.0</estimatedDuration>
      <chainedToPrev>false</chainedToPrev>
      <title>FS1_00h33m_-12d Z-band</title>
      <elapsedTime>120.0</elapsedTime>
      <meta_gui_collapsed>true</meta_gui_collapsed>
      <standard>true</standard>
      <SpTelescopeObsComp type="oc" subtype="targetList">
        <chopThrow></chopThrow>
        <chopSystem></chopSystem>
        <BASE TYPE="Base">
          <target>
            <targetName>FS1</targetName>
            <spherSystem SYSTEM="J2000">
              <c1>00  33 54.407</c1>
              <c2>-12 07 57.0</c2>
            </spherSystem>
          </target>
        </BASE>
        <chopAngle></chopAngle>
        <meta_unique>true</meta_unique>
        <meta_gui_collapsed>false</meta_gui_collapsed>
        <meta_gui_selectedTelescopePos>GUIDE</meta_gui_selectedTelescopePos>
        <chopping>false</chopping>
        <BASE TYPE="GUIDE">
          <target>
            <targetName></targetName>
            <spherSystem SYSTEM="J2000">
              <c1>0:33:54.407</c1>
              <c2>-12:07:57.0</c2>
            </spherSystem>
          </target>
        </BASE>
      </SpTelescopeObsComp>
      <SpInstUFTI type="oc" subtype="inst.UFTI">
        <posAngle>0.0</posAngle>
        <instPort>East</instPort>
        <meta_version>1.0</meta_version>
        <readoutArea>512x512</readoutArea>
        <coadds>1</coadds>
        <sourceMag>13-14</sourceMag>
        <instAper>
          <value>-12.86</value>
          <value>17.51</value>
          <value>0.0</value>
          <value>1.033</value>
        </instAper>
        <polariser>none</polariser>
        <filter>Z</filter>
        <exposureTime>20.0</exposureTime>
        <title>- set configuration</title>
        <meta_unique>true</meta_unique>
        <acqMode>Normal+NDSTARE</acqMode>
        <meta_gui_collapsed>false</meta_gui_collapsed>
      </SpInstUFTI>
      <SpDRRecipe type="oc" subtype="DRRecipe">
        <SkyRecipe>REDUCE_SKY</SkyRecipe>
        <FlatRecipe>REDUCE_FLAT</FlatRecipe>
        <ArcRecipe>REDUCE_ARC</ArcRecipe>
        <DarkRecipe>REDUCE_DARK</DarkRecipe>
        <title>BRIGHT_POINT_SOURCE_APHOT</title>
        <meta_unique>true</meta_unique>
        <BiasInGroup>false</BiasInGroup>
        <DarkInGroup>false</DarkInGroup>
        <BiasRecipe>REDUCE_BIAS</BiasRecipe>
        <meta_gui_collapsed>false</meta_gui_collapsed>
        <ObjectRecipe>BRIGHT_POINT_SOURCE_APHOT</ObjectRecipe>
        <DRRecipe>JITTER5_SELF_FLAT</DRRecipe>
        <ArcInGroup>false</ArcInGroup>
        <FlatInGroup>false</FlatInGroup>
        <SkyInGroup>true</SkyInGroup>
        <ObjectInGroup>true</ObjectInGroup>
      </SpDRRecipe>
      <SpIterFolder type="if" subtype="none">
        <meta_gui_collapsed>false</meta_gui_collapsed>
        <SpIterDarkObs type="ic" subtype="darkObs">
          <coadds>1</coadds>
          <exposureTime>20.0</exposureTime>
          <repeatCount>1</repeatCount>
          <meta_gui_collapsed>false</meta_gui_collapsed>
        </SpIterDarkObs>
        <SpIterRepeat type="ic" subtype="repeat">
          <meta_gui_collapsed>false</meta_gui_collapsed>
          <SpIterOffset type="ic" subtype="offset">
            <meta_gui_selectedOffsetPos>Offset8</meta_gui_selectedOffsetPos>
            <obsArea>
              <PA>0.0</PA>
              <OFFSET>
                <DC1>11.0</DC1>
                <DC2>10.0</DC2>
              </OFFSET>
              <OFFSET>
                <DC1>-10.0</DC1>
                <DC2>11.0</DC2>
              </OFFSET>
              <OFFSET>
                <DC1>-12.0</DC1>
                <DC2>-10.0</DC2>
              </OFFSET>
              <OFFSET>
                <DC1>11.0</DC1>
                <DC2>-11.0</DC2>
              </OFFSET>
              <OFFSET>
                <DC1>0.0</DC1>
                <DC2>0.0</DC2>
              </OFFSET>
            </obsArea>
            <title>jitter_5_10as</title>
            <meta_gui_collapsed>false</meta_gui_collapsed>
            <SpIterObserve type="ic" subtype="observe">
              <repeatCount>1</repeatCount>
              <meta_gui_collapsed>false</meta_gui_collapsed>
            </SpIterObserve>
          </SpIterOffset>
        </SpIterRepeat>
        <SpIterOffset type="ic" subtype="offset">
          <meta_gui_selectedOffsetPos>Offset0</meta_gui_selectedOffsetPos>
          <meta_gui_collapsed>false</meta_gui_collapsed>
          <obsArea>
            <PA>0.0</PA>
            <OFFSET>
              <DC1>0.0</DC1>
              <DC2>0.0</DC2>
            </OFFSET>
          </obsArea>
        </SpIterOffset>
      </SpIterFolder>
    </SpObs>
  </SpMSB>
</SpProg>
