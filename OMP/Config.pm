package OMP::Config;

=head1 NAME

OMP::Config - parse and supply information from OMP configuration files

=head1 SYNOPSIS

  use OMP::Config;

  OMP::Config->cfgdir( "/jac_sw/omp/cfg");

  $url = OMP::Config->getdata( 'omp' );

  $datadir = OMP::Config->getdata( 'datadir',
				   telescope => 'JCMT',
                                   instrument => 'SCUBA',
				   utdate => 'YYYY-MM-DD');

=head1 DESCRIPTION

This class can read and return the information contained in
OMP format configuration files.

=cut

use 5.006;
use strict;
use warnings;

use OMP::General;
use File::Spec;
use File::Basename;
use Config::IniFiles;
use Data::Dumper;

use vars qw/ $DEBUG /;
$DEBUG = 0;

# just in case we need to know where we are
use FindBin;

# These are the variables that contain the important information
# [class variables] - the actual configuration
my %CONFIG;

# Must do two things on startup
# Note that we use __PACKAGE__ here rather than OMP::Config simply
# because we can! [and it would allow us to use this code somewhere else]

# First determine the domainname and hostname
my %CONST;
__PACKAGE__->_determine_constants;

# Find default config directory
# If none of the directories exist simply defer the read until later
__PACKAGE__->_determine_default_cfgdir();

=head1 METHODS

There are no instance objects created by this class. The config
files are always read whenever the config directory is changed
and at startup.

=head2 Public Methods

=over 4

=item B<cfgdir>

Set (or retrieve) the directory in which the configuration files
reside.

 OMP::Config->cfgdir( $newdir );
 $dir = OMP::Config->cfgdir();

All the config files are read when the directory changes.

=cut

{
  # Keep the real variable private
  my $cfgdir;
  sub cfgdir {
    my $class = shift;
    if (@_) {
      my $dir = shift;
      if (-d $dir) {
	$cfgdir = $dir;
	$class->_read_configs();
      } else {
	throw OMP::Error::FatalError "Specified config directory [$dir] does not exist";
      }
    }
    return $cfgdir;
  }
}

=item B<getData>

Retrieve the data associated with the supplied key.

  $value = OMP::Config->getData( $key );

The key is case-insensitive. Additionally, if you want a telescope,
date or instrument specific result that information must also
be supplied. An exception is thrown if the key does not exist
or the value can not be found given the telescope information (or
lack of it).

  $value = OMP::Config->getData( $key, telescope => 'JCMT' );

The recognised modifiers are:

   telescope  - the telescope name (JCMT, UKIRT etc)
   utdate     - YYYY-MM-DD string or Time::Piece object
   instrument - instrument name

=cut

sub getData {
  my $class = shift;
  my $key = shift;
  my %args = @_;

  # Make sure we have read some files (ie specified a cfgdir)
  if (!exists $CONFIG{omp}) {
    my $cfgdir = $class->cfgdir;
    $cfgdir = (defined $cfgdir ? $cfgdir : "<undefined>");
    throw OMP::Error::FatalError("We have not read any config files yet. Please set cfgdir [currently = '$cfgdir']");
  }

  # Need to find the relevant config table. Only choices are "omp"
  # and a valid a telescope
  my $table = "omp";

  # Do we have a telescope?
  if (exists $args{telescope}) {
    # and is it valid
    my $tel = lc($args{telescope});
    if (exists $CONFIG{$tel}) {
      $table = $tel;
    } else {
      throw OMP::Error::FatalError("Telescope [$tel] is not recognized by the OMP config system");
    }
  }

  # Does the key exist in that table [note that the telescopes are
  # clones of the omp base table so we do not need to look in both
  # once read]
  my $value;
  if (exists $CONFIG{$table}{$key}) {
    # success
    $value = $CONFIG{$table}{$key};
  } else {
    throw OMP::Error::FatalError("Key [$key] could not be found in OMP config system");
  }

  # Now need to either replace the placeholders or convert to array
  return $class->_format_output( $value, %args );

}

=back

=head2 Internal Methods

=over 4

=item B<_read_configs>

Read all the configuration files in the config directory and store
the results.

=cut

