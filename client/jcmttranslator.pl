#!/local/perl/bin/perl -X

=head1 NAME

jcmttranslator - translate science program XML to ODFs

=head1 SYNOPSIS

  cat sp.xml | jcmttranslator > outfile

  jcmttranslator -sim msb.xml

=head1 DESCRIPTION

Reads science program xml either from standard input or by filename
and writes the translated configuration to disk. The name of the file
that should be loaded into the queue is written to standard output.

=head1 ARGUMENTS

The input science program can either be supplied as a filename
argument or by piping the XML from standard input. A supplied filename
supercedes standard input.

=head1 OPTIONS

The following options are supported:

=over 4

=item B<-help>

A help message.

=item B<-man>

This manual page.

=item B<-version>

Display version information.

=item B<-old>

By default the file name written to stdout, is in a format suitable
for upload directly to the modern OCS queue (an XML format). If this
switch is enabled, the file written to stdout will be specific to
the translated config class (ie a single HTML file for DAS translations,
a SCUBA ODF macro for SCUBA). Note that if this switch is enabled,
mixed instrument MSBs are not supported.

=item B<-sim>

Enables simulation mode for translators that support this.

=item B<-transdir>

Specify an explicit directory to receive the translated output files.
Supercedes the C<-cwd> and C<-tempdir> options if specified in conjunction
with other directory options.

=item B<-cwd>

Write the translated files to the current working directory
rather than to the standard translation directory location.
C<-transdir> supercedes C<-cwd> if both are specified. It is an
error to set both C<-cwd> and C<-transdir>.

=item B<-tempdir>

Writes the translated files to the configured temporary translation
directory. It is an error to set both C<-cwd> and C<-transdir>

=item B<-debug>

Turn on debugging messages.

=item B<-verbose>

Turn on verbose messaging.

=item B<-log>

Log verbose messages to the logging directory (defined in the OMP
config system but usually /jac_logs/YYYYMMDD/translator in a JAC system).

=back

=cut

use warnings;
use strict;

use File::Spec;
use Pod::Usage;
use Getopt::Long;

# run relative to the client directory. Also set config directory.
use FindBin;
use constant OMPLIB => File::Spec->catdir("$FindBin::RealBin",
					  File::Spec->updir );
use lib OMPLIB;
$ENV{'OMP_CFG_DIR'} = File::Spec->catdir( OMPLIB, "cfg" )
  unless exists $ENV{'OMP_CFG_DIR'};


# We need to set the search path for the Queue classes
# and the OCS Config classes. Hard wire the location.
use lib qw| /jac_sw/hlsroot/ocsq/lib |;
use lib qw| /jac_sw/hlsroot/OCScfg/lib |;

# Load the servers (but use them locally without SOAP)
use OMP::TransServer;

# Need config system
use OMP::Config;
use OMP::Error qw/ :try /;

# Options
my ($help, $man, $debug, $cwd, $tempdir, $old, $sim, $transdir, $verbose,
   $version, $log);
my $status = GetOptions("help" => \$help,
			"man" => \$man,
			"debug" => \$debug,
			"cwd" => \$cwd,
			"sim" => \$sim,
			"old" => \$old,
			"tempdir" => \$tempdir,
			"transdir=s" => \$transdir,
			"verbose" => \$verbose,
			"version" => \$version,
			"log" => \$log,
		       );

pod2usage(1) if !$status;

pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

if ($version) {
  my $id = '$Id$ ';
  print "jcmttranslator - Translate Science Program MSBs to OCS configs\n";
  print " Source code revision: $id\n";
  exit;
}


# debugging
$OMP::Translator::DEBUG = $debug;

# verbose
$OMP::Translator::VERBOSE = $verbose;;

# Translation directory override
if ($transdir) {
  print "Overriding output directory. Using '$transdir'\n" if $verbose;
  OMP::Translator->outputdir($transdir);
} elsif ($cwd || $tempdir) {
  if ($cwd && $tempdir) {
    die "The -cwd and -tempdir options can not be used together.\n";
  }
  if ($cwd) {
    print "Overriding output directory. Using current directory\n" if $verbose;
    OMP::Translator->outputdir(File::Spec->curdir);
  } elsif ($tempdir) {
    # this should fail if no temp dir is defined
    my $tmp = OMP::Config->getData( "jcmt_translator.temptransdir" );
    if ($tmp) {
      print "Overriding output directory. Using '$tmp'\n" if $verbose;
      OMP::Translator->outputdir( $tmp );
    } else {
      die "No temporary translator directly defined.";
    }
  }
}


# Configure translation mode
OMP::Translator->backwards_compatibility_mode( 1 ) if $old;

# Now for the action
# Read from standard input or from the command line.
my $xml;
{
  # Can not let this localization propoagate to the OMP classes
  # since this affects the srccatalog parsing
  local $/ = undef;

  if (@ARGV) {
    my $file = shift(@ARGV);
    open my $fh, '<', $file or die "Error reading input science program from file $file: $!";
    $xml = <$fh>;
  } else {
    # Stdin should be readable
    my $rin = '';
    vec($rin,fileno(STDIN),1) = 1;
    my $nfound = select($rin,undef,undef,0.1);

    if ($nfound) {
      $xml = <>;
    } else {
      die "No filename specified for science program and nothing appearing from pipe on STDIN\n";
    }

  }

}

my $filename = OMP::TransServer->translate( $xml, { simulate => $sim,
						    log => $log});

# convert the filename to an absolute path
print File::Spec->rel2abs($filename) ."\n";

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002-2006 Particle Physics and Astronomy Research Council.
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

