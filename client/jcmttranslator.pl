#!/local/perl-5.6/bin/perl

=head1 NAME

jcmttranslator - translate science program XML to ODFs

=head1 SYNOPSIS

  cat sp.xml | jcmttranslator > outfile

=head1 DESCRIPTION

Reads science program xml from standard input and writes the
translated odf file name to standard output. The filename is
suitable for reading into the new DRAMA Queue.

=head1 ARGUMENTS

The following arguments are allowed:

=over 4

=back

=head1 OPTIONS

The following options are supported:

=over 4

=item B<-help>

A help message.

=item B<-man>

This manual page.

=item B<-debug>

Do not send messages to the feedback system. Send all messages
to standard output.

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
my ($help, $man, $debug);
my $status = GetOptions("help" => \$help,
			"man" => \$man,
			"debug" => \$debug,
		       );

pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

# deubgging
$OMP::Translator::DEBUG = 1 if $debug;

# Now for the action
# Read from standard input
local $/ = undef;
my $xml = <>;

my $filename = OMP::TransServer->translate( $xml );

# convert the filename to an absolute path
print File::Spec->rel2abs($filename) ."\n";

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

