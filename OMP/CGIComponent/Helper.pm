package OMP::CGIComponent::Helper;

=head1 NAME

OMP::CGIHelper - Helper for the OMP feedback system CGI scripts

=head1 SYNOPSIS

  use OMP::CGIComponent::Helper;
  use OMP::CGIComponent::Helper qw/flex_page/;

=head1 DESCRIPTION

Provide functions to generate commonly displayed items for the feedback
system CGI scripts, such as a table containing information on the current
status of a project.

=cut

use 5.006;
use strict;
use warnings;
use Carp;

our $VERSION = (qw$ Revision: 1.2 $ )[1];

use OMP::Config;
use OMP::General;

use vars qw/@ISA %EXPORT_TAGS @EXPORT_OK/;

require Exporter;

$| = 1;

@ISA = qw/Exporter/;

@EXPORT_OK = (qw/flex_page public_url private_url/);

%EXPORT_TAGS = (
		'all' =>[ @EXPORT_OK ],
	       );

Exporter::export_tags(qw/ all /);

# A default width for HTML tables
our $TABLEWIDTH = 720;

=head1 Routines

=over 4

=item B<flex_page>

Routine to serve the UKIRT flex page through the OMP feedback pages.

  flex_page($q, %cookie);

=cut

sub flex_page {
  my $q = shift;
  my %cookie = @_;

  my $sem;
  my $tainted = $q->url_param('sem');
  if ($tainted =~ m!^(\d{2}\w)$!) {
    $sem = $1;
  }

  # Default to current semester if we couldn't untaint the semester url
  # param (or it just wasn't provided)
  if (! $sem) {
    $sem = OMP::General->determine_semester( tel => 'UKIRT' );
  }

  $sem = lc($sem);
  my $flexpage = "/web/UKIRT/observing/omp/$sem/Flex_programme_descriptions.html";

  # Read in flex page
  open(FLEX, $flexpage) or die "Unable to open flex page [$flexpage]: $!";

  local $/ = undef;
  my $output = <FLEX>;  # Slurp!

  close(FLEX);

  $output =~ s/<body/<body BGCOLOR=\"\#BBBBEE\"/;

  # Display the page
  print "Content-Type: text/html\n\n";
  print $output;
}

=item B<public_url>

Return the URL where public cgi scripts can be found.

  $url = OMP::CGIComponent::Helper->public_url();

=cut

sub public_url {
  # Get the base URL
  my $url = OMP::Config->getData( 'omp-url' );

  # Now the CGI dir
  my $cgidir = OMP::Config->getData( 'cgidir' );

  return "$url" . "$cgidir";
}

=item B<private_url>

Return the URL where private cgi scripts can be found.

  $url = OMP::CGIComponent::Helper->private_url();

=cut

sub private_url {
  # Get the base URL
  my $url = OMP::Config->getData( 'omp-private' );

  # Now the CGI dir
  my $cgidir = OMP::Config->getData( 'cgidir' );

  return "$url" . "$cgidir";
}

=back

=head1 AUTHORS

Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>,
Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
