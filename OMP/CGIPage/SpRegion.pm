package OMP::CGIPage::SpRegion;

=head1 NAME

OMP::CGIPage::SpRegion - Save or plot the regions of a Science Program

=cut

use strict;
use warnings;

use OMP::SpRegion;

use CGI;
use CGI::Carp qw/fatalsToBrowser/;
use PGPLOT;

use OMP::CGIDBHelper;
use OMP::General;
use Starlink::AST::PGPLOT;

=head1 METHODS

=over 4

=item B<view_region>

Creates a page allowing the user to select the output format for the regions.

=cut

sub view_region {
  my $q = shift;
  my %cookie = @_;

  my $projectid = OMP::General->extract_projectid($cookie{'projectid'});
  die 'Did not recieve valid project ID.' unless $projectid;

  print $q->h2('Download or Plot Regions for ' . uc($projectid)),
        $q->start_form(),
        $q->p($q->b('Type of observations')),
        $q->blockquote(
          $q->radio_group(-name => 'type', -values => ['all', 'new', 'progress', 'complete'],
                          -default => 'all', -linebreak => 'true',
                          -labels => {all => 'All observations',
                                      new => 'New observations',
                                      progress => 'Observations in progress',
                                      complete => 'Completed observations'})),
        $q->p($q->b('Output format')),
        $q->blockquote(
          $q->radio_group(-name => 'format', -values => ['stcs', 'ast', 'png'],
                          -default => 'stcs', -linebreak => 'true',
                          -labels => {stcs => 'STC-S file',
                                      ast => 'AST region file',
                                      png => 'Plot as PNG image'})),
        $q->p(
          $q->hidden(-name => 'show_output', -value => 'true'),
          $q->submit(-value => 'Download / Plot')),
        $q->end_form;
}

=iten B<view_region_output>

Outputs the region file.

=cut

sub view_region_output {
  my $q = shift;
  my %cookie = @_;

  my %mime = (png => 'image/png',
              stcs => 'text/plain',
              ast => 'application/octet-stream');

  my %types = map {$_ => 1} qw/all new progress complete/;


  # Check input

  my $projectid = OMP::General->extract_projectid($cookie{'projectid'});
  die 'Did not recieve valid project ID.' unless $projectid;

  die 'Invalid output format' unless $q->param('format') =~ /^(\w+)$/;
  my $format = $1;
  die 'Unrecognised output format' unless exists $mime{$format};

  die 'Invalid output type' unless $q->param('type') =~ /^(\w+)$/;
  my $type = $1;
  die 'Unrecognised output format' unless exists $types{$type};


  # Prepare region object, by fetching the SP and converting it.
  # Note that safeFetchSciProg will print warnings, so we need to
  # redirect its output as we have not yet printed the script header.

  select(STDERR);
  my $sp = OMP::CGIDBHelper::safeFetchSciProg($projectid, $cookie{'password'});
  select(STDOUT);

  unless (defined $sp) {
    print $q->header(),
          $q->start_html('Error: no science program'),
          $q->h2('Error'),
          $q->p('The science program could not be fetched for this project.'),
          $q->end_html();
    return;
  }

  my $region = new OMP::SpRegion($sp);

  unless (defined $region) {
    print $q->header(),
          $q->start_html('Error: no regions found'),
          $q->h2('Error'),
          $q->p('No regions were found for this project.'),
          $q->end_html();
    return;
  }


  # Print the output.

  my %header = (-type => $mime{$format});
  $header{'-attachment'} = $projectid.'.'.$format
    unless $mime{$format} =~ /^image/;

  print $q->header(%header);

  if ($format eq 'png') {
    PGPLOT::pgbegin(0, '-/PNG', 1, 1);
    PGPLOT::pgwnad(0, 1, 0, 1);
    $region->plot_pgplot(type => $type);
    PGPLOT::pgend();
  }
  elsif ($format eq 'ast') {
    $region->write_ast(type => $type);
  }
  elsif ($format eq 'stcs') {
    $region->write_stcs(type => $type);
  }
  else {
    die 'Unrecognised format, not trapped by first check.';
  }
}

=back

=cut

1;

