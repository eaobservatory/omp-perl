#!/local/perl-5.6/bin/perl
#
# WWW Observing Remotely Facility (WORF)
#
# http://www.jach.hawaii.edu/JACpublic/UKIRT/software/worf/
#
# Requirements:
# TBD
#
# Authors: Frossie Economou (f.economou@jach.hawaii.edu)
#          Brad Cavanagh (b.cavanagh@jach.hawaii.edu)

# Set up the environment for PGPLOT

BEGIN {
	$ENV{'PGPLOT_DIR'} = '/star/bin';
  $ENV{'PGPLOT_FONT'} = '/star/bin/grfont.dat';
  $ENV{'PGPLOT_GIF_WIDTH'} = 600;
  $ENV{'PGPLOT_GIF_HEIGHT'} = 450;
  $ENV{'PGPLOT_BACKGROUND'} = 'white';
  $ENV{'PGPLOT_FOREGROUND'} = 'black';
  $ENV{'HDS_SCRATCH'} = "/tmp";
}

# Bring in all the required modules

use CGI;
use CGI::Carp qw/fatalsToBrowser/;
#use NDF;
use PDL::Graphics::LUT;

# we need to point to a different directory to see ORAC and OMP modules

use lib qw(/ukirt_sw/oracdr/lib/perl5);
use ORAC::Frame::NDF;
use ORAC::Inst::Defn qw(orac_configure_for_instrument);

use lib qw(/jac_sw/omp/test/omp/msbserver);
use OMP::CGI;

use strict;

# Set up global variables, system variables, etc.

my ($q_view, $q_file, $q_instrument, $q_obstype, $q_all, $q_rstart, $q_rend,
	  $q_cut, $q_xscale, $q_xstart, $q_xend, $q_yscale, $q_ystart, $q_yend, $q_type,
	  $q_autocut, $q_xcrop, $q_xcropstart, $q_xcropend, $q_ycrop, $q_ycropstart, $q_ycropend,
    $q_lut);

$| = 1;  # make output unbuffered

my @ctabs = lut_names();
my @instruments = ("cgs4", "ircam", "michelle", "ufti");
my $query = new CGI;
my $cgi = new OMP::CGI( CGI => $query );
$cgi->html_title("WORF: UKIRT WWW Observing Remotely Facility");

# Header translation hashes
my %headers = (ufti => {objname => "OBJECT",
												utstart => "DATE-OBS",
												exptime => "EXP_TIME",
												filter => "FILTER",
												grating => "",
												wavelength => "",
												airmass => "AMSTART",
												RA => "RABASE",
												dec => "DECBASE",
											  project => "PROJECT",
											  MSBID => "MSBID" },
							 michelle => {objname => "OBJECT",
														utstart => "DATE-OBS",
														exptime => "OBSTIME",
														filter => "FILTER",
														grating => "GRATNAME",
														wavelength => "GRATPOS",
														airmass => "AMSTART",
														RA => "RABASE",
														dec => "DECBASE",
													  project => "PROJECT",
													  MSBID => "MSBID" },
							 cgs4 => {objname => "OBJECT",
												utstart => "RUTSTART",
												exptime => "EXPOSED",
												filter => "",
												grating => "GRATING",
												wavelength => "GLAMBDA",
												airmass => "AMSTART",
												RA => "MEANRA",
												dec => "MEANDEC",
											  project => "PROJECT",
											  MSBID => "MSBID" } );

# Reduced group file suffixes (for each instrument, a list of suffixes that will
# be displayed for later viewing)
# If the array is empty, then display everything available
my %groupsuffix = (ufti => [],
									 michelle => [],
									 cgs4 => ["fc","dbs","sp","ypr"],
									 ircam => [] );

# Set up the UT date
my $ut;
	{
		my ($sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdist) = gmtime(time);
		$ut = ($year + 1900) . pad($month + 1, "0", 2) . pad($day, "0", 2);

# for demo purposes
#		$ut = "20020310";
	}

# write the page

$cgi->write_page( \&worf_output, \&worf_output );

