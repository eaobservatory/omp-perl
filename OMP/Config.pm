package OMP::Config;

=head1 NAME

OMP::Config - parse and supply information from OMP configuration files

=head1 SYNOPSIS

  use OMP::Config;

  OMP::Config->cfgdir( "/jac_sw/omp/cfg");

  $url = OMP::Config->getData( 'omp' );
  $dbserver = OMP::Config->getData( 'database.server' );

  $datadir = OMP::Config->getdata( 'datadir',
				   telescope => 'JCMT',
                                   instrument => 'SCUBA',
				   utdate => 'YYYY-MM-DD');

  $tel = OMP::Config->inferTelescope('instruments', 'SCUBA');

  @telescopes = OMP::Config->telescopes;

=head1 DESCRIPTION

This class can read and return the information contained in
OMP format configuration files.

=cut

use 5.006;
use strict;
use warnings;
use warnings::register;

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

The config files are read on demand. If the config directory
is changed, old configs are cleared.

=cut

{
  # Keep the real variable private
  my $cfgdir;
  sub cfgdir {
    my $class = shift;
    print "In cfgdir method\n" if $DEBUG;
    if (@_) {
      my $dir = shift;
      print "dir: $dir\n" if $DEBUG;
      if (-d $dir) {
        $cfgdir = $dir;
        print "cfgdir: $cfgdir\n" if $DEBUG;
        %CONFIG = (); # reset configs
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

In scalar context, this method can return a single value
or a reference to an array (depending on the entry), when
called in list context will always return a list (the
array reference is expanded to a list). This simplifies the
case where a single config entry is a single value in one
file and multiple values in another.

A hierarchical key is supported using a "." separator.

 $value = OMP::Config->getData( "database.server" );

In all other respects the hierarchical form of the command
is identical to the non-hierarchical form.

=cut

sub getData {
  my $class = shift;
  my $key = lc(shift);
  my %args = @_;

  # Make sure we have read some files (ie specified a cfgdir)
  $class->_checkConfig;

  # Need to find the relevant config table. Only choices are "omp"
  # and a valid telescope
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

  # Split hierarchical keys
  my @keys = split(/\./, $key);

  # Now traverse the hash looking for the supplied key
  my $value = _traverse_cfg( [$key, $table], $CONFIG{$table}, @keys);

  # Now need to either replace the placeholders or convert to array
  my $retval = $class->_format_output( $value, %args );
  if (wantarray) {
    my $ref = ref($retval);
    if (not $ref) {
      return $retval;
    } elsif ($ref eq 'ARRAY') {
      return @$retval;
    } elsif ($ref eq 'HASH') {
      return %$retval;
    } else {
      throw OMP::Error::FatalError("getData called in list context but unable to determine the type of data that we are dealing with!");
    }

  } else {
    return $retval;
  }
}

=item B<getTelescopes>

Return a list of telescopes for which a config file exists.

  @telescopes = OMP::Config->getTelescopes();

=cut

sub telescopes {
  my $class = shift;
  $class->_checkConfig;
  return grep { $_ ne 'omp' }  keys %CONFIG;
}

=item B<inferTelescope>

Try to infer the relevant telescope by looking for a key in the
config system that has a specific value. This can be used, for example,
to determine the telescope associated with a specific instrument:

  $tel = OMP::Config->inferTelescope('instruments', 'SCUBA');

The test is case-insensitive. There is no check for placeholders.  If
the key refers to an array a match occurs if an element in that array
matches. If more than one telescope matches or no telescope matches
then an exception is thrown. Returns the empty string if the only
match is the default OMP configuration.

Always does a string comparison.

=cut

sub inferTelescope {
  my $class = shift;
  my $refkey = lc(shift);
  my $refval = lc(shift);

  # Make sure we have read some files (ie specified a cfgdir)
  $class->_checkConfig;

  my @matches;
  for my $tel (keys %CONFIG) {
    if (exists $CONFIG{$tel}->{$refkey}) {
      my $val = $CONFIG{$tel}->{$refkey};
      if (not ref $val) {
	# compare directly
	$val = lc($val);
	if ($val eq $refval) {
	  push(@matches, $tel);
	}
      } elsif (ref($val) eq 'ARRAY') {
	my @vals = map { lc($_); } @$val;
	my @mm = grep { $_ eq $refval } @vals;
	if (scalar(@mm) > 0) {
	  push(@matches, $tel);
	}

      } else {
	throw OMP::Error::FatalError("Key value is unexpected reference type!");
      }
    }
  }

  if (scalar(@matches) == 0) {
    throw OMP::Error::BadCfgKey("No matches in config system for value $refval using key $refkey");
  } elsif (scalar(@matches) > 1) {
    throw OMP::Error::FatalError("Multiple matches in config system for value $refval using key $refkey. Telescopes: " . join(",",@matches));
  }

  # correct for 'omp' telescope
  my $tel = $matches[0];
  $tel = '' if $tel eq 'omp';

  return $tel;
}

=back

=head2 Internal Methods

=over 4

=item B<_checkConfig>

Check to see if we have read a config yet. If we have no keys,
attempt to read a config. If still no keys throw an exception.

  $hashref = $pkg->_checkConfig;

=cut

sub _checkConfig {
  my $class = shift;

  # check for the OMP key
  if (!exists $CONFIG{omp}) {
    # Try to read the configs on demand
    $class->_read_configs();

    # if still no luck complain about it
    if (!exists $CONFIG{omp}) {
      my $cfgdir = $class->cfgdir;
      $cfgdir = (defined $cfgdir ? $cfgdir : "<undefined>");
      throw OMP::Error::FatalError("We have not read any config files yet. Please set cfgdir [currently = '$cfgdir']");
    }
  }
}

=item B<_read_configs>

Read all the configuration files in the config directory and store
the results.

If the $OMP_SITE_CONFIG environment variable is set this overrides 
all the non-telescope settings.

=cut

sub _read_configs {
  my $class = shift;

  # First step is to read all the .cfg files from the config directory
  my $dir = $class->cfgdir;

  if ($DEBUG) {
    my $text = (defined $dir ? $dir : "<undef>");
    print "Config Dir is $text\n";
  }

  throw OMP::Error::FatalError("Config dir has not been defined - Aborting")
      unless defined $dir;

  opendir my $dh, $dir
    or throw OMP::Error::FatalError("Error reading config directory [$dir]: $!");

  # files must end in .cfg and not be hidden
  # and we must prefix the actual directory name
  my @files = map {File::Spec->catfile($dir,$_) } 
         grep { $_ !~ /^\./ }
            grep /\.cfg$/, readdir $dh;

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

  print Dumper(\%read) if $DEBUG;

  # if we have a siteconfig override environment variable, read that
  my %envsite;
  if (exists $ENV{OMP_SITE_CONFIG}) {
    if (-e $ENV{OMP_SITE_CONFIG}) {
      my ($slab, $site) = $class->_read_cfg_file( $ENV{OMP_SITE_CONFIG} );
      %envsite = %$site;
    } else {
      warnings::warnif("Site config specified as '$ENV{OMP_SITE_CONFIG}' in \$OMP_SITE_CONFIG but could not be found");
    }
  }

  # Now need to merge information with the omp defaults
  # and the telescope values so that we do not have to
  # look in two places for each lookup.
  # We also override the contents from the environment variable site config
  # which overrides everything
  $CONFIG{omp} = { %{$read{omp}}, %envsite };
  delete $read{omp};

  for my $cfg (keys %read) {
    $CONFIG{$cfg} = { %{$CONFIG{omp}}, %{$read{$cfg}} };
  }

  # done
  return;
}

=item B<_read_cfg_file>

Read the specified file, choose which bits of the file we need to
use and return a label and the contents.

  ($label, $hashref) = OMP::Config->_read_cfg_file( $file );

Comma-separated values are converted to arrays.

Primary fields are "default" for scalar entries, and associated domain/host
aliases.

Any remainining non-host/non-domain entries will be read in as hash references
with a key corresponding to the name of the block.

If a scalar "siteconfig" entry if present, the site configuration will be read
and combined with the configuration file content. Note that site configuration
override all others.

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

  # determine the key order. host overrides, domain overrides. default

  # The first thing to do is to look for host and domain aliases
  # since we allow config files to contain aliases and internal
  # overrides we deal with this by fiddling with the order of keys
  # to be searched
  #
  #  [host:xxx]
  #  hostalias=yyy
  #  blah=2
  #  blurgh=3
  #
  #  [host:yyy]
  #  blah=5
  #  arg=22
  #
  # would result in blah=2 blurgh=3 arg=22 on host xxx
  # Note also that yyy could be an alias for another host

  # We have to fill @keys starting with the most general and becoming
  # more specific. host trumps domain
  my @keys = ( 'default' );

  # Look for domain and host aliases
  foreach my $type (qw/ domain host /) {
    # This is the start key
    my $key = $type . ":" . $CONST{$type};

    # do nothing if the start key is not present
    if (exists $data{$key}) {
      # Now look in that key for an alias. Use recursion
      # pass the current key into this
      my @nkeys =  _locate_aliases( $key, $type, \%data, $key);

      # The keys from _locate_aliases are in the wrong order
      # so reverse them before pushing onto the stack
      push(@keys, reverse @nkeys);

    }

  }

  # loop through the keys (including aliases)
  my %cfg;
  for my $key ( @keys ) {
    print "Trying key $key\n" if $DEBUG;
    if (exists $data{$key} && defined $data{$key}) {

      # Want to lower case all the keys and process arrays
      # We also want to filter out domainalias and hostalias keys
      my %new;
      for my $oldkey (keys %{$data{$key}}) {
	next if ($oldkey eq 'domainalias' || $oldkey eq 'hostalias');
	my $newkey = lc($oldkey);
	my $newval = $data{$key}->{$oldkey};
	if ($newval =~ /,/) {
	  $newval = [ split(/,/,$newval)];
	}
	$new{$newkey} = $newval;
      }

      # this involves increasing overhead as more keys are added
      %cfg = (%cfg, %new);
    }
  }

  # Now store any other keys so long as they are neither domain nor host
  # entries. These are assumed to be entries that do not have any domain
  # or host specific content and should be stored as hashes
  for my $key (keys %data) {
    next if $key =~ /^(domain|host):/;
    next if $key eq 'default';

    # Copy the hash
    my %temp = %{ $data{$key} };
    $cfg{lc($key)} = \%temp;
  }

  # if we have a siteconfig, read that
  if (exists $cfg{siteconfig}) {
    if (-e $cfg{siteconfig}) {
      my ($slab, $site) = $class->_read_cfg_file( $cfg{siteconfig} );

      # Site overrides local
      %cfg = ( %cfg, %$site );
    } else {
      warnings::warnif("Site config specified in '$file' as '$cfg{siteconfig}' but could not be found");
    }
  }

  # return the answer
  return ($label, \%cfg);
}

# Recursion helper routine for config reader

sub _locate_aliases {
  my ($key, $type, $dataref, @keys ) = @_;

  my $alias = $type . "alias";

  if (exists $dataref->{$key}->{$alias}) {

    # we have an alias so expand it
    my $nkey = $type . ":" . $dataref->{$key}->{$alias};

    # and store all the keys returned from lower levels
    if (exists $dataref->{$nkey}) {
      push( @keys, _locate_aliases($nkey, $type, $dataref, $nkey ) );
    } else {
      throw OMP::Error::FatalError("$type alias of '$nkey' defined in entry '$key' " .
				   "but that $type is not specified in config file");

    }
  }
  return @keys,
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

  print "Guessing CFGDIR as $cfgdir\n" if $DEBUG;

  # set it if it is accessible
  $class->cfgdir($cfgdir)
    if -d $cfgdir;

  return;
}

=item B<_format_output>

Converts a string read from a config file into something suitable for
use in a program. This generally involves replacing placeholder
strings.

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
    my %tel;
    $tel{tel} = $args{telescope} if (exists $args{telescope} && defined $args{telescope});
    if ($ut) {
      $places{UTDATE} = $ut->strftime("%Y%m%d");
      $places{SEMESTER} = uc(OMP::General->determine_semester(date => $ut, %tel));
      $places{semester} = lc($places{SEMESTER});

      # Warn if the string includes SEMESTER without us being given a telescope
      if (!exists $tel{tel}) {
	my $all = (ref($input) eq 'ARRAY' ? join("",@$input) : $input);
	warnings::warnif("Warning. Telescope not supplied despite request for semester")
	  if $all =~ /_\+semester\+_/i;
      }
    }
  }

  # For now it is easiest to convert arrays back to strings
  # and then back to arrays. Sorry.
  if (ref($input) eq 'ARRAY') {
    $input = join(",",@$input);
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

=item B<_read_key>

Internal routine to parse the supplied key and return the corresponding
data value from the internal hash.

  $value = _traverse_cfg( [$key,$table], $CONFIG{$table}, @keys );

The first argument is a reference to an array that simply includes the
toplevel description of the query for use in error message creation. The original
key request and table name are required.

The second argument is a reference to the top of the config hash for
that particular table.

The third argument is the array of keys that should be used in the traversal.

=cut

sub _traverse_cfg {
  my $refkey = shift;
  my $curhash = shift;
  my $curkey = shift;   # The current key
  my @keys = @_;        # Remaining keys

  # see if the hash entry exists
  if (exists $curhash->{$curkey}) {
    # if we have run out of keys, return the value
    if (!@keys) {
      return $curhash->{$curkey};
    } else {
      # Need to go down a level *if* we have a hash
      if (ref($curhash->{$curkey}) eq 'HASH' ) {
	return _traverse_cfg( $refkey, $curhash->{$curkey}, @keys);
      } else {
	throw OMP::Error::FatalError("Hierarchical key referenced [".$refkey->[0]. "] ".
				     "but entry '$keys[0]' does not exist in hierarchy ".
				     "[telescope=".$refkey->[1]."]");
      }
    }
  } else {
    my $keyerr;
    if ($refkey->[0] eq $curkey) {
      $keyerr = "'$curkey'";
    } else {
      $keyerr = "'$curkey' (part of ".$refkey->[0].")";
    }
    throw OMP::Error::BadCfgKey("Key $keyerr could not be found in OMP config system [telescope=".$refkey->[1]."]");
  }

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

Site-wide configuration files can be specified by using the "siteconfig"
key. This should contain the name of a file that can contain site configuration
information. It should be in the same format as the normal config file
and is not expected to be in CVS. This can be used to store local encrypted
passwords. Contents from the site file are read in last and override
entries in the original config file.

Finally, if $OMP_SITE_CONFIG environment variable is set this config
file is read last.

Any entries that are neither in "default" or in a domain/host configuration
will be read in hierarchically. They can be accessed using "." separators
to represent hierarchy.

  [database]
  server=SYB_TMP

would be read using

  $server = OMP::Config->getData("database.server");

If we really wanted we could put telescope specific stuff and general
stuff into a single file. For now, they are separate. Keys are
all case-insenstive.

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

  [domain:JAC.hilo]
  datadir=/scuba
  ftpdir=/local/ftp

  [domain:jach.hawaii.edu]
  domainalias=JAC.hilo
  ftpdir=/local/jcmt/ftp

In some cases multiple hosts/domains need to share the same configuration.
In this case domain and host aliases can be configured to refer to
other domain/host entries in the config file. In the above example, if the
domainname is jach.hawaii.edu the configuration will read ftpdir definition
from "domain:jach.hawaii.edu" but datadir will be read from the alias.
Similarly hostalias can be defined for host entries.


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

Copyright (C) 2002-2004 Particle Physics and Astronomy Research Council.
All Rights Reserved.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful,but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 59 Temple
Place,Suite 330, Boston, MA  02111-1307, USA


=cut

# First determine the domainname and hostname
#__PACKAGE__->_determine_constants;

# secondly set the default config directory (forcing read of config files)
#__PACKAGE__->cfgdir( File::Spec->catdir($FindBin::RealBin,
#					File::Spec->updir,
#					"cfg"));


1;