sub _read_configs {
  my $class = shift;

  # First step is to read all the .cfg files from the config directory
  my $dir = $class->cfgdir;
  print "Config Dir is $dir\n" if $DEBUG;

  opendir my $dh, $dir
    or throw OMP::Error::FatalError("Error reading config directory [$dir]: $!");

  # files must end in .cfg
  # and we must prefix the actual directory name
  my @files = map {File::Spec->catfile($dir,$_) } grep /\.cfg$/, readdir $dh;

  warn "No config files read from directory $dir!"
    unless scalar(@files);

  closedir $dh
    or throw OMP::Error::FatalError("Error closing cfg directory handle: $!");

  # Need to read all the INI files, copy the information and deal
  # with host and domain lookups
  print Dumper(\@files) if $DEBUG;

  # Read each of the files and store the results
  my %read = map { $class->_read_cfg_file($_) } @files;

  # Do we have a 'omp' entry? Is this fatal?
  $read{omp} = {} unless exists $read{omp};

  use Data::Dumper;
  print Dumper(\%read);

  # Now need to merge information with the omp defaults
  # and the telescope values so that we do not have to
  # look in two places for each lookup
  $CONFIG{omp} = $read{omp};
  delete $read{omp};

  for my $cfg (keys %read) {
    my %copy = (%{$CONFIG{omp}}, %{$read{$cfg}});
    $CONFIG{$cfg} = \%copy;
  }

  # done
  return;
}

=item B<_read_cfg_file>

Read the specified file, choose which bits of the file we need to
use and return a label and the contents.

  ($label, $hashref) = OMP::Config->_read_cfg_file( $file );

=cut

sub _read_cfg_file {
  my $class = shift;
  my $file = shift;

  # Determine the "label"
  my $label = basename($file,'.cfg');

  # Read the file
  my %data;
  tie %data, 'Config::IniFiles', (-file => $file);
  print "File $file: ".Dumper \%data
    if $DEBUG;

  # determine the key order. host overrides, domain overrides
  # default
  my @keys = ('default',map { $_.":".$CONST{$_} } qw/ domain host /);

  # loop through the keys
  # It would be easy if we only looked for set keys
  #   default, host: and domain:
  my %cfg;
  for my $key ( @keys ) {
    print "Trying key $key\n" if $DEBUG;
    if (exists $data{$key} && defined $data{$key}) {
      # this involves increasing overhead as more keys are added
      %cfg = (%cfg, %{ $data{$key} });
    }
  }

  # return the answer
  return ($label, \%cfg);
}

=item B<_determine_constants>

Determine the values of the constants that are used to decide
on which values to read from a file.

  OMP::Config->_determine_constants;

Currently determines the domainname and the hostname.

Respects the OMP_NOGETHOST environment variable.  (useful if you are
not on a network) See OMP::General for more information on this
variable.

=cut

sub _determine_constants {
  my $class = shift;

  my ($host, $domain);
  if (exists $ENV{OMP_NOGETHOST}) {
    # we are not even going to look
    $host = 'localhost';
    $domain = 'localdomain';
  } else {
    # Get the fully qualified domain name
    # being careful to disable checks for REMOTE_HOST
    (my $user, $host, my $email) = OMP::General->determine_host( 1 );

    # split the host name on dots
    ($host, $domain) = split(/\./,$host,2);
  }

  # Store them
  print "Host: $host  Domain: $domain\n" if $DEBUG;
  $CONST{host} = $host;
  $CONST{domain} = $domain;
}

=item B<_determine_default_cfgdir>

Make an initial guess at the location of the config files.
If no directory can be found simply does nothing and awaits
an explicit setting of the directory. This method is only
run once at startup.

Three methods are used to guess:

 - The OMP_CFG_DIR environment variable

 - The OMP_DIR environment variable (OMP_DIR/cfg)

 - A path relative to the binary location (bin/../cfg)

=cut

sub _determine_default_cfgdir {
  my $class = shift;

  my $cfgdir;
  if (exists $ENV{OMP_CFG_DIR}) {
    $cfgdir = $ENV{OMP_CFG_DIR};
  } elsif (exists $ENV{OMP_DIR}) {
    $cfgdir = File::Spec->catdir($ENV{OMP_DIR},
				 "cfg");
  } else {
    $cfgdir = File::Spec->catdir( $FindBin::RealBin,
				  File::Spec->updir,
				  "cfg");
  }

  # set it if it is accessible
  $class->cfgdir($cfgdir)
    if -d $cfgdir;

  return;
}

=item B<_format_output>

Converts a string read from a config file into something suitable
for use in a program. This involves replacing placeholder strings
and converting comma-separated lists into arrays.

  $formatted = OMP::Config->_format_output($value, %extra );

The hash contains information used to replace placeholders.
Recognized entries are:

  instrument   - instrument name
  utdate       - YYYY-MM-DD or Time::Piece object
  telescope    - telescope name

Additionally the utdate is used to generate a semester. An exception
is raised if some of the placeholders can not be replaced.

=cut

