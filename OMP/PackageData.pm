package OMP::PackageData;

=head1 NAME

OMP::PackageData - Package up data for retrieval by PI

=head1 SYNOPSIS

  use OMP::PackageData;

  my $pkg = new OMP::PackageData( projectid => 'M02BU127',
                                  utdate => '2002-09-15',
				  inccal => 1,
				);

  $pkg->root_tmpdir("/tmp/ompdata");

  $pkg->pkgdata;

  $file = $pkg->tarfile;

=head1 DESCRIPTION

This class packages data for a particular project and UT date
and makes the tar file available for FTP. It can be run dynamically
from a CGI page.

The process running this routine must have permissions to read the data
files.

=cut

use 5.006;
use strict;
use warnings;
use Carp;

use vars qw/ $VERSION $UseArchiveTar /;
$VERSION = '0.01';

# Disable $PATH - we need /usr/local/bin for gzip on Solaris
# when running tar
$ENV{PATH} = "/usr/bin:/bin:/usr/local/bin";

# Do we want to ues the slower Archive::Tar
$UseArchiveTar = 0;

use File::Spec;
use File::Copy;

# Must be using untaint versions of File::Find and File::Path
use File::Find '1.04';
use File::Path '1.05';

use File::Basename;
use Cwd;
use OMP::General;
use OMP::Error;
use OMP::ProjServer;
use OMP::Info::ObsGroup;
use File::Temp qw/ tempdir /;
use OMP::Config;
use Archive::Tar;

# ONE day in seconds. Should probably use Time::Seconds
use constant ONE_DAY => 60 * 60 * 24;

# Age in days of files to be purged
use constant OLD_AGE => 1;

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

Object constructor. Requires a project and a ut date.

  $pkg = new OMP::PackageData( projectid => 'blah',
			       password => $pass,
			       utdate => '2002-09-17');

UT date can either be a Time::Piece object or a string in the
form "YYYY-MM-DD".

=cut

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;

  my $pkg = bless {
		   ProjectID => undef,
		   UTDate => undef,
		   RootTmpDir => OMP::Config->getData('tmpdir'),
		   TmpDir => undef,
		   FtpRootDir => OMP::Config->getData('ftpdir'),
		   Verbose => 1,
		   ObsGroup => undef,
		   TarFile => undef,
		   Password => undef,
		   UTDir => undef,
		   FTPDir => undef,
		   Key => undef,
		   IncCal => 1,
		  };

  if (@_) {
    $pkg->_populate( @_ );
  }

  return $pkg;
}

=back

=head2 Accessor Methods

=over 4

=item B<projectid>

The project ID associated with these data. No attempt is made to
see if this is a valid OMP project.

  $proj = $pkg->projectid();
  $pkg->projectid('BLAH');

=cut

sub projectid {
  my $self = shift;
  if (@_) {
    $self->{ProjectID} = uc(shift);
  }
  return $self->{ProjectID};
}

=item B<password>

The password required to access this project data.

  $pass = $pkg->password();
  $pkg->password('BLAH');

=cut

sub password {
  my $self = shift;
  if (@_) {
    $self->{Password} = shift;
  }
  return $self->{Password};
}

=item B<utdate>

Set or retrieve the UT date for which the data should be packaged.
For setting, can be either a string in format YYYY-MM-DD or a Time::Piece
object. Always retreves a Time::Piece object.

 $ut = $pkg->utdate();
 $pkg->utdate('2002-09-12');

=cut

sub utdate {
  my $self = shift;
  if (@_) {
    my $ut = shift;
    if (defined $ut) {
      if (not ref $ut) {
	# A scalar, try to parse
	my $parsed = OMP::General->parse_date($ut);
	throw OMP::Error::BadArgs("Unable to parse string '$ut' as a date. Must be YYYY-MM-DD") unless $parsed;
	
	# overwrite $ut
	$ut = $parsed;

      } elsif (!UNIVERSAL::isa($ut, "Time::Piece")) {
	throw OMP::Error::BadArgs("The object supplied to utdate method must be a Time::Piece");
      }
    }
    $self->{UTDate} = $ut;
  }
  return $self->{UTDate};
}

=item B<obsGrp>

Group of observations (an C<OMP::Info::ObsGroup> object) to
be archived and packaged. Created automatically as part of the
object constructor.