sub worf_output {
# this subroutine is basically the "main" subroutine for this CGI

# First, pop off the CGI object and the cookie hash

	my $query = shift;
	my %cookie = @_;

	my $projectid = $cookie{'projectid'};
	my $password = $cookie{'password'};

# set up and verify $query variables

	if($query->param('view')) {

# The 'view' parameter must be either yes or no.
# Default to 'no'.

		if($query->param('view') eq 'yes') {
			$q_view = 'yes';
		} else {
			$q_view = 'no';
		}
	} else {
		$q_view = 'no';
	}
	
	if($query->param('file')) {

# The 'file' parameter must be just a filename. No pipes, slashes, or other weird
# characters that can allow for shell manipulation. If it doesn't match the proper
# format, set it to an empty string.

		# first, strip out anything that's not a letter, a digit, an underscore, or a period
		
		my $t_file = $query->param('file');
		$t_file =~ s/[^a-zA-Z0-9\._]//g;
		
		# now check to make sure it's in some sort of format -- one or two letters, eight digits,
		# an underscore, and ending with .sdf
		
		if($t_file =~ /^[a-zA-Z]{1,2}\d{8}_\w+\.sdf$/) {
			$q_file = $t_file;
		} else {
			$q_file = '';
		}
	} else {
		$q_file = '';
	}
	
	if($query->param('instrument')) {

# The 'instrument' parameter must match one of the strings listed in the @instrument array.
# If it doesn't, set it to an empty string.
	
		# first, strip out anything that's not a letter or a number
		
		my $t_instrument = $query->param('instrument');
		$t_instrument =~ s/[^a-zA-Z0-9]//g;
		
		# this parameter needs to match exactly one of the strings listed in @instruments
		
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

	if($query->param('obstype')) {

# The 'obstype' parameter must be either 'raw' or 'reduced'.
# Default to 'reduced'.

		if($query->param('obstype') eq 'raw') {
			$q_obstype = 'raw';
		} else {
			$q_obstype = 'reduced';
		}
	} else {
		$q_obstype = 'reduced';
	}
	
	if($query->param('all')) {

# The 'all' parameter must be either 'yes' or 'no'.
# Default to 'no'.

		if($query->param('all') eq 'yes') {
			$q_all = 'yes';
		} else {
			$q_all = 'no';
		}
	} else {
		$q_all = 'no';
	}
	
	if($query->param('rstart')) {
		
# The 'rstart' parameter must be digits.

		$q_rstart = $query->param('rstart');
		$q_rstart =~ s/[^0-9]//g;
	} else {
		$q_rstart = 0;
	}

	if($query->param('rend')) {

# The 'rend' parameter must be digits.
		
		$q_rend = $query->param('rend');
		$q_rend =~ s/[^0-9]//g;
	} else {
		$q_rend = 0;
	}

	if($query->param('cut')) {

# The 'cut' parameter must be either 'horizontal' or 'vertical'.
# Default to 'horizontal'.
		
		if($query->param('cut') eq 'vertical') {
			$q_cut = 'vertical';
		} else {
			$q_cut = 'horizontal';
		}
	} else {
		$q_cut = 'horizontal';
	}
	
	if($query->param('xscale')) {

# The 'xscale' parameter must be either 'autoscaled' or 'set'.
# Default to 'autoscaled'.

		if($query->param('xscale') eq 'set') {
			$q_xscale = 'set';
		} else {
			$q_xscale = 'autoscaled';
		}
	} else {
		$q_xscale = 'autoscaled';
	}
	
	if($query->param('xstart')) {

# The 'xstart' parameter must be digits.
		
		$q_xstart = $query->param('xstart');
		$q_xstart =~ s/[^0-9\.]//g;
	} else {
		$q_xstart = 0;
	}
	
	if($query->param('xend')) {

# The 'xend' parameter must be digits.

		$q_xend = $query->param('xend');
		$q_xend =~ s/[^0-9\.]//g;
	} else {
		$q_xend = 0;
	}

	if($query->param('yscale')) {

# The 'yscale' parameter must be either 'autoscaled' or 'set'.
# Default to 'autoscaled'.

		if($query->param('yscale') eq 'set') {
			$q_yscale = 'set';
		} else {
			$q_yscale = 'autoscaled';
		}
	} else {
		$q_yscale = 'autoscaled';
	}
	
	if($query->param('ystart')) {

# The 'ystart' parameter must be digits.

		$q_ystart = $query->param('ystart');
		$q_ystart =~ s/[^0-9\.]//g;
	} else {
		$q_ystart = 0;
	}

	if($query->param('yend')) {

# The 'yend' parameter must be digits.

		$q_yend = $query->param('yend');
		$q_yend =~ s/[^0-9\.]//g;
	} else {
		$q_yend = 0;
	}
	
	if($query->param('type')) {

# The 'type' parameter must be either 'image' or 'spectrum'.
# Default to 'image'.

		if($query->param('type') eq 'spectrum') {
			$q_type = 'spectrum';
		} else {
			$q_type = 'image';
		}
	} else {
		$q_type = 'image';
	}
	
	if($query->param('autocut')) {

# The 'autocut' parameter must be digits.
# Default to '100'.

		$q_autocut = $query->param('autocut');
		$q_autocut =~ s/[^0-9\.]//g;
	} else {
		$q_autocut = 100;
	}
	
	if($query->param('xcrop')) {

# The 'xcrop' parameter must be either 'full' or 'crop'.
# Default to 'full'.

		if($query->param('xcrop') eq 'crop') {
			$q_xcrop = 'crop';
		} else {
			$q_xcrop = 'full';
		}
	} else {
		$q_xcrop = 'full';
	}
	
	if($query->param('xcropstart')) {

# The 'xcropstart' parameter must be digits.
# Default to '0'.

		$q_xcropstart = $query->param('xcropstart');
		$q_xcropstart =~ s/[^0-9\.]//g;
	} else {
		$q_xcropstart = 0;
	}
	
	if($query->param('xcropend')) {

# The 'xcropend' parameter must be digits.
# Default to '0'.

		$q_xcropend = $query->param('xcropend');
		$q_xcropend =~ s/[^0-9\.]//g;
	} else {
		$q_xcropend = 0;
	}
	
	if($query->param('xcrop')) {

# The 'ycrop' parameter must be either 'full' or 'crop'.
# Default to 'full'.

		if($query->param('ycrop') eq 'crop') {
			$q_ycrop = 'crop';
		} else {
			$q_ycrop = 'full';
		}
	} else {
		$q_ycrop = 'full';
	}
	
	if($query->param('ycropstart')) {

# The 'ycropstart' parameter must be digits.
# Default to '0'.

		$q_ycropstart = $query->param('ycropstart');
		$q_ycropstart =~ s/[^0-9\.]//g;
	} else {
		$q_ycropstart = 0;
	}
	
	if($query->param('ycropend')) {
		
# The 'ycropend' parameter must be digits.
# Default to '0'.

		$q_ycropend = $query->param('ycropend');
		$q_ycropend =~ s/[^0-9\.]//g;
	} else {
		$q_ycropend = 0;
	}
	
	if($query->param('lut')) {

# The 'lut' parameter must be one of the standard lookup tables.
# Default is 'standard'.
		
		# first, strip out anything that's not a letter or a number
		
		my $t_lut = $query->param('lut');
		$t_lut =~ s/[^a-zA-Z0-9]//g;
		
		# this parameter needs to match exactly one of the strings listed in @ctabs
		
		my $match = 0;
		
		foreach my $t_ctab (@ctabs) {
			if($t_lut eq $t_ctab) {
				$q_lut = $t_ctab;
				$match = 1;
			}
		}
		if ($match == 0) {
			$q_lut = 'heat';
		}
	} else {
		$q_lut = 'heat';
	}
	
	if($query->param('size')) {

# The 'size' parameter must be [128 | 640 | 960 | 1280]
# Default is '640'.

		my $t_size = $query->param('size');
		$t_size =~ s/[^0-9]//;
		$ENV{'PGPLOT_GIF_WIDTH'} = $t_size;
		$ENV{'PGPLOT_GIF_HEIGHT'} = $t_size * 3 / 4;
	} else {
		$ENV{'PGPLOT_GIF_WIDTH'} = 640;
		$ENV{'PGPLOT_GIF_HEIGHT'} = 480;
	}

# Print out the page

	print_JAC_header();
	
	foreach my $instrument (@instruments) {
		print_summary($instrument, $ut, $projectid, $password);
	}
	
	print "<hr>List all reduced group observations for ";
	my @string;
	foreach my $instrument (@instruments) {
		push @string, (sprintf "<a href=\"?all=yes&instrument=%s\">%s</a>", $instrument, $instrument);
	}
	print join ", ", @string;
	print " for $ut.<br>\n";
	print "<hr>\n";
	
	print $query->startform(undef,"worf.pl");
	
	if ( $q_view eq 'yes' ) {
		display_observation($q_file, $q_cut, $q_rstart, $q_rend, $q_xscale, $q_xstart, $q_xend,
												$q_yscale, $q_ystart, $q_yend, $q_instrument, $q_type, $q_obstype,
												$q_autocut, $q_xcrop, $q_xcropstart, $q_xcropend, $q_ycrop, $q_ycropstart,
												$q_ycropend, $q_lut, $q_instrument);
	}
	
	print $query->endform;
	
	if ($q_all eq 'yes' ) {
		print_observations ($q_instrument, $ut, $projectid);
	}
	
	print_JAC_footer();

} # end sub worf_output

# Define subroutines

sub print_JAC_header {
  print <<END;
Welcome to WORF. <a href="/JACpublic/UKIRT/software/worf/help.html">Need help?</a><br>
<hr>
END
};

sub print_JAC_footer {
  print <<END;
  <p>
  <hr>
  <address>Last Modification Author: bradc<br>Brad Cavanagh (<a href="mailto:b.cavanagh\@jach.hawaii.edu">b.cavanagh\@jach.hawaii.edu</a>)</address>
</html>
END
};

sub print_summary {

# This subroutine gives the UT date, latest raw file, and latest reduced group file for
# the given instrument.
#
# IN: $instrument: instrument name
#     $ut: UT date in YYYYMMDD format
#     $projectid: OMP project id
#     $password: OMP password
#
# OUT: none

	my @groupfiles;
	my @groupfilessuffix = ();
	my @projectgroupfiles = ();
	my @projectrawfiles = ();
	my @group;
	my @raw;
	my @foo;
	my @bar;
	my @baz;
	my $latestgroup;
	my $latestraw;

# Grab the list of all the files in the directory, except for
# dot files (you know, those silly files that begin with dots?).

	my ($instrument, $ut, $projectid, $password) = @_;
	my $directory = get_reduced_directory($instrument, $ut);
	opendir(FILES, $directory);
	my @files = grep(!/^\./, readdir(FILES)); # skip dot files
	closedir(FILES);

# Okay, now we have a list of all of the files in the directory. Let's
# trim out everything that isn't an NDF

	@files = grep(/sdf$/, @files);

# Alrighty. Reduced group files are (I'm assuming) ones that begin
# with a 'g' and have two letters followed by the UT date. Let's
# grab all of them.

	@groupfiles = grep(/^g[a-zA-Z]/, @files);

# We're only concerned with files that have suffixes that are listed
# in @groupsuffix{$instrument}. If that array is empty, don't trim
# the file list.

	if(scalar(@{$groupsuffix{$instrument}}) != 0) {
		foreach my $elm1 (@groupfiles) {
			foreach my $elm2 (@{$groupsuffix{$instrument}}) {
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
		if(file_matches_project($directory . "/" . $file, $projectid, $instrument)) {
			push @projectgroupfiles, $file;
		}
	}

# Now sort them according to the observation number
	my $i;
	my @foo;
	for($i = 0; $i <= $#projectgroupfiles; $i++) {
		$projectgroupfiles[$i] =~ /\d{8}_(\d+)_/ && ($foo[$i] = $1);
	}

	@group = sort {$a <=> $b} @foo;

# And, the latest reduced group file is...

	@baz = grep(/\d{8}_$group[$#group]_/, @projectgroupfiles);
	$latestgroup = $baz[0];

# Now let's do basically the same for the raw data files.

  $directory = get_raw_directory($instrument, $ut);

	opendir(FILES, $directory);
	my @files = grep(!/^\./, readdir(FILES));
	closedir(FILES);

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
		if(file_matches_project($directory . "/" . $tfile, $projectid, $instrument)) {
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
			print "$latestraw (<a href=\"?view=yes&file=$latestraw&instrument=$instrument&obstype=raw\">view</a>)";
		} else {
			print "&nbsp;";
		}
		print "</td><td>";
		if ($latestgroup) {
			print "$latestgroup (<a href=\"?view=yes&file=$latestgroup&instrument=$instrument&obstype=reduced\">view</a>)";
		} else {
			print "&nbsp;";
		}
		print "</td></tr>\n";
		print "</table>\n";
	}
}

sub display_observation {

# This subroutine displays a given observation.
#
# IN: $file: filename of observation to be displayed
#     $cut: whether the cut is horizontal or vertical (spectrum)
#     $rstart: starting row for cut (spectrum)
#     $rend: ending row for cut (spectrum)
#     $xscale: whether the x-dimension is autoscaled or set (spectrum)
#     $xstart: starting position for x-dimension (spectrum)
#     $xend: ending position for x-dimension (spectrum)
#     $yscale: whether the y-dimension is autoscaled or set (spectrum)
#     $ystart: starting position for y-dimension (spectrum)
#     $yend: ending position for y-dimension (spectrum)
#     $instrument: name of instrument
#     $type: type of display (image or spectrum)
#     $obstype: type of observaton (raw or reduced)
#     $autocut: scale data by cutting percentages (image)
#     $xcrop: whether the x-dimension is cropped or set (full or crop) (image)
#     $xcropstart: starting position for x-dimension (image)
#     $xcropend: ending position for x-dimension (image)
#     $ycrop: whether the y-dimension is cropped or set (full or crop) (image)
#     $ycropstart: starting position for y-dimension (image)
#     $ycropend: ending position for y-dimension (image)
#     $lut: look up table for colour tables (image)
#     $instrument: name of instrument
#
# OUT:
# none

	my($file, $cut, $rstart, $rend, $xscale, $xstart, $xend, $yscale, $ystart, $yend, $instrument, $type, $obstype, $autocut, $xcrop, $xcropstart, $xcropend, $ycrop, $ycropstart, $ycropend, $lut, $instrument) = @_;

	print_display_properties();	

	print "<br>\n";

	print $query->hidden(-name=>'file', -default=>[$file]);
	print $query->hidden(-name=>'view', -default=>['yes']);
	print $query->hidden(-name=>'instrument', -default=>[$instrument]);
	print $query->hidden(-name=>'obstype', -default=>[$obstype]);

	print $query->submit('modify');
	print $query->defaults('defaults');

	print "<hr>Worf says:<br><ul>\n";

	print "<img src=\"worf_graphic.pl?file=$file&cut=$cut&rstart=$rstart&rend=$rend&xscale=$xscale&xstart=$xstart&xend=$xend&yscale=$yscale&ystart=$ystart&yend=$yend&instrument=$instrument&type=$type&obstype=$obstype&autocut=$autocut&xcrop=$xcrop&xcropstart=$xcropstart&xcropend=$xcropend&ycrop=$ycrop&ycropstart=$ycropstart&ycropend=$ycropend&lut=$lut\" width=\"$ENV{'PGPLOT_GIF_WIDTH'}\" height=\"$ENV{'PGPLOT_GIF_HEIGHT'}\">\n";

}

sub print_display_properties {

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

}

sub print_observations {

# This subroutine prints out observations for whichever instrument is
# given in the argument.
#
# IN:
# $instrument - the instrument for which the observations will be printed
# $ut - the UT date on which the observations were taken
# $project - OMP project
#
# OUT:
# none

  my ($instrument, $ut, $project) = @_;
	my @files;
  my %data;
	my ($objname, $utstart, $exptime, $filter, $grating, $wavelength, $airmass, $RA, $dec, $fileproject, $msbid);
	my $currentproject = "NOPROJECT";
	my $currentmsbid = "";
	my $first = 1;
	my $reduceddir = get_reduced_directory( $instrument, $ut );
  if( -d $reduceddir ) {
		opendir(FILES, $reduceddir);
		@files = grep(!/^\./, readdir(FILES));
		closedir(FILES);
		@files = grep(/sdf$/, @files);
		@files = sort @files;
		print "<hr>\n";
		print "<strong>Reduced group observations for $instrument on $ut</strong><br>\n";
		foreach my $file (@files) {
			if($file =~ /^([a-zA-Z]{2})($ut)_(\d+)(_?)(\w*)\.(\w+)/) {
				my ($prefix, $null, $obsnum, $null, $suffix, $extension) = ($1, $2, $3, $4, $5, $6);

# Find out if the suffix is in @groupsuffix{$instrument}, if that array
# is not empty.

				my $match = 0;
				if(scalar(@{$groupsuffix{$instrument}}) != 0) {
					foreach my $elm (@{$groupsuffix{$instrument}}) {
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
					
					$objname = $Frm->hdr($headers{$instrument}{'objname'});
					$utstart = $Frm->hdr($headers{$instrument}{'utstart'});
					$exptime = $Frm->hdr($headers{$instrument}{'exptime'});
					$filter = $Frm->hdr($headers{$instrument}{'filter'});
					$grating = $Frm->hdr($headers{$instrument}{'grating'});
					$wavelength = $Frm->hdr($headers{$instrument}{'wavelength'});
					$airmass = $Frm->hdr($headers{$instrument}{'airmass'});
					$RA = $Frm->hdr($headers{$instrument}{'RA'});
					$dec = $Frm->hdr($headers{$instrument}{'dec'});
					$fileproject = $Frm->hdr($headers{$instrument}{'project'});
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
							print "<strong>Project:</strong> $fileproject <strong>MSBID:</strong> $msbid<br>\n";
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
							print "<strong>Project:</strong> $fileproject <strong>MSBID:</strong> $msbid<br>\n";
							print "<table border=\"1\">\n";
							print "<tr><th>observation number</th><th>object name</th><th>UT start</th><th>exposure time</th><th>filter</th><th>grating</th><th>central wavelength</th><th>airmass</th><th>file suffix</th><th>view data</th><th>download file</th></tr>\n";
							$currentmsbid = $msbid;
						}
						print "<tr><td>$obsnum</td><td>$objname</td><td>$utstart</td><td>$exptime</td><td>$filter</td><td>$grating</td><td>$wavelength</td><td>$airmass</td><td>$suffix</td><td><a href=\"?view=yes&instrument=$instrument&file=$file&obstype=reduced\">view</a></td><td><a href=\"worf_file.pl?instrument=$instrument&file=$file\">download</a></td></tr>\n";
					}
				}
			}
		}
		print "</table>\n";
	} else {
		print "Directory for $instrument on $ut reduced data does not exist.<br>\n";
	}
}

sub get_raw_directory {
# A simplified way to retrieve the raw data directory given an
# instrument and a UT date.

	my $instrument = shift;
	my $ut = shift;

	my %options;
  $options{'ut'} = $ut;
	orac_configure_for_instrument( uc( $instrument ), \%options );

	return $ENV{"ORAC_DATA_IN"};
}

sub get_reduced_directory {
# A simplified way to retrieve the reduced data directory given an
# instrument and a UT date.

	my $instrument = shift;
	my $ut = shift;

	my %options;
	$options{'ut'} = $ut;
	orac_configure_for_instrument( uc( $instrument ), \%options );

	return $ENV{"ORAC_DATA_OUT"};
}

sub pad {
  my ($string, $character, $endlength) = @_;
  my $result = ($character x ($endlength - length($string))) . $string;
}

sub file_matches_project {
	my $file = shift; # note that this needs to be a full filename
	my $projectid = shift;
	my $instrument = shift;

	if( lc($projectid) eq 'staff') { return 1; }

	my $Frm = new ORAC::Frame::NDF($file);
	$Frm->readhdr;

	my $project = $Frm->hdr($headers{$instrument}{'project'});
	return (uc($project) eq uc($projectid));
}
