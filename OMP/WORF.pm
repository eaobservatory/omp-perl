package OMP::WORF;

=head1 NAME

OMP::WORF - WWW Observing Remotely Facility non-CGI functions

=head1 SYNOPSIS

use OMP::WORF;

use OMP::WORF qw( print_summary, display_observation );

=head1 DESCRIPTION

This class handles all the routines that deal with image creation,
display, and summary for WORF. CGI-related routines for WORF are
handled in OMP::WORF::CGI.

=cut

use strict;
use warnings;
use Carp;

use lib qw( /ukirt_sw/oracdr/lib/perl5 );
use ORAC::Frame::NDF;
use ORAC::Inst::Defn qw( orac_configure_for_instrument );

use lib qw( /jac_sw/omp/test/omp/msbserver );
use OMP::CGI;

our $VERSION = (qw$Revision$ )[1];

require Exporter;

our @ISA = qw/Exporter/;
our @EXPORT = qw( display_observation list_raw_observations list_reduced_observations
                obsnumsort pad print_footer print_header print_summary );
our @EXPORT_OK = qw( _file_matches_project _get_raw_directory _get_reduced_directory
                   %display_suffix %headers );
our %EXPORT_TAGS = (
                    'all' => [ qw( @EXPORT @EXPORT_OK ) ],
                    'variables' => [ qw( %display_suffix %headers ) ],
                    'routines' => [ qw( _file_matches_project _get_raw_directory
                                        _get_reduced_directory ) ]
                    );
#Exporter::export_tags(qw/ all variables routines /);

=item B<Variables>

The following variables may be exported, but are not by default.

=over 4

=item B<%headers>

Provides a header translation table for B<list_raw_observations> and
B<list_reduced_observations>.

  $ufti_objectname_header = $headers{ufti}{objname};

=cut

our %headers = (ufti => {OBJNAME => "OBJECT",
                        UTSTART => "DATE-OBS",
                        EXPTIME => "EXP_TIME",
                        FILTER => "FILTER",
                        GRATING => "",
                        WAVELENGTH => "",
                        AIRMASS => "AMSTART",
                        RA => "RABASE",
                        DEC => "DECBASE",
                        PROJECT => "PROJECT",
                        MSBID => "MSBID" },
               michelle => {OBJNAME => "OBJECT",
                            UTSTART => "DATE-OBS",
                            EXPTIME => "OBSTIME",
                            FILTER => "FILTER",
                            GRATING => "GRATNAME",
                            WAVELENGTH => "GRATPOS",
                            AIRMASS => "AMSTART",
                            RA => "RABASE",
                            DEC => "DECBASE",
                            PROJECT => "PROJECT",
                            MSBID => "MSBID" },
               cgs4 => {OBJNAME => "OBJECT",
                        UTSTART => "RUTSTART",
                        EXPTIME => "EXPOSED",
                        FILTER => "",
                        GRATING => "GRATING",
                        WAVELENGTH => "GLAMBDA",
                        AIRMASS => "AMSTART",
                        RA => "MEANRA",
                        DEC => "MEANDEC",
                        PROJECT => "PROJECT",
                        MSBID => "MSBID" },
               ircam => {OBJNAME => "OBJECT",
                         UTSTART => "RUTSTART",
                         EXPTIME => "EXPOSED",
                         FILTER => "FILTER",
                         GRATING => "",
                         WAVELENGTH => "",
                         AIRMASS => "AMSTART",
                         RA => "MEANRA",
                         DEC => "MEANDEC",
                         PROJECT => "PROJECT",
                         MSBID => "MSBID"} );

=item B<%displaysuffix>

Provides a list of file suffices that dictate whether or not a
reduced data file will be displayed for a given instrument. If
the list is empty for a given instrument, then all files will
be displayed.

=cut

our %displaysuffix = (ufti => [],
                  michelle => [],
                  cgs4 => ["fc","dbs","sp","ypr"],
                  ircam => [] );

=back

=head1 Routines

Routines beginning with an underscore are deemed to be private and
do not form part of the default public interface. They can be exported
if needed.

=over 4

=item B<print_summary>