=cut

sub obsGrp {
  my $self = shift;
  if (@_) {
    my $grp = shift;
    if (defined $grp) {
      throw OMP::Error::BadArgs("Argument to obsGrp must be an OMP::Info::ObsGroup object")
	unless UNIVERSAL::isa($grp,"OMP::Info::ObsGroup");
    }
    $self->{ObsGroup} = $grp;
  }
  return $self->{ObsGroup};
}

=item B<verbose>

Controls whether messages are sent to standard output during
the packaging of the data. Default is true.

  $pkg->verbose(0);
  $v = $pkg->verbose();

=cut

sub verbose {
  my $self = shift;
  if (@_) {
    $self->{Verbose} = shift;
  }
  return $self->{Verbose};
}

=item B<inccal>

Controls whether calibration observations are included in the packaged data.
Default is to include calibrations.

  $pkg->inccal(0);
  $inc = $pkg->inccal();

=cut

sub inccal {
  my $self = shift;
  if (@_) {
    $self->{IncCal} = shift;
  }
  return $self->{IncCal};
}

=item B<key>

Return the "unique" key associated with this transaction. This
allows multiple FTP transactions to be running at the same time
with out clashing directories.

 $key = $pkg->key;

A key is automatically generated if one does not exist. Use the
C<keygen> method to force a new key to be generated.

=cut

sub key {
  my $self = shift;
  if (@_) {
    $self->{Key} = shift;
  }
  if (!defined $self->{Key}) {
    # Hopefully we will not get into an infinite loop
    $self->keygen;
  }
  return $self->{Key};
}

=item B<tarfile>

Name of the final packaged tar file.

  $file = $pkg->tarfile;

=cut

sub tarfile {
  my $self = shift;
  if (@_) {
    $self->{TarFile} = shift;
  }
  return $self->{TarFile};
}

=item B<root_tmpdir>

Location where any temporary directories and files are to be
written during the archive file creation. This is not necessarily
the same as the FTP directory in which the tar file will
appear (see C<ftp_rootdir>). Defaults to the "tmpdir" setting in
the C<OMP::Config> system.

Temporary files created in here will be removed when the process
completes.

=cut

sub root_tmpdir {
  my $self = shift;
  if (@_) {
    $self->{RootTmpDir} = shift;
  }
  return $self->{RootTmpDir};
}

=item B<ftp_rootdir>

Location where any temporary directories and files are to be written
to on the FTP server. Defaults to OMP::Config entry "ftpdir".

Directories in this directory older than 1 day will be removed
automatically when new directories are created.

=cut

sub ftp_rootdir {
  my $self = shift;
  if (@_) {
    $self->{FtpRootDir} = shift;
  }
  return $self->{FtpRootDir};
}

=item B<tmpdir>

Location in which the data files are to be copied into prior to
creating a tar file. This directory will be cleaned on exit.

  $pkg->tmpdir( $tmpdir );
  $dir = $pkg->tmpdir;

=cut

sub tmpdir {
  my $self = shift;
  if (@_) {
    $self->{TmpDir} = shift;
  }
  return $self->{TmpDir};
}

=item B<ftpdir>

Location in which the ftp tar file will be stored.

  $pkg->ftpdir( $ftpdir );
  $dir = $pkg->ftpdir;

=cut

sub ftpdir {
  my $self = shift;
  if (@_) {
    $self->{FTPDir} = shift;
  }
  return $self->{FTPDir};
}

=item B<utdir>

Name of date-stamped directory in which the temporary files
are placed prior to creating the tar file. This allows the
directory to be untarred with the correct structure.

  $pkg->utdir( $utdir );
  $utdir = $pkg->utdir;

=cut

sub utdir {
  my $self = shift;
  if (@_) {
    $self->{UTDir} = shift;
  }
  return $self->{UTDir};
}


=back

=head2 General Methods

=over 4

=item B<pkgdata>

Create temporary directory, copy data into the directory,
create tar file and place tar file in FTP directory.

  $pkg->pkgdata();

Once packaged, the tar file name can be retrieved using the
tarfile() method.

We could build the tar file in memory but this may take up
too much memory for large transactions (but we would not
need to have a temporary directory)

=cut

