=head1 NAME

OMP::PackageData - Package up data for retrieval by PI

=head1 SYNOPSIS

  use OMP::PackageData;

  my $pkg = new OMP::PackageData( projectid => 'M02BU127',
                                  utdate => '2002-09-15');

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

use vars qw/ $VERSION /;
$VERSION = '0.01';

use File::Spec;
use OMP::General;
use OMP::Error;
use OMP::Info::ObsGroup;
use File::Temp qw/ tempdir /;

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

Object constructor. Requires a project and a ut date.

  $pkg = new OMP::PackageData( projectid => 'blah',
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
		   RootTmpDir => File::Spec->tmpdir,
		   TmpDir => undef,
		   FtpRootDir => undef,
		   Verbose => 1,
		   ObsGroup => undef,
		   TarFile => undef,
		   Password => undef,
		  };

  if (@_) {
    $pkg->_populate( @_ );
  }

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
	throw OMP::Error::BadArgs("Unable to parse string '$ut' as a date. Must be YYYY-MM-DD");
	
	# overwrite $ut
	$ut = $parsed;

      } elsif (!UNIVERSAL::isa($ut, "Time::Piece") {
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
  $v = $pkg->verbose(1);

=cut

sub verbose {
  my $self = shift;
  if (@_) {
    $self->{Verbose} = shift;
  }
  return $self->{Verbose};
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
appear (see C<ftp_tmpdir>).

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
to on the FTP server. Defaults to C<root_tmpdir> if undefined.

Directories in this directory older than 1 day will be removed
automatically when new directories are created.

=cut

sub ftp_rootdir {
  my $self = shift;
  if (@_) {
    $self->{FtpRootDir} = shift;
  }
  # Default to RootTmpDir if not defined
  my $dir = $self->{FtpRootDir};
  return (defined $dir ? $dir : $self->root_tmpdir);
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


=back

=head2 General Methods

=over 4

=item B<pkgdata>

Create temporary directory, copy data into the directory,
create tar file and place tar file in FTP directory.

  $pkg->pkgdata();

Once packaged, the tar file name can be retrieved using the
tarfile() method.

=cut

sub pkgdata {
  my $self = shift;

  # Verify project password
  OMP::ProjServer->verifyPassword($self->projectid, $self->password)
      or throw OMP::Error::Authentication("Unable to verify project password");

  # Create the temp directory

  # Copy the data into it

  # Create the tar file from the temp direcotry to
  # the FTP directory

  # store the tar file name

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

  # Need to get the telescope associated with this project
  # Should ObsGroup do this???
  my $proj = OMP::ProjServer->($self->projectid, $self->password, 'object');

  my $tel = $proj->telescope;

  # Now need to do a query on the archive
  # Since we need the calibrations we do a full ut query and
  # then select the calibrations and project info. This needs
  # to be done in ObsGroup.
  my $grp = new OMP::Info::ObsGroup( telescope => $tel,
				     utdate => $self->utdate,
				   );

  # Now go through and get the bits me need
  my @match
  for my $obs ($grp->obs) {
    if ($obs->projectid eq $self->projectid ||
       $obs->iscal) {
      push(@match, $obs);
    }
  }

  $grp->obs(\@match);
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

  # create the directory. We will cleanup ourselves in the destructor
  my $dir = tempdir( DIR => $root );

  # store it
  $self->tmpdir( $dir );

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