Displays an HTML table listing the latest raw and reduced group
files for a given instrument.

  print_summary( $instrument, $ut, $projectid );

The UT date must be of the form yyyymmdd. The project ID is used to display
a summary for that project.

=cut

sub print_summary {
  my ( $instrument, $ut, $projectid, $password ) = @_;

  my @groupfiles;
  my @groupfilessuffix;
  my @projectgroupfiles;
  my @group;
  my @raw;
  my @projectrawfiles;
  my ( $latestgroup, $latestraw );

  my @files = ();
  my $directory = _get_reduced_directory( $instrument, $ut );
  if( -e $directory ) {
    opendir(FILES, $directory);
    @files = grep(!/^\./, readdir(FILES)); # skip dot files
    closedir(FILES);
  } else {
    @files = ();
  }

# Okay, now we have a list of all of the files in the directory. Let's
# trim out everything that isn't an NDF

  @files = grep(/sdf$/, @files);

# Alrighty. Reduced group files are (I'm assuming) ones that begin
# with a 'g' and have two letters followed by the UT date. Let's
# grab all of them.

  @groupfiles = grep(/^g[a-zA-Z]/, @files);

# We're only concerned with files that have suffixes that are listed
# in @displaysuffix{$instrument}. If that array is empty, don't trim
# the file list.

  if(scalar(@{$displaysuffix{$instrument}}) != 0) {
    foreach my $elm1 (@groupfiles) {
      foreach my $elm2 (@{$displaysuffix{$instrument}}) {
        if ($elm1 =~ /_$elm2[\._]/) {
          push @groupfilessuffix, $elm1;
        }
      }
    }
  } else {
    @groupfilessuffix = @groupfiles;
  }

# And we're also only concerned with files that belong to the specific
# OMP project.

  foreach my $file (@groupfilessuffix) {
    if( _file_matches_project($directory . "/" . $file, $projectid, $instrument)) {
      push @projectgroupfiles, $file;
    }
  }

# Now sort them according to the observation number
  my $i;
  my @foo;
  for($i = 0; $i <= $#projectgroupfiles; $i++) {
    $projectgroupfiles[$i] =~ /\d{8}_(\d+)_/ && ($foo[$i] = $1);
  }

  @group = sort obsnumsort @foo;

# And, the latest reduced group file is...

  my @baz = grep(/\d{8}_$group[$#group]_/, @projectgroupfiles);
  $latestgroup = $baz[0];

# Now let's do basically the same for the raw data files.

  $directory = _get_raw_directory($instrument, $ut);

  if( -e $directory ) {
    opendir(FILES, $directory);
    @files = grep(!/^\./, readdir(FILES));
    closedir(FILES);
  } else {
    @files = ();
  }

  @files = grep(/sdf$/, @files);

# We don't need to differentiate between group files and anything else,
# so just sort them by observation number, after we only grab the ones
# for the specific OMP project.

  my @bar;
  for($i = 0; $i <= $#files; $i++) {
    $files[$i] =~ /\d{8}_(\d{5})/ && ($bar[$i] = pad($1,'0',5));
  }

  foreach my $file (@files) {
    my $tfile;
    if($instrument eq "cgs4") {
      ($tfile = $file) =~ s/\.sdf$/\.i1/;
    } elsif ($instrument eq "ufti") {
      ($tfile = $file) =~ s/\.sdf$/\.header/;
    } else {
      $tfile = $file;
    }
    if( _file_matches_project($directory . "/" . $tfile, $projectid, $instrument)) {
      push @projectrawfiles, $file;
    }
  }

  @raw = sort {$a <=> $b} @projectrawfiles;

# And, the latest raw observation is...

  @baz = grep(/$raw[$#raw]/, @projectrawfiles);
  $latestraw = $baz[0];

# Now that we've figured out the latest raw and group files, print out
# the status information.

  if($latestgroup || $latestraw) {
    print "<strong>Summary for $instrument:</strong><br>\n";
    print "<table border=1>\n";
    print "<tr><th>UT date</th><th>Latest raw observation</th><th>Latest reduced group observation</th></tr>\n";
    print "<tr><td>$ut</td><td>";
    if($latestraw) {
      print "$latestraw (<a href=\"worf.pl?view=yes&file=$latestraw&instrument=$instrument&obstype=raw\">view</a>)";
    } else {
      print "&nbsp;";
    }
    print "</td><td>";
    if ($latestgroup) {
      print "$latestgroup (<a href=\"worf.pl?view=yes&file=$latestgroup&instrument=$instrument&obstype=reduced\">view</a>)";
    } else {
      print "&nbsp;";
    }
    print "</td></tr>\n";
    print "</table>\n";
  }
}

=item B<display_observation>

Create HTML that will display a graphic for a given observation.

  display_observation( \%args );

Argument must be a hash reference containing observation information as follows:

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

=item * 'width' - width in pixels of graphic

=item * 'height' - height in pixels of graphic

=cut

sub display_observation {

  my $options = shift;

  my ($file, $instrument, $type, $obstype, $cut, $rstart, $rend, $xscale,
      $xstart, $xend, $yscale, $ystart, $yend, $autocut, $xcrop, $xcropstart,
      $xcropend, $ycrop, $ycropstart, $ycropend, $lut, $height, $width);

  $file = $$options{file};
  $instrument = $$options{instrument};
  $type = $$options{type} || "image";
  $obstype = $$options{obstype} || "reduced";
  $cut = $$options{cut} || "horizontal";
  $rstart = $$options{rstart} || 28;
  $rend = $$options{rend} || 30;
  $xscale = $$options{xscale} || "autoscaled";
  $xstart = $$options{xstart};
  $xend = $$options{xend};
  $yscale = $$options{yscale} || "autoscaled";
  $ystart = $$options{ystart};
  $yend = $$options{yend};
  $autocut = $$options{autocut} || 100;
  $xcrop = $$options{xcrop} || "full";
  $xcropstart = $$options{xcropstart};
  $xcropend = $$options{xcropend};
  $ycrop = $$options{ycrop} || "full";
  $ycropstart = $$options{ycropstart};
  $ycropend = $$options{ycropend};
  $lut = $$options{lut} || "heat";
  $width = $$options{width} || 640;
  $height = $$options{height} || 480;

  print "<img src=\"worf_graphic.pl?file=$file&cut=$cut&rstart=$rstart&rend=$rend&xscale=$xscale&xstart=$xstart&xend=$xend&yscale=$yscale&ystart=$ystart&yend=$yend&instrument=$instrument&type=$type&obstype=$obstype&autocut=$autocut&xcrop=$xcrop&xcropstart=$xcropstart&xcropend=$xcropend&ycrop=$ycrop&ycropstart=$ycropstart&ycropend=$ycropend&lut=$lut\" width=\"$width\" height=\"$height\">\n";

}

=item B<list_reduced_observations>

Prints an HTML table listing all reduced observations on a given UT date
for a given instrument and project.

  list_reduced_observations( $instrument, $ut, $project );

The UT date must be of the form yyyymmdd. The project ID is used to display
only the reduced observations for that project.

=cut

sub list_reduced_observations {
  my ($instrument, $ut, $project) = @_;
  my @files;
  my %data;
  my ($objname, $utstart, $exptime, $filter, $grating, $wavelength, $airmass, $RA, $dec, $fileproject, $msbid);
  my $currentproject = "NOPROJECT";
  my $currentmsbid = "";
  my $first = 1;
  my $reduceddir = _get_reduced_directory( $instrument, $ut );
  if( -d $reduceddir ) {
    opendir(FILES, $reduceddir);
    @files = grep(!/^\./, readdir(FILES));
    closedir(FILES);
    @files = grep(/sdf$/, @files);
    @files = grep(/^[a-zA-Z]{2}\d{8}/, @files);

# Sort the files according to observation number

    @files = sort obsnumsort @files;

    print "<hr>\n";
    print "<strong>Reduced group observations for $instrument on $ut</strong><br>\n";
    foreach my $file (@files) {
      if($file =~ /^([a-zA-Z]{2})($ut)_(\d+)(_?)(\w*)\.(\w+)/) {
        my ($prefix, $null, $obsnum, $null2, $suffix, $extension) = ($1, $2, $3, $4, $5, $6);

# Find out if the suffix is in @displaysuffix{$instrument}, if that array
# is not empty.

        my $match = 0;
        if(scalar(@{$displaysuffix{$instrument}}) != 0) {
          foreach my $elm (@{$displaysuffix{$instrument}}) {
            if ($suffix =~ /^$elm$/) {
              $match = 1;
            }
          }
        } else {
          $match = 1;
        }
        if(($match) || (length($suffix . "") == 0)) {
          my $fullfile = $reduceddir . "/" . $file;

          my $Frm = new ORAC::Frame::NDF($fullfile);
          $Frm->readhdr;

# Get the headers from each frame. We'll present this information to the
# user so they can make a more informed decision.

          $objname = $Frm->hdr($headers{$instrument}{'OBJNAME'});
          $utstart = $Frm->hdr($headers{$instrument}{'UTSTART'});
          $exptime = $Frm->hdr($headers{$instrument}{'EXPTIME'});
          $filter = $Frm->hdr($headers{$instrument}{'FILTER'});
          $grating = $Frm->hdr($headers{$instrument}{'GRATING'});
          $wavelength = $Frm->hdr($headers{$instrument}{'WAVELENGTH'});
          $airmass = $Frm->hdr($headers{$instrument}{'AIRMASS'});
          $RA = $Frm->hdr($headers{$instrument}{'RA'});
          $dec = $Frm->hdr($headers{$instrument}{'DEC'});
          $fileproject = $Frm->hdr($headers{$instrument}{'PROJECT'});
          $msbid = $Frm->hdr($headers{$instrument}{'MSBID'});

# Only list files for the specific project (or if the override 'staff' project
# is being used.

          if(($project eq 'staff') || (uc($fileproject) eq uc($project))) {

# If the current project does not match the project for the current frame,
# write a new header.

            if(uc($fileproject) ne uc($currentproject)) {
              if(!$first) {
                print "</table>";
              } else {
                $first = 0;
              }
              print "<strong>Project:</strong> ";
              print $fileproject || "";
              print " <strong>MSBID:</strong> ";
              print $msbid || "";
              print "<br>\n";
              print "<table border=\"1\">\n";
              print "<tr><th>observation number</th><th>object name</th><th>UT start</th><th>exposure time</th><th>filter</th><th>grating</th><th>central wavelength</th><th>airmass</th><th>file suffix</th><th>view data</th><th>download file</th></tr>\n";
              $currentproject = $fileproject;
              $currentmsbid = $msbid;
            }
            if( ( uc($fileproject) eq uc($currentproject) ) && ( uc($msbid) ne uc($currentmsbid))) {
              if(!$first) {
                print "</table>\n";
              } else {
                $first = 0;
              }
              print "<strong>Project:</strong> ";
              print $fileproject || "";
              print " <strong>MSBID:</strong> ";
              print $msbid || "";
              print "<br>\n";
              print "<table border=\"1\">\n";
              print "<tr><th>observation number</th><th>object name</th><th>UT start</th><th>exposure time</th><th>filter</th><th>grating</th><th>central wavelength</th><th>airmass</th><th>file suffix</th><th>view data</th><th>download file</th></tr>\n";
              $currentmsbid = $msbid;
            }
          print "<tr><td>";
          print $obsnum || "";
          print "</td><td>";
          print $objname || "";
          print "</td><td>";
          print $utstart || "";
          print "</td><td>";
          print $exptime || "";
          print "</td><td>";
          print $filter || "";
          print "</td><td>";
          print $grating || "";
          print "</td><td>";
          print $wavelength || "";
          print "</td><td>";
          print $airmass || "";
          print "</td><td><a href=\"worf.pl?view=yes&instrument=$instrument&file=$file&obstype=reduced\">view</a></td><td><a href=\"worf_file.pl?instrument=$instrument&file=$file&type=reduced\">download</a></td></tr>\n";
          }
        }
      }
    }
    print "</table>\n";
  } else {
    print "Directory for $instrument on $ut reduced data does not exist.<br>\n";
  }
}

=item B<list_raw_observations>

Prints an HTML table listing all raw observations on a given UT date for
a given instrument and project.

  list_raw_observations( $instrument, $ut, $project );

The UT date must be of the form yyyymmdd. The project ID is used to display
only the raw observations for that project.

=cut

sub list_raw_observations {
  my ($instrument, $ut, $project) = @_;
  my @files;
  my %data;
  my ($objname, $utstart, $exptime, $filter, $grating, $wavelength, $airmass, $RA, $dec, $fileproject, $msbid);
  my $currentproject = "NOPROJECT";
  my $currentmsbid = "";
  my $first = 1;
  my $directory = _get_raw_directory( $instrument, $ut );

  if( -d $directory ) {
    opendir(FILES, $directory);
    @files = grep(!/^\./, readdir(FILES));
    closedir(FILES);

# Get all *.sdf and files starting with two letters and eight digits

    @files = grep(/sdf$/, @files);
    @files = grep(/^[a-zA-Z]{1}\d{8}/, @files);

# Sort the files according to observation number

    @files = sort obsnumsort @files;

    print "<hr>\n";
    print "<strong>Raw observations for $instrument on $ut</strong><br>\n";
    foreach my $file (@files) {
      if($file =~ /^([a-zA-Z])($ut)_(\d+)\.(\w+)/) {
        my ($prefix, $null, $obsnum, $extension) = ($1, $2, $3, $4);

        my $fullfile = $directory . "/" . $file;
        $fullfile =~ s/\.sdf$/\.header/;

        my $Frm = new ORAC::Frame::NDF($fullfile);
        $Frm->readhdr;

# Get the headers from each frame. We'll present this information to the
# user so they can make a more informed decision.

        $objname = $Frm->hdr($headers{$instrument}{'OBJNAME'});
        $utstart = $Frm->hdr($headers{$instrument}{'UTSTART'});
        $exptime = $Frm->hdr($headers{$instrument}{'EXPTIME'});
        $filter = $Frm->hdr($headers{$instrument}{'FILTER'});
        $grating = $Frm->hdr($headers{$instrument}{'GRATING'});
        $wavelength = $Frm->hdr($headers{$instrument}{'WAVELENGTH'});
        $airmass = $Frm->hdr($headers{$instrument}{'AIRMASS'});
        $RA = $Frm->hdr($headers{$instrument}{'RA'});
        $dec = $Frm->hdr($headers{$instrument}{'DEC'});
        $fileproject = $Frm->hdr($headers{$instrument}{'PROJECT'});
        $msbid = $Frm->hdr($headers{$instrument}{'MSBID'});

# Only list files for the specific project (or if the override 'staff' project
# is being used.

        if(($project eq 'staff') || (uc($fileproject) eq uc($project))) {

# If the current project does not match the project for the current frame,
# write a new header.

          if(uc($fileproject) ne uc($currentproject)) {
            if(!$first) {
              print "</table>";
            } else {
              $first = 0;
            }
            print "<strong>Project:</strong> ";
            print $fileproject || "";
            print " <strong>MSBID:</strong> ";
            print $msbid || "";
            print "<br>\n";
            print "<table border=\"1\">\n";
            print "<tr><th>observation number</th><th>object name</th><th>UT start</th><th>exposure time</th><th>filter</th><th>grating</th><th>central wavelength</th><th>airmass</th><th>view data</th><th>download file</th></tr>\n";
            $currentproject = $fileproject;
            $currentmsbid = $msbid;
          } elsif( ( uc($fileproject) eq uc($currentproject) ) && ( uc($msbid) ne uc($currentmsbid))) {
            if(!$first) {
              print "</table>\n";
            } else {
              $first = 0;
            }
            print "<strong>Project:</strong> ";
            print $fileproject || "";
            print " <strong>MSBID:</strong> ";
            print $msbid || "";
            print "<br>\n";
            print "<table border=\"1\">\n";
            print "<tr><th>observation number</th><th>object name</th><th>UT start</th><th>exposure time</th><th>filter</th><th>grating</th><th>central wavelength</th><th>airmass</th><th>view data</th><th>download file</th></tr>\n";
            $currentmsbid = $msbid;
          }
          print "<tr><td>";
          print $obsnum || "";
          print "</td><td>";
          print $objname || "";
          print "</td><td>";
          print $utstart || "";
          print "</td><td>";
          print $exptime || "";
          print "</td><td>";
          print $filter || "";
          print "</td><td>";
          print $grating || "";
          print "</td><td>";
          print $wavelength || "";
          print "</td><td>";
          print $airmass || "";
          print "</td><td><a href=\"worf.pl?view=yes&instrument=$instrument&file=$file&obstype=raw\">view</a></td><td><a href=\"worf_file.pl?instrument=$instrument&file=$file&type=raw\">download</a></td></tr>\n";
        }
      }
    }
    print "</table>\n";
  } else {
    print "Directory for $instrument on $ut raw data does not exist.<br>\n";
  }
}

=item B<print_header>

Prints a header.

  print_header();

There are no arguments.

=cut

sub print_header {
  print <<END;
Welcome to WORF. <a href="/JACpublic/UKIRT/software/worf/help.html">Need help?</a><br>
<hr>
END
};

=item B<print_footer>

Prints a footer.

  print_footer();

There are no arguments.

=cut

sub print_footer {
  print <<END;
  <p>
  <hr>
  <address>Last Modification Author: bradc<br>Brad Cavanagh (<a href="mailto:b.cavanagh\@jach.hawaii.edu">b.cavanagh\@jach.hawaii.edu</a>)</address>
</html>
END
};

=item B<obsnumsort>

A sorting routine that sorts by observation number. Used for the 'sort' function.

  @sorted = sort obsnumsort @files;

=cut

sub obsnumsort {
  $a =~ /[a-zA-Z]{1,2}\d{8}_(\d+)/;
  my $a_obsnum = int($1);
  $b =~ /[a-zA-Z]{1,2}\d{8}_(\d+)/;
  my $b_obsnum = int($1);
  $a_obsnum <=> $b_obsnum;
}

=item B<pad>

A routine that pads strings with characters.

  $padded = pad( $string, $character, $endlength );

The string paramter is the initial string, the character parameter is the character
you wish to pad the string with (at the beginning of the string), and the endlength
parameter is the final length in characters of the padded string.

=cut

sub pad {
  my ($string, $character, $endlength) = @_;
  my $result = ($character x ($endlength - length($string))) . $string;
}

=item B<_file_matches_project>

Checks to see if the project ID in a file header matches the given project
ID. Returns 0 (for false) or 1 (for true).

  $match = _file_matches_project( $file, $projectID );

The file parameter must be include the full path to the file.

If the 'staff' project ID is given, then the routine will always return 'true'.

=cut

sub _file_matches_project {
  my $file = shift; # note that this needs to be a full filename
  my $projectid = shift;

  if( lc($projectid) eq 'staff') { return 1; }

  my $Frm = new ORAC::Frame::NDF($file);
  $Frm->readhdr;

  my $project = $Frm->hdr('PROJECT');
  return (uc($project) eq uc($projectid));
}

=item B<_get_raw_directory>

Retrieves the raw data directory given an instrument and UT date.
Simplifies the use of ORAC::Inst::Defn::orac_configure_for_instrument().

  $raw_directory = _get_raw_directory( $instrument, $ut );

The UT date must be in the form yyyymmdd.

This routine modifies the value of $ENV{"ORAC_DATA_IN"}.

=cut

sub _get_raw_directory {
  my $instrument = shift;
  my $ut = shift;

  my %options;
  $options{'ut'} = $ut;
  orac_configure_for_instrument( uc( $instrument ), \%options );

  return $ENV{"ORAC_DATA_IN"};
}

=item B<_get_reduced_directory>

Retrieves the reduced data directory given an instrument and UT date.
Simplifes the use of ORAC::Inst::Defn::orac_configure_for_instrument();

  $reduced_directory = _get_reduced_directory( $instrument, $ut );

The UT date must be in the form yyyymmdd.

This routine modifies the value of $ENV{"ORAC_DATA_OUT"};

=cut

sub _get_reduced_directory {
  my $instrument = shift;
  my $ut = shift;

  my %options;
  $options{'ut'} = $ut;
  orac_configure_for_instrument( uc( $instrument ), \%options );

  return $ENV{"ORAC_DATA_OUT"};
}

=head1 AUTHOR

Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>

=cut

1;