sub pkgdata {
  my $self = shift;

  # Verify project password
  OMP::ProjServer->verifyPassword($self->projectid, $self->password)
      or throw OMP::Error::Authentication("Unable to verify project password");

  # Force a new key to make sure we can be called multiple times
  $self->keygen;

  # Create the temp directories
  $self->_mktmpdir;
  $self->_mkutdir;

  # Copy the data into it
  $self->_copy_data();

  # Create directory in FTP server to hold the tar file
  $self->_mkftpdir();

  # Create the tar file from the temp direcotry to
  # the FTP directory
  $self->_mktarfile();

}

=item B<keygen>

Force a new key to be generated. If this is done during data 
packaging there is a very good chance that things will get confused.

  $pkg->keygen;

=cut

sub keygen {
  my $self = shift;
  my $rand = int( rand( 9999999999 ) );
  $self->key( $rand );
}

=item B<ftpurl>

Retrieve the URL required to retrieve the completed tar file.

Returns undef if a tarfile has not been created.

=cut

sub ftpurl {
  my $self = shift;

  my $tarfile = $self->tarfile;
  return undef unless $tarfile;
  $tarfile = basename( $tarfile );

  my $key = $self->key;
  return undef unless defined $key;

  my $baseurl = OMP::Config->getData('ftpurl');
  return $baseurl . "/$key/$tarfile";

}

=back

=head2 Private Methods

=over 4

=item B<_populate>

Populate the observation details from the project ID and
the UT date.

  $pkg->_populate( %hash );

Recognized keys are:

  utdate
  projectid
  password

The corresponding methods are used to initialise the object.
All keys must be present.

This method automatically does the observation file selection.

=cut

sub _populate {
  my $self = shift;
  my %args = @_;

  throw OMP::Error::BadArgs("Must supply both utdate and projectid keys")
    unless exists $args{utdate} && exists $args{projectid}
      && exists $args{password};

  # init the object
  $self->projectid( $args{projectid} );
  $self->utdate( $args{utdate} );
  $self->password( $args{password} );

  # indicate whether we are including calibrations
  $self->inccal( $args{inccal}) if exists $args{inccal};

  # Need to get the telescope associated with this project
  # Should ObsGroup do this???
  my $proj = OMP::ProjServer->projectDetails($self->projectid, $self->password, 'object');

  my $tel = $proj->telescope;

  # Now need to do a query on the archive
  # We do not always need to include the calibrations.
  # It might make sense for ObsGroup to have a calibration switch
  # but for now we vary our query to include the project ID and utdate
  # only if calibrations are not required
  my %query = ( telescope => $tel,
		date => $self->utdate,
	      );

  # Decide whether to optimize for project ID
  $query{projectid} = $self->projectid
    unless $self->inccal;

  # KLUGE for SCUBA. ArchiveDB can not currently query mutltiple JCMT instruments
  $query{instrument} = 'scuba' if $tel =~ /jcmt/i;

  # Since we need the calibrations we do a full ut query and
  # then select the calibrations and project info. This needs
  # to be done in ObsGroup.
  print STDOUT "Querying database for relevant data files..."
    if $self->verbose;

  my $grp = new OMP::Info::ObsGroup( %query );

  # If we asked for everything we now have to go through and select
  # out project observations and the calibrations
  # Now go through and get the bits we need
  # Anything associated with the project or anything from the
  # night that is not a science observation

  # We need to go through each obs returned even if we
  # did a project-centric query. This is because some project
  # observations are actually calibrations


  # Go through looking for project informaton
  # Do this so we can warn if we do not get any data for this night
  my (@proj,@cal);
  for my $obs ($grp->obs) {
    if (uc($obs->projectid) eq $self->projectid && $obs->isScience) {
      print "SCIENCE:     " .$obs->mode ." [".$obs->target ."]\n" 
	if $self->verbose;
      push(@proj, $obs);
    } elsif ( ! $obs->isScience && $self->inccal) {
      print "CALIBRATION: ". $obs->mode . " [".$obs->target."]\n" 
	if $self->verbose;
      push(@cal, $obs);
    }
  }

  # warn if we have cals but no science
  if (scalar(@proj) == 0  && scalar(@cal) > 0) {
    print STDOUT "\nThis request matched calibrations but no science observations\n..."
      if $self->verbose;
  }

  # Store the new observations [calibrations first]
  $grp->obs([@cal,@proj]);

  my @obs = $grp->obs;
  print STDOUT "Done [".scalar(@obs)." files match]\n" if $self->verbose;

  # Store the result
  $self->obsGrp($grp);

}