sub _format_output {
  my $class = shift;
  my $input = shift;
  my %args = @_;

  # Currently we recognize the following placeholders
  # [a placeholder is a string with format _+STRING+_]
  # INSTRUMENT - upper-cased instrument name
  # instrument - lower-cased instrument name
  # UTDATE     - ut date, in YYYYMMDD format
  # SEMESTER   - semester name [upper case]
  # semester   - semester name [lower case]
  # TELESCOPE  - telescope name [upper case]
  # telescope  - telescope name [lower case]

  # If formatting of UTDATE becomes an issue we will need to
  # provide a config entry suitable for strftime. That will
  # only work if the format is fixed for a telescope. If we need
  # different formats we might need to change placeholders to
  #  _+UTDATE:%Y%m%d+_

  # Get the replacement strings
  my %places;

  for my $key (qw/ instrument telescope /) {
    if (exists $args{$key}) {
      my $up = uc($key);
      my $down = lc($key);
      $places{$up} = uc($args{$key});
      $places{$down} = lc($args{$key});
    }
  }
  if (exists $args{utdate}) {
    my $ut = OMP::General->parse_date( $args{utdate} );
    if ($ut) {
      $places{UTDATE} = $ut->strftime("%Y%m%d");
      $places{SEMESTER} = uc(OMP::General->determine_semester($ut));
      $places{semester} = lc($places{SEMESTER});
    }
  }

  # Now go through each placeholder (assuming we have any)
  for my $p (keys %places) {
    # do not do it in one big replace becuase we want to
    # trap placeholders that we can not fix rather than inserting undef
    $input =~ s/(_\+$p\+_)/$places{$p}/g;
  }

  # did we get them all?
  if ($input =~ /_\+(\w+)\+_/) {
    throw OMP::Error::FatalError("Failed to replace all placeholders in output string: Missing $1");
  }


  # Now convert to array if we have commas
  if ($input =~ /,/) {
    my @split = split(/,/,$input);
    $input = \@split;
  }

  # And return the munged variable
  return $input;
}

=back

=head1 FORMAT

The files follow the standard INI format and are read by the
C<Config::IniFiles> class. XML is not used since we want to keep the
files very simple, easy to read and easy to edit.

Each telescope has its own file in the config directory (in the OMP
tree in C<omp/msbserver/cfg>), the location of which can be modified,
for telescope specific information. There is also an "omp.cfg" file
for general configuration options that are not telescope specific.

All config files are read on startup or when the config directory is
changed (since a telescope can be changed during the execution of a
program) and if a telescope is specified information in the telescope
specific files overrides that found in the basic defaults.

If we really wanted we could put telescope specific stuff and general
stuff into a single file. For now, they are separate.

In some cases we want the information to change depending on the domain
name or even the hostname of the computer running the program. Rather
than having to remember to change config files to suit the current
computer [which plays havoc with CVS] or having an additional level
of directory abstraction the files can include special key prefixes
which are used to indicate something should switch on host or domain.

  [domain:JCMT]
  datadir=/jcmtdata

  [domain:JAC]
  datadir=/scuba

  [host:lapaki]
  datadir=/export/data/

When this file is read a key of "datadir" will only be set if the
domainname matches. Host specific matches override, domain-specific
matches which override default settings.  This only works for
information that will not vary during the execution of the
program. The list of allowed keys is restricted to "default" for
generic information, "host:..." for host based switching and
"domain:..." for doman-based switching:

  [default]
  omp-url=http://omp.jach.hawaii.edu
  omp-private=http://omp-private.jach.hawaii.edu

  [host:hihi]
  ftpdir=/export/ftp/pub/jcmt/

  [domain:JAC]
  ftpdir=/local/jcmt/ftp/

Some config entries include placeholders which should be replaced
with actual information such as instrument and UT date. If the
C<getData> method is supplied with instrument and UT information
these placeholders will be replaced automatically. An error
is raised if a placeholder can not be replaced (possibly including
the additional required information). A placeholder is indicated
by "_+STRING+_",

  [domain:JCMT]
  datadir=/jcmtdata/raw/_+instrument+_/_+UTDATE+_/dem

  [domain:JAC]
  datadir=/scuba/m_+semester+_/_+UTDATE+_

Array information is represented by comma separated lists. The getData
method will return an array reference in that case.

  [default]
  qcolumns=msbid,checksum

An exception is raised if the required information is not present in
the files.

The format of this file could change at any time. The interface
is set.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

# First determine the domainname and hostname
#__PACKAGE__->_determine_constants;

# secondly set the default config directory (forcing read of config files)
#__PACKAGE__->cfgdir( File::Spec->catdir($FindBin::RealBin,
#					File::Spec->updir,
#					"cfg"));


1;
