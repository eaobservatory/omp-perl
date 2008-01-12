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
$VERSION = '0.02';

# Do we want to ues the slower Archive::Tar (but which does not have
# taint issues)
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
use OMP::Constants qw/ :fb /;
use OMP::FBServer;
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
                   TarFile => [],
                   Password => undef,
                   UTDir => undef,
                   FTPDir => undef,
                   Key => undef,
                   IncCal => 1,
                  },
                  $class;

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

Names of the final packaged tar files.

  @files = $pkg->tarfile;
  $file = $pkg->tarfile;

In scalar context returns the first file.

=cut

sub tarfile {
  my $self = shift;
  if (@_) {
    @{$self->{TarFile}} = @_;
  }
  return (wantarray ? @{$self->{TarFile}} :
                     (scalar @{$self->{TarFile}} ? $self->{TarFile}->[0] : undef )
         );
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

  # Add a comment to the log
  $self->_log_request();

  # Purge files older than the limit
  $self->_purge_old_ftp_files();

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

  # Send a message to the feedback system
  $self->_add_comment();

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

Retrieve the URLs required to retrieve the completed tar files.

  @urls = $pkg->ftpurl;

Returns undef (in scalar context) or empty list (list context) if a
tarfile has not been created or if no key is defined.

Returns the first URL in scalar context.

If a list of file names are provided as an argument, those files are
converted into urls rather than the internal object tarfiles.

=cut

sub ftpurl {
  my $self = shift;

  # Check for a key and abort early if none found
  my $key = $self->key;
  return (wantarray ? () : undef) unless defined $key;

  # Get all the tarfiles (either from arglist or from object)
  my @tarfiles = (@_ ? @_ : $self->tarfile);
  return (wantarray ? () : undef) unless @tarfiles;

  # Get the base URL
  my $baseurl = OMP::Config->getData('ftpurl');

  # Form urls [ "/" is the proper delimiter]
  my @urls = map { "$baseurl/$key/". basename($_) } @tarfiles;

  # Return, checking context
  return (wantarray ? @urls : $urls[0] );
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

  # Pass our query onto the ObsGroup constructor which can correctly handle the inccal
  # switch and optimize for it.
  my %query = ( telescope => $tel,
                date => $self->utdate,
                inccal => $self->inccal,
                projectid => $self->projectid,
              );

  # information for the user
  print STDOUT "Querying database for relevant data files...[tel:$tel / ut:".
    substr($query{date},0,8)." / project '".$self->projectid."']\n"
      if $self->verbose;

  # Query the database
  my $grp = new OMP::Info::ObsGroup( %query, verbose => $self->verbose,
                                     ignorebad => 1, sort => 1 );

  # Inform them of how many we have found
  print STDOUT "Done [".$grp->numobs." observations match]\n" if $self->verbose;

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

    # Untaint the filename
    my $file;
    if ($obs->filename =~ m/(.*\.(sdf|gsd))$/ ) {
      $file = $1;
    } else {
      print "Error untainting filename. Must skip\n";
      next;
    }

    #    my $file = $obs->filename;

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
    my $base = $obs->simple_filename;
    if ($base =~ /(.*\.(sdf|gsd|dat))$/) {
      $base = $1;
    } else {
      print "Error untainting base file. Must skip\n";
      next;
    }

    # Kludge to serve up ACSIS cubes
    if ($base =~ /^a(\d{8})_(\d{5})_\d{2}_\d{4}\.sdf$/) {
      my $date = $1;
      my $obsnum = $2;

      $base = "ac${date}_${obsnum}_01_01.sdf";
      $file = "/jcmtdata/raw/acsis/acsis01/gridder01/$date/cubes/$base";
    }

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

  # Open the directory
  opendir my $dh, $utdir
    or croak "Error reading dir $utdir to get tar files: $!";

  # Read them into an array, ignoring hidden files
  my @files = map { File::Spec->catfile($tardir,$_) }
      grep { $_ !~ /^\./ } readdir $dh;

  # And untaint them all
  @files = _untaint_data_files( @files );

  # Close the directory handle
  closedir $dh or croak "Error closing dir handle for $utdir: $!";

  # Now need to create an array of arrays where each sub-array
  # contains files up to a certain (uncompressed) limit specified in the config
  # system. Note that it is obviously easier to group by uncompressed size!
  my @infiles;

  # Get the upper limit in mega bytes (converted to bytes)
  my $upperlimit = OMP::Config->getData('tarfilelimit') * 1024 * 1024;

  my $size = 0;
  my $total = 0;
  my $tmp = [];
  for my $file (@files) {
    # Store the file in the current array and add its size to the current total
    my $filesize = -s $file;
    $size += $filesize;
    $total += $filesize;
    push(@$tmp, $file);

    # check if we have exceeded the current limit
    if ($size > $upperlimit) {
      # Exceed limit so store the array ref in @infiles and create a new temp array
      push(@infiles, $tmp);
      $tmp = [];
      $size = 0;
    }
  }
  # if we have something in $tmp, push it onto infiles
  push(@infiles, $tmp) if scalar(@$tmp);

  # Somewhere to store all the tar file names
  my @outfiles;

  # Convenience variable containing the number of tar files
  my $ntar = scalar(@infiles);

  # Generate the tar file name [include a counter]
  my $counter = 1; # People expect us to start at 1

  # loop over all the file groups
  print STDOUT "Total amount of data to be retrieved: ".
     _format_bytes( $total )."\n"
    if $self->verbose;
  for my $grp (@infiles) {

    # Create the output file name for this group. Special case suffix if there is only one
    # input group
    my $suffix = ( $ntar > 1 ? "_$counter" : '' );
    my $outfile = File::Spec->catfile( $ftpdir,
                                       "ompdata_$utstr" . "_$$". $suffix .".tar.gz"
                                     );

    print STDOUT "Creating tar file $counter [of $ntar] " . basename($outfile) ."...\n"
      if $self->verbose;


    # If we are using Archive::Tar (slow) we need to read all the files
    # from the directory
    if ($UseArchiveTar) {
      require Archive::Tar;

      # Finally create the tar file
      Archive::Tar->create_archive($outfile, 2, $tardir,@$grp )
        or croak "Error creating tar file in $outfile: ".&Tar::error;

    } else {
      # It is much faster to use the tar command directly
      # The tar command needs to come from a config file although
      # it would then have to be untainted - for now just hardwire
      # Must give full path
      my $tarcmd;
      if ($^O eq 'solaris') {
        # GNU tar
        $tarcmd = "/usr/local/bin/tar";
      } elsif ($^O eq 'linux') {
        $tarcmd = "/bin/tar";
      } else {
        croak "Unable to determine tar command for OS $^O";
      }
      # Locally Disable $PATH under taint checking
      #  - we need /usr/local/bin for gzip on Solaris
      #    when running tar
      local $ENV{PATH} = "/usr/bin:/bin:/usr/local/bin";

      system("$tarcmd","-zcvf",$outfile,@$grp) &&
          croak "Error building the tar file: $!";
    }

    # Store the tarfiles
    push(@outfiles, $outfile);

    # Print message in verbose mode
    if ($self->verbose) {
      my $url = $self->ftpurl($outfile);
      print STDOUT "Tar File $counter of $ntar ready for retrieval from: <a href=\"$url\">here</a>\n";
    }

    # increment the counter
    $counter++;

  }

  # change back again
  chdir $cwd || croak "Error changing back to directory $cwd: $!";

  print STDOUT "Done\n"
    if $self->verbose;

  # Store the tar file name
  $self->tarfile ( @outfiles );

}

=item B<_log_request>

Write a message in the OMP log describing the request for data.

=cut

sub _log_request {
  my $self = shift;
  my $projectid = $self->projectid();
  my $utdate = $self->utdate();

  # String representations
  my $pstr = (defined $projectid ? $projectid : '<undefined>' );
  my $utstr = (defined $utdate ? $utdate->strftime('%Y-%m-%d'): '<undefined>');

  OMP::General->log_message("Request received to retrieve archive data for project $pstr for UT date $utstr");

}

=item B<_add_comment>

Send a message to the feedback system indicating that the data
have been packaged.

  $pkg->_add_comment();

=cut

sub _add_comment {
  my $self = shift;

  my $projectid = $self->projectid();
  my $utdate = $self->utdate();
  my ($user, $host, $email) = OMP::General->determine_host;
  my $utstr = (defined $utdate ? $utdate->strftime('%Y-%m-%d'): '<undefined>');

  # In some cases with weird firewalls the host is not actually available
  # Have not tracked down the reason yet so for now we allow it to
  # go through [else data retrieval does not work]
  $host = (length($host) > 0 ? $host : '<undefined>');

  # Get project PI name for inclusion in feedback message
  my $project = OMP::ProjServer->projectDetails( $projectid, $self->password, "object" );
  my $pi = $project->pi;

  OMP::FBServer->addComment(
                            $projectid,
                            {
                             subject => "Data requested",
                             author => undef,
                             program => $0,
                             sourceinfo => $host,
                             status => OMP__FB_SUPPORT,
                             text => "<html>Data have been requested by $email for project $projectid from UT $utstr<br><br>Project PI: $pi",
                             msgtype => OMP__FB_MSG_DATA_REQUESTED,
                            }
                           )

}

=item B<_purge_old_ftp_files>

Remove files that are older than 4 days from the FTP directory.

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
  # do not bother doing a chdir
  find({ wanted => \&_unlink_if_old,
         no_chdir => 1,
         untaint => 1,
       },
         @dirs);

}

