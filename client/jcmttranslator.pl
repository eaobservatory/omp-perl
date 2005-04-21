#!/local/perl/bin/perl -X

=head1 NAME

jcmttranslator - translate science program XML to ODFs

=head1 SYNOPSIS

  cat sp.xml | jcmttranslator > outfile

  jcmttranslator -sim msb.xml

=head1 DESCRIPTION

Reads science program xml either from standard input or by filename and writes the
translated configuration to disk. The name of the file that should be loaded into
the queue is written to standard output.

=head1 ARGUMENTS

The input science program can either be supplied as a filename argument or by
piping the XML from standard input. A supplied filename supercedes standard input.

=head1 OPTIONS

The following options are supported:

=over 4

=item B<-help>

A help message.

=item B<-man>

This manual page.

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
Supercedes the C<-cwd> option if both are specified.

=item B<-cwd>

Write the translated files to the current working directory
rather than to the standard translation directory location.
C<-transdir> supercedes C<-cwd> if both are specified.

=item B<-debug>

Turn on debugging messages.

=back

=cut

use warnings;
use strict;

use Pod::Usage;
use Getopt::Long;

# run relative to the client directory
use FindBin;
use lib "$FindBin::RealBin/../";



# Load the servers (but use them locally without SOAP)
use OMP::TransServer;
use File::Spec;

# Options
my ($help, $man, $debug, $cwd, $old, $sim, $transdir);
my $status = GetOptions("help" => \$help,
			"man" => \$man,
			"debug" => \$debug,
			"cwd" => \$cwd,
			"sim" => \$sim,
			"old" => \$old,
			"transdir=s" => \$transdir,
		       );

pod2usage(1) if !$status;

pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

# debugging
$OMP::Translator::DEBUG = 1 if $debug;

# Translation directory override
if ($transdir) {
  OMP::Translator->outputdir($transdir);
} elsif ($cwd) {
  OMP::Translator->outputdir(".");
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
    open my $fh, "< $file" or die "Error reading input science program from file $file: $!";
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

my $filename = OMP::TransServer->translate( $xml, { simulate => $sim });

# convert the filename to an absolute path
print File::Spec->rel2abs($filename) ."\n";

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

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

=cut

