package OMP::Translator::DASHTML;

=head1 NAME

OMP::Translator::DASHTML - Simple wrapper for translated DAS HTML

=head1 SYNOPSIS

 $tr = new OMP::Translator::DASHTML( $html, \@targets, \%files );

 $tr->write_file();
 $tel = $tr->telescope(); # JCMT
 $inst = $tr->instrument(); # DAS
 $dur = $tr->duration();    # 0


=head1 DESCRIPTION

The DAS translator is designed to generate an HTML description of the
observation, a source catalogue and a set of pattern files. This class provides a lightweight wrapper to this information, providing the minimum methods to support the updated translator infrastructure (as opposed to the "write it all to disk at once" infrastructure).

=cut

use 5.006;
use strict;
use warnings;

use OMP::Error qw/ :try /;
use Astro::Catalog;
use Astro::Catalog::Star;
use File::Spec;
use Time::HiRes qw/ gettimeofday /;

# Location of ouytput directory from the vaxes viewpoint
our $VAX_TRANS_DIR = "OBSERVE:[OMPODF]";

# Debugging
our $DEBUG = 0;

=head1 METHODS

=over 4

=item B<new>

  $tr = new OMP::Translator::DASHTML( $html, \@targets, \%files, $catfile );

The catfile argument specifies the root name to be used for writing catalogue
files (since this is embedded in the HTML by the translator).

=cut

sub new {
  my $proto = shift;
  my $class = ( ref($proto) || $proto );
  throw OMP::Error::FatalError( "Need 4 args not ".scalar(@_) )
    unless scalar(@_) == 4;
  my ($html, $targ, $files, $catfile) = @_;

  return bless {
		HTML => $html,
		TARGETS => [ @$targ ],
		FILES => { %$files },
		CATFILE => $catfile,
	       };

}

=head2 General Methods

=over 4

=item B<write_file>

Write the translated information to disk.

  $outfile = $das->write_file();
  $outfile = $das->write_file( $dir, \%opts );

If no directory is specified, the config is written to the directory
returned by OMP::Translator::DASHTML->outputdir(). The C<outputdir> method is
a class method, there is no scheme for overriding the default output
directory per object.

Additional options can be supplied through the optional hash (which must
be the last argument). Supported keys are:

  chmod => file protection to be used for output files. Default is to
           use the current umask.

Returns the output filename with path information for the file written in
the root directory.

This routine writes an HTML file and associated catalogue and pattern
files. Backup files are also written that are timestamped to prevent
overwriting.  An accuracy of 1 milli second is used in forming the
unique names.

=cut

sub write_file {
  my $self = shift;

  # Look for hash ref as last arg and read options
  my $newopts;
  $newopts = pop() if ref($_[-1]) eq 'HASH';
  my %options = ();
  %options = (%options, %$newopts) if $newopts;

  # Now if we have anything left its a directory
  my $TRANS_DIR = shift;

  # default value for class
  $TRANS_DIR = $self->outputdir unless defined $TRANS_DIR;

  # Write this HTML file to disk along with the patterns and all the
  # target information to a catalogue

  # We always write backup files tagged with the current time to millisecond
  # resolution.
  my ($epoch, $mus) = gettimeofday;
  my $time = gmtime();
  my $suffix = $time->strftime("%Y%m%d_%H%M%S") ."_".substr($mus,0,3);

  # The public easy to recognize name of the html file
  my $htmlroot = File::Spec->catfile( $TRANS_DIR, "hettrans" );
  my $htmlfile = $htmlroot . ".html";

  # The internal name
  my $file = $htmlroot . "_" . $suffix . ".html";
  open my $fh, ">$file" or 
  throw OMP::Error::FatalError("Could not write HTML translation [$file] to disk: $!\n");

  print $fh $self->{HTML};

  close($fh) 
  or throw OMP::Error::FatalError("Error closing HTML translation [$file]: $!\n");

  # and make sure the file protections are correct
  chmod $options{chmod}, $file
    if exists $options{chmod};

  # Now for a soft link - the html file is not important because we will
  # return the timestamped file to prevent cache errors in mozilla
  # It is there as a back up
  if (-e $htmlfile) {
    unlink $htmlfile;
  }
  symlink $file, $htmlfile;

  # Get the files
  my %files = %{ $self->{FILES} };

  # Now the pattern files et al
  for my $f (keys %files) {
    my $outfile = File::Spec->catfile( $TRANS_DIR, $f );
    open my $fh, ">$outfile" or
      throw OMP::Error::FatalError("Could not write translation file [$file] to disk: $!\n");

    for my $l ( @{ $files{$f} } ) {
      chomp($l);
      print $fh "$l\n";
    }

    close($fh) 
      or throw OMP::Error::FatalError("Error closing translation [$outfile]: $!\n");

    # and make sure the file protections are correct
    chmod $options{chmod}, $f
      if exists $options{chmod};

    # and make a backup
    copy( $f, $f . "_" . $suffix);

  }

  # Now the catalogue file
  my @targets = @{ $self->{TARGETS} };

  my $cat;
  eval {
    $cat = new Astro::Catalog(Format => 'JCMT',
			      File => '/local/progs/etc/poi.dat');
  };
  unless (defined $cat) {
    warnings::warnif("Unable to read local pointing catalogue.");
    $cat = new Astro::Catalog() unless defined $cat;
  }
  $cat->origin("JCMT DAS Translator");

  # For each of the targets add the projectid
  for (@targets) {
    $_->comment("Project: $projectid");
  }

  # Insert the new sources at the start
  unshift(@{$cat->allstars},
	  map {new Astro::Catalog::Star(Coords=>$_)} @targets);

  # And write it out
  my $outfile = File::Spec->catfile( $TRANS_DIR, $self->{CATFILE});
  $cat->write_catalog( File => $outfile, Format => 'JCMT' );

  chmod $options{chmod}, $outfile
    if exists $options{chmod};

  # and make a backup
  copy( $outfile, $outfile . "_" . $suffix);


  return $file;
}

=item B<append>

Append a translation to this object.

  $das->append( $das2 );

Argument must be a OMP::Translator::DASHTML object.

=cut

sub append {
  my $self = shift;
  my $new = shift;

  $self->{HTML} .= $new->{HTML};
  push(@{ $self->{TARGETS} }, @{ $new->{TARGETS} } );

  # Need to fix up pattern file names

}

=back

=head2 Class Methods

=over 4

=item B<outputdir>

Default output directory for writing the HTML and associated files.

  $out = OMP::Translator::DASHTML->outputdir();
  OMP::Translator::DASHTML->outputdir( $newdir );

=cut

  {
    my $outputdir = "/observe/ompodf";
    sub outputdir {
      my $class = shift;
      if ( @_ ) {
	$outputdir = shift;
      }
      return $outputdir;
    }
}



=back

=head1 NOTES

This is essentially a completely private class that should only be
used by the DAS translator (C<OMP::Translator::DAS>).

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

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut

1;
