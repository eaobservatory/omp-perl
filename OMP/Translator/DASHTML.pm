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
use warnings::register;

use OMP::Error qw/ :try /;
use Astro::Catalog;
use Astro::Catalog::Star;
use File::Spec;
use File::Copy;
use Time::Seconds;
use Time::HiRes qw/ gettimeofday /;

# Location of ouytput directory from the vaxes viewpoint
our $VAX_TRANS_DIR = "OBSERVE:[OMPODF]";

# Debugging
our $DEBUG = 0;

=head1 METHODS

=over 4

=item B<new>

  $tr = new OMP::Translator::DASHTML( $html, \@targets, \%files,
                                      $projectid, $catfile );

The projectid is used for tagging the MSB targets in the output catalogue.
The catfile argument specifies the root name to be used for writing catalogue
files (since this is embedded in the HTML by the translator).

No arguments are allowed in order to create a blank container (then
use the push() method to extend it.

=cut

sub new {
  my $proto = shift;
  my $class = ( ref($proto) || $proto );

  my ($html, $targ, $files, $catfile, $proj) = ('', [], {}, undef, undef);
  if ( @_ ) {
    throw OMP::Error::FatalError( "Need 5 args not ".scalar(@_) )
      unless scalar(@_) == 5;
    ($html, $targ, $files, $catfile, $proj) = @_;
  }

  return bless {
                HTML => $html,
                TARGETS => [ @$targ ],
                FILES => { %$files },
                CATFILE => $catfile,
                PROJECTID => $proj,
               },
               $class;

}

=head2 General Methods

=over 4

=item B<telescope>

Telescope name (JCMT).

=cut

sub telescope {
  return "JCMT";
}

=item B<instrument>

Instrument name (DAS).

=cut

sub instrument {
  return "DAS";
}

=item B<duration>

Observation duration (unknown).

=cut

sub duration {
  return Time::Seconds->new(0);
}


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
  open my $fh, '>', $file or
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
    open my $fh, '>', $outfile or
      throw OMP::Error::FatalError("Could not write translation file [$file] to disk: $!\n");

    for my $l ( @{ $files{$f} } ) {
      chomp($l);
      print $fh "$l\n";
    }

    close($fh)
      or throw OMP::Error::FatalError("Error closing translation [$outfile]: $!\n");

    # and make sure the file protections are correct
    chmod $options{chmod}, $outfile
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
    $_->comment("Project: ".$self->{PROJECTID});
  }

  # Insert the new sources at the start
  unshift(@{$cat->allstars},
          map {new Astro::Catalog::Star(Coords=>$_)} @targets);

  # And write it out
  my $catroot = ( $self->{CATFILE} || "omp.cat" );
  my $outcat = File::Spec->catfile( $TRANS_DIR, $catroot);
  $cat->write_catalog( File => $outcat, Format => 'JCMT' );

  chmod $options{chmod}, $outcat
    if exists $options{chmod};

  # and make a backup
  copy( $outcat, $outcat . "_" . $suffix);


  return $file;
}

=item B<push_config>

Append a translation or translations to this object.

  $das->push_config( @more );

Argument must be a OMP::Translator::DASHTML object.

If no projectid or catalogue file name is defined, the first one
available will be copied into this object.

=cut

sub push_config {
  my $self = shift;

  for my $new ( @_ ) {

    my $cat = $new->{CATFILE};
    my $proj = $new->{PROJECTID};
    $self->{CATFILE} = $cat unless $self->{CATFILE};
    $self->{PROJECTID} = $proj unless $self->{PROJECTID};

    $self->{HTML} .= $new->{HTML};

    # Astro::Catalog will filter out duplicates
    push(@{ $self->{TARGETS} }, @{ $new->{TARGETS} } );

    # Need to fix up pattern file names
    # but for now assume that they are unique within a single
    # instance of the translator
    for my $f ( keys %{ $new->{FILES} } ) {
      if ( exists $self->{FILES}->{$f}) {
        throw OMP::Error::FatalError("Internal error file $f exists in both instances of object");
      }
      $self->{FILES}->{$f} = $new->{FILES}->{$f};
    }
  }
}

=back

=head2 Class Methods

=over 4

=item B<outputdir>

Default output directory for writing the HTML and associated files.

  $out = OMP::Translator::DASHTML->outputdir();
  OMP::Translator::DASHTML->outputdir( $newdir );

This is not to be confused with the translator default writing directory
defined in C<OMP::Translator::DAS>.

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

=item B<container_class>

Name of the class that can be used to store multiple configurations.
In this case, returns the name of the class itself since the append
method can be used.

=cut

sub container_class {
  my $class = shift;
  return (ref $class || $class);
}

=back

=head1 NOTES

This is essentially a completely private class that should only be
used by the DAS translator (C<OMP::Translator::DAS>).

=head1 COPYRIGHT

Copyright (C) 2002-2005 Particle Physics and Astronomy Research Council.
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
