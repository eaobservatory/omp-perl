package OMP::WORF::CGI;

=head1 NAME

OMP::WORF::CGI - WWW Observing Remotely Facility CGI functions

=head1 SYNOPSIS

use OMP::WORF::CGI;

=head1 DESCRIPTION

This module provides routines used for CGI-related functions for
WORF - form variable verification and form creation. Non-CGI-related
routines for WORF are provided by OMP::WORF;

=cut

use strict;
use warnings;
use Carp;

use CGI;
use PDL::Graphics::LUT;

our $VERSION = (qw$Revision$ )[1];

require Exporter;

our @ISA = qw/Exporter/;
our @EXPORT = qw( print_display_properties verify_query );
our %EXPORT_TAGS = (
                    'all' => [ @EXPORT ]
                    );

#Exporter::export_tags(qw/ all /);

my @instruments = qw(cgs4 ufti ircam michelle);
my @ctabs = lut_names();

=head1 Routines

All routines are exported by default.

=over 4

=item B<print_display_properties>

Prints the HTML form that allows users to change display properties.

  print_display_properties( $instrument, $file, $obstype );

The file argument is the filename without the path, and the obstype
argument is either 'raw' or 'reduced', depending on observation type.

=cut

sub print_display_properties {

  my $instrument = shift;
  my $file = shift;
  my $obstype = shift;

  my $query = new CGI;

  print $query->startform(undef, "worf.pl");
  print "Show me the ";
  print $query->popup_menu(-name=>'size',
                           -values=>['640','960','1280','128'],
                           -labels=>{640=>'small (~150K)',
                                     960=>'medium (~300K)',
                                     1280=>'large (~450K)',
                                     128=>'thumbnail'},
                           );
  print $query->popup_menu('type', ['image','spectrum']) . "<br>\n<br>\n";
  print "\n<b>Image settings:</b><br>\n";

  print "Auto-cut (percentage): ", $query->popup_menu('autocut', ['100','99','98','95','90','80','70','50']) . "<br>\n";
  print "X axis: ", $query->radio_group('xcrop',['full','crop']);
  print " from ", $query->textfield('xcropstart','',8,8);
  print " to ", $query->textfield('xcropend','',8,8) . "<br>\n";
  print "Y axis: ", $query->radio_group('ycrop',['full','crop']);
  print " from ", $query->textfield('ycropstart','',8,8);
  print " to ", $query->textfield('ycropend','',8,8) . "<br>\n";

  print "Colour table ",$query->popup_menu('lut',\@ctabs, 'heat') . "<br>\n";

  print "<b>Spectrum settings:</b><br>\n";
  print "Row or Column range: From ",$query->textfield('rstart','28',4,4);
  print " to ",$query->textfield('rend','30',4,4);
  print "   Cut: ",$query->radio_group('cut',['horizontal','vertical']);
  
# get xstart xend

  print "<br> X axis:  ",$query->radio_group('xscale',['autoscaled','set']);
  print "  from  ",$query->textfield('xstart','',8,8);
  print "  to  ",$query->textfield('xend','',8,8);

# get ystart yend

  print "<br> Y axis: ",$query->radio_group('yscale',['autoscaled','set']);
  print "  from  ",$query->textfield('ystart','',8,20);
  print "  to  ",$query->textfield('yend','',8,20);

  print "<br>\n";

  print $query->hidden(-name=>'file', -default=>[$file]);
  print $query->hidden(-name=>'view', -default=>['yes']);
  print $query->hidden(-name=>'instrument', -default=>[$instrument]);
  print $query->hidden(-name=>'obstype', -default=>[$obstype]);

  print $query->submit('modify');
  print $query->defaults('defaults');

  print $query->endform;
}

=item B<verify_query>

Verifies values in a CGI query hash. To be used for the CGI query object
formed when the form printed by B<print_display_properties> is submitted.

  verify_query( \%query, \%verified );

The query argument must be a hash reference optionally containing observation
information as follows (listed are valid keys that will be verified):

=over 8

=item * 'view' - list all observations for a given instrument? ( yes | no )

=item * 'file' - filename of observation, not including path.

=item * 'instrument' - instrument name

=item * 'type' - type of image ( image | spectrum )

=item * 'obstype' - type of observation ( raw | reduced )

=item * 'cut' - row or column cut ( horizontal | vertical )

=item * 'rstart' - starting row/column for cut

=item * 'rend' - ending row/column for cut

=item * 'xscale' - scale the spectrum's x-dimension? ( autoscaled | set )

=item * 'xstart' - starting position for scaled x-dimension

=item * 'xend' - ending position for scaled x-dimension

=item * 'yscale' - scale the spectrum's y-dimension? ( autoscaled | set )

=item * 'ystart' - starting position for scaled y-dimension