=item B<_mktmpdir>

Make a temporary directory for storing intermediate files.

  $pkg->_mktmpdir();

Stores the directory in the tmpdir() method.

=cut

sub _mktmpdir {
  my $self = shift;
  my $root = $self->root_tmpdir;
  throw OMP::Error::FatalError("Attempt to create temporary directory failed because we have no root dir")
    unless $root;

  # Need to untaint prior to creating this directory
  $root = _untaint_dir($root);

  # create the directory. For now force cleanup at end. Need to
  # decide whether object destructor is okay to use since that implies
  # only one packaging per usage.
  my $dir = tempdir( DIR => $root, CLEANUP => 1 );

  # store it
  $self->tmpdir( $dir );

}


=item B<_mkutdir>

Make the UT date-stamped directory in which we will create the
tar files.

=cut

sub _mkutdir {
  my $self = shift;
  my $ut = $self->utdate;

  my $yyyymmdd = $ut->strftime("%Y%m%d");
  # untaint [strftime should untaint]
  $yyyymmdd = _untaint_YYYYMMDD( $yyyymmdd );

  my $tmpdir = $self->tmpdir;
  my $utdir = File::Spec->catdir($tmpdir, $yyyymmdd);

  # make the directory
  mkdir $utdir
    or croak "Error creating directory for UT files: $utdir - $!";

  $self->utdir( $utdir );

}

=item B<_mkftpdir>

Create the ftp directory that will contain the tar file. This directory
is given a random name based on a large random integer. Could just
as easily use Crypt::PassGen.

=cut

sub _mkftpdir {
  my $self = shift;
  my $ftproot = $self->ftp_rootdir;

  # untaint ftp root just in case
  $ftproot = _untaint_dir( $ftproot );

  my $key = $self->key;

  my $ftpdir = File::Spec->catdir($ftproot, $key);

  mkdir $ftpdir
    or croak "Error creating directory for FTP files: $ftpdir - $!";

  $self->ftpdir( $ftpdir );

}



=item B<_copy_data>

Copy the files from the data directory to our temporary directory
ready for copying.

  $pkg->_copy_data();

=cut

sub _copy_data {
  my $self = shift;
  my $grp = $self->obsGrp;

  my $outdir = $self->utdir();
  throw OMP::Error::FatalError("Output directory not defined for copy")
    unless defined $outdir;

  throw OMP::Error::FatalError("Output directory does not exist!")
    unless -d $outdir;

  # Loop over each file
  my $count = 0;
  for my $obs ($grp->obs) {
    my $file = $obs->filename;

    if (!defined $file) {
      print "File for this observation was not defined. Must skip.\n";
      next;
    }

    # what if we can not find it
    if ( !-e $file ) {
      print "Unable to locate file $file. Not copying\n";
      $obs->filename('');
      next;
    }

    # Get the actual filename without path
    my $base = basename( $file );
    my $outfile = File::Spec->catfile( $outdir, $base );

    print STDOUT "Copying file $base to temporary location..."
      if $self->verbose;

    my $status = copy( $file, $outfile);

    if ($status) {
      print "Complete\n" if $self->verbose;
      $count++;

      # change the filename in the object
      $obs->filename( $outfile );

    } else {
      print "Encountered error ($!). Skipping file\n" if $self->verbose;

      # effectively disable it
      $obs->filename( '' );

    }


  }

  print "Copied $count files out of ".scalar(@{$grp->obs}) ."\n"
    if $self->verbose;

  throw OMP::Error::FatalError("Unable to copy any files. Aborting.")
    if $count == 0;

}

=item B<_mktarfile>

Create a tar file from the copied data files.

  $pkg->_mktarfile();

=cut