# Routine to unlink the old files
sub _unlink_if_old {
  my $file = $File::Find::name;
  return unless defined $file;

  my @stat = stat $file;

  # get the current time
  my $time = time;

  # Get the change time
  my $ctime = $stat[10];

  # get the difference
  my $age = $time - $ctime;

  # convert to days [could use Time::Seconds]
  $age /= ONE_DAY;

  # Remove it if it is old and not a directory
  # AND is a tar file or a data file
  # Not sure if doing an rmtree will really hurt
  # Should get the patterns for .sdf from config system
  if ($age > OLD_AGE && !-d _ ) {
    # Must untaint
    my $untaint;
    if ($file =~ /(.*\.tar\.gz)$/) {
      $untaint = $1;
    } elsif ($file =~ /(.*\.sdf)$/) {
      $untaint = $1;
    }
    unlink $untaint if defined $untaint;
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

sub _untaint_data_files {
  my @files = @_;

  # these files were read from the file system. Simply make sure
  # that they only have alphabetical, _ and . in the name
  # They will have a directory prefix
  my @untaint;
  for my $f (@files) {
    if ($f =~ /^(\d+\/[A-Za-z0-9_.]+)$/) {
      push(@untaint, $1);
    } else {
      croak "File [$f] does not pass untaint test";
    }
  }
  return @untaint;
}

sub _format_bytes {
  my $nbytes = shift;
  return "0B" unless defined $nbytes;
  my @prefix = ( "K", "M", "G", "T", "P", "E" );
  my $pre = "";
  while ($nbytes > 1024) {
    $nbytes /= 1024;
    $pre = shift(@prefix);
  }
  return sprintf("%.1f%sB",$nbytes,$pre);
}

=back

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt> based on code
from Remo Tilanus.

=head1 COPYRIGHT

Copyright (C) 2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program (see SLA_CONDITIONS); if not, write to the
Free Software Foundation, Inc., 59 Temple Place, Suite 330,
Boston, MA  02111-1307  USA


=cut

1;