=item * 'yend' - ending position for scaled y-dimension

=item * 'autocut' - scale data by cutting percentages ( 100 | 99 | 98 | 95 | 90 | 80 | 70 | 50 )

=item * 'xcrop' - crop the image's x-dimension? ( full | crop )

=item * 'xcropstart' - starting positon for cropped x-dimension

=item * 'xcropend' - ending position for cropped x-dimension

=item * 'ycrop' - crop the image's y-dimension? ( full | crop )

=item * 'ycropstart' - starting position for cropped y-dimension

=item * 'ycropend' - ending position for cropped y dimension

=item * 'lut' - lookup table for colour tables. Should be one of the colour
tables in PDL::Graphics::LUT;

=item * 'size' - size of output graphic ( 128 | 640 | 960 | 1280 )

=back

The verified argument will contain verified values for use by routines
in OMP::WORF.

=cut

sub verify_query {
  my $q = shift;
  my $v = shift;

  if($q->{view}) {

# The 'view' parameter must be either yes or no.
# Default to 'no'.

    if($q->{view} eq 'yes') {
      $v->{view} = 'yes';
    } else {
      $v->{view} = 'no';
    }
  } else {
    $v->{view} = 'no';
  }

  if($q->{file}) {

# The 'file' parameter must be just a filename. No pipes, slashes, or other weird
# characters that can allow for shell manipulation. If it doesn't match the proper
# format, set it to an empty string.

    # first, strip out anything that's not a letter, a digit, an underscore, or a period
    
    my $t_file = $q->{file};
    $t_file =~ s/[^a-zA-Z0-9\._]//g;
    
    # now check to make sure it's in some sort of format -- one or two letters, eight digits,
    # an underscore, and ending with .sdf
    
    if($t_file =~ /^[a-zA-Z]{1,2}\d{8}_\w+\.sdf$/) {
      $v->{file} = $t_file;
    } else {
      $v->{file} = '';
    }
  } else {
    $v->{file} = '';
  }
  
  if($q->{instrument}) {

# The 'instrument' parameter must match one of the strings listed in the @instrument array.
# If it doesn't, set it to an empty string.
  
    # first, strip out anything that's not a letter or a number
    
    my $t_instrument = $q->{instrument};
    $t_instrument =~ s/[^a-zA-Z0-9]//g;
    
    # this parameter needs to match exactly one of the strings listed in @instruments
    
    my $match = 0;
    
    foreach my $t_inst (@instruments) {
      if($t_instrument eq $t_inst) {
        $v->{instrument} = $t_inst;
        $match = 1;
      }
    }
    if ($match == 0) {
      $v->{instrument} = "";
    }
  } else {
    $v->{instrument} = '';
  }

  if($q->{obstype}) {

# The 'obstype' parameter must be either 'raw' or 'reduced'.
# Default to 'reduced'.

    if($q->{obstype} eq 'raw') {
      $v->{obstype} = 'raw';
    } else {
      $v->{obstype} = 'reduced';
    }
  } else {
    $v->{obstype} = 'reduced';
  }
  
  if($q->{all}) {

# The 'all' parameter must be either 'yes' or 'no'.
# Default to 'no'.

    if($q->{all} eq 'yes') {
      $v->{all} = 'yes';
    } else {
      $v->{all} = 'no';
    }
  } else {
    $v->{all} = 'no';
  }
  
  if($q->{rstart}) {
    
# The 'rstart' parameter must be digits.

    $v->{rstart} = $q->{rstart};
    $v->{rstart} =~ s/[^0-9]//g;
  } else {
    $v->{rstart} = 0;
  }

  if($q->{rend}) {

# The 'rend' parameter must be digits.
    
    $v->{rend} = $q->{rend};
    $v->{rend} =~ s/[^0-9]//g;
  } else {
    $v->{rend} = 0;
  }

  if($q->{cut}) {

# The 'cut' parameter must be either 'horizontal' or 'vertical'.
# Default to 'horizontal'.
    
    if($q->{cut} eq 'vertical') {
      $v->{cut} = 'vertical';
    } else {
      $v->{cut} = 'horizontal';
    }
  } else {
    $v->{cut} = 'horizontal';
  }
  
  if($q->{xscale}) {

# The 'xscale' parameter must be either 'autoscaled' or 'set'.
# Default to 'autoscaled'.

    if($q->{xscale} eq 'set') {
      $v->{xscale} = 'set';
    } else {
      $v->{xscale} = 'autoscaled';
    }
  } else {
    $v->{xscale} = 'autoscaled';
  }
  
  if($q->{xstart}) {

# The 'xstart' parameter must be digits.
    
    $v->{xstart} = $q->{xstart};
    $v->{xstart} =~ s/[^0-9\.]//g;
  } else {
    $v->{xstart} = 0;
  }
  
  if($q->{xend}) {

# The 'xend' parameter must be digits.

    $v->{xend} = $q->{xend};
    $v->{xend} =~ s/[^0-9\.]//g;
  } else {
    $v->{xend} = 0;
  }

  if($q->{yscale}) {

# The 'yscale' parameter must be either 'autoscaled' or 'set'.
# Default to 'autoscaled'.

    if($q->{yscale} eq 'set') {
      $v->{yscale} = 'set';
    } else {
      $v->{yscale} = 'autoscaled';
    }
  } else {
    $v->{yscale} = 'autoscaled';
  }
  
  if($q->{ystart}) {

# The 'ystart' parameter must be a number. This can include
# exponents (like 1.0e-12)

    $v->{ystart} = $q->{ystart};
    $v->{ystart} =~ s/[^0-9\.e\-]//g;
  } else {
    $v->{ystart} = 0;
  }

  if($q->{yend}) {

# The 'yend' parameter must be a number. This can include
# exponents (like 1.0e-12)

    $v->{yend} = $q->{yend};
    $v->{yend} =~ s/[^0-9\.e\-]//g;
  } else {
    $v->{yend} = 0;
  }
  
  if($q->{type}) {

# The 'type' parameter must be either 'image' or 'spectrum'.
# Default to 'image'.

    if($q->{type} eq 'spectrum') {
      $v->{type} = 'spectrum';
    } else {
      $v->{type} = 'image';
    }
  } else {
    $v->{type} = 'image';
  }
  
  if($q->{autocut}) {

# The 'autocut' parameter must be digits.
# Default to '100'.

    $v->{autocut} = $q->{autocut};
    $v->{autocut} =~ s/[^0-9\.]//g;
  } else {
    $v->{autocut} = 100;
  }
  
  if($q->{xcrop}) {

# The 'xcrop' parameter must be either 'full' or 'crop'.
# Default to 'full'.

    if($q->{xcrop} eq 'crop') {
      $v->{xcrop} = 'crop';
    } else {
      $v->{xcrop} = 'full';
    }
  } else {
    $v->{xcrop} = 'full';
  }
  
  if($q->{xcropstart}) {

# The 'xcropstart' parameter must be digits.
# Default to '0'.

    $v->{xcropstart} = $q->{xcropstart};
    $v->{xcropstart} =~ s/[^0-9\.]//g;
  } else {
    $v->{xcropstart} = 0;
  }
  
  if($q->{xcropend}) {

# The 'xcropend' parameter must be digits.
# Default to '0'.

    $v->{xcropend} = $q->{xcropend};
    $v->{xcropend} =~ s/[^0-9\.]//g;
  } else {
    $v->{xcropend} = 0;
  }
  
  if($q->{ycrop}) {

# The 'ycrop' parameter must be either 'full' or 'crop'.
# Default to 'full'.

    if($q->{ycrop} eq 'crop') {
      $v->{ycrop} = 'crop';
    } else {
      $v->{ycrop} = 'full';
    }
  } else {
    $v->{ycrop} = 'full';
  }
  
  if($q->{ycropstart}) {

# The 'ycropstart' parameter must be digits.
# Default to '0'.

    $v->{ycropstart} = $q->{ycropstart};
    $v->{ycropstart} =~ s/[^0-9\.]//g;
  } else {
    $v->{ycropstart} = 0;
  }
  
  if($q->{ycropend}) {
    
# The 'ycropend' parameter must be digits.
# Default to '0'.

    $v->{ycropend} = $q->{ycropend};
    $v->{ycropend} =~ s/[^0-9\.]//g;
  } else {
    $v->{ycropend} = 0;
  }
  
  if($q->{lut}) {

# The 'lut' parameter must be one of the standard lookup tables.
# Default is 'standard'.
    
    # first, strip out anything that's not a letter or a number
    
    my $t_lut = $q->{lut};
    $t_lut =~ s/[^a-zA-Z0-9]//g;
    
    # this parameter needs to match exactly one of the strings listed in @ctabs
    
    my $match = 0;
    
    foreach my $t_ctab (@ctabs) {
      if($t_lut eq $t_ctab) {
        $v->{lut} = $t_ctab;
        $match = 1;
      }
    }
    if ($match == 0) {
      $v->{lut} = 'heat';
    }
  } else {
    $v->{lut} = 'heat';
  }
  
  if($q->{size}) {

# The 'size' parameter must be [128 | 640 | 960 | 1280]
# Default is '640'.

    $v->{size} = $q->{size};
    $v->{size} =~ s/[^0-9]//;
  } else {
    $v->{size} = 640;
  }
}

=back

=head1 AUTHOR

Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