sub _mktarfile {
  my $self = shift;

  # We need to know the directory to be tarred and the output directory
  my $utdir = $self->utdir;
  my $ftpdir = $self->ftpdir;
  my $utdate = $self->utdate;
  my $utstr = $utdate->strftime( "%Y%m%d" );

  $utstr = _untaint_YYYYMMDD( $utstr );

  # Generate the tar file name
  my $outfile = File::Spec->catfile( $ftpdir,
				     "ompdata_$utstr" . "_$$".".tar.gz"
				   );

  print STDOUT "Creating tar file ". basename($outfile) ."..."
    if $self->verbose;

  # Create the tar file
  # First need to cd to the temp directory (remembering where we started
  # from). Returns tainted dir
  my $cwd = getcwd;
  $cwd = _untaint_dir( $cwd );

  my $root = File::Spec->catdir($utdir, File::Spec->updir);
  chdir $root || croak "Error changing to tar directory $root: $!";

  # The directory we want to tar up is the last directory in $tardir
  my @dirs = File::Spec->splitdir( $utdir );
  my $tardir = $dirs[-1];

  # If we are using Archive::Tar (slow) we need to read all the files
  # from the directory
  if ($UseArchiveTar) {
    require Archive::Tar;

    # we also need to explicitly read that directory
    opendir my $dh, $utdir
      or croak "Error reading dir $utdir to get tar files: $!";
    my @files = map { File::Spec->catfile($tardir,$_) } 
      grep { $_ !~ /^\./ } readdir $dh;
    closedir $dh or croak "Error closing dir handle for $utdir: $!";

    # Finally create the tar file
    Archive::Tar->create_archive($outfile, 9, $tardir,@files )
	or croak "Error creating tar file in $outfile: ".&Tar::error;

  } else {
    # It is much faster to use the tar command directly
    # The tar command needs to come from a config file although
    # it would then have to be untained - for now just hardwire
    # Must give full path
    my $tarcmd;
    if ($^O eq 'solaris') {
      # GNU tar
      $tarcmd = "/usr/local/bin/tar -zcvf ";
    } elsif ($^O eq 'linux') {
      $tarcmd = "/bin/tar -zcvf ";
    } else {
      croak "Unable to determine tar command for OS $^O";
    }
    system("$tarcmd $outfile $tardir") && 
      croak "Error building the tar file: $!";


  }

  # change back again
  chdir $cwd || croak "Error changing back to directory $cwd: $!";

  print STDOUT "Done\n"
    if $self->verbose;

  # Store the tar file name
  $self->tarfile ( $outfile );

}

=item B<_purge_old_ftp_files>

Remove files that are older than 4 days from the FTP directory.

NOT YET IMPLEMENTED

Note that files and directories created in order to create the 
tar file itself are cleaned up automatically when the process
exits. [but will be left around if the previous invocation
crashed]. For that reason we look for old files in both root_tmpdir
and ftp_rootdir.

=cut

sub _purge_old_ftp_files {
  my $self = shift;

  # Get the directories
  my @dirs = ( $self->ftp_rootdir, $self->root_tmpdir );

  # loop over them, unlinking files that are older than 7 days
  find(\&_unlink_if_old, @dirs);

}

# Routine to unlink the old files
sub _unlink_if_old {
  my $file = shift;

  my @stat = stat $file;

  # get the current time
  my $time = time;

  # Get the change time
  my $ctime = $stat[10];

  # get the difference
  my $age = $time - $ctime;

  # convert to days [could use Time::Seconds]
  $age /= ONE_DAY;

  if ($age > OLD_AGE) {
    print "File is very old and should be removed: $file\n";
  }


}

# not a class method
sub _untaint_dir {
  my $dir = shift;
  Carp::confess "Can not untaint an undefined directory name!" unless defined $dir;
  if (-d $dir) {
    # untaint
    $dir =~ /^(.*)$/ && ($dir = $1);
  } else {
    croak("Directory [$dir] does not exist so we can not be sure we are allowed to untaint it!");
  }

}

sub _untaint_YYYYMMDD {
  my $utstr = shift;
  Carp::confess "Can not untaint an undefined date!" unless defined $utstr;
  if ($utstr =~ /^(\d\d\d\d\d\d\d\d)$/) {
    # untaint
    $utstr = $1;
  } else {
    croak("UT string [$utstr] does not match the expect format so we are not allowed to untaint it!");
  }


}


=back

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt> based on code
from Remo Tilanus.

=head1 COPYRIGHT

Copyright (C) 2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
