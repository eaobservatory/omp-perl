package OMP::CGI;

=head1 NAME

OMP::CGI - Functions for the OMP Feedback pages

=head1 SYNOPSIS

use OMP::CGI(qw/:feedback/);

=head1 DESCRIPTION

This class provides functions for use with the OMP Feedback CGI scripts.

=cut

use 5.006;
use strict;
use warnings;
use Carp;
our $VERSION = (qw$ Revision: 1.2 $ )[1];

use vars qw/@ISA %EXPORT_TAGS @EXPORT_OK/;

require Exporter;

@ISA = qw/Exporter/;

my @feedback = qw/sideBar ompHeader/;

@EXPORT_OK = (@feedback);

%EXPORT_TAGS = ( 'feedback' =>\@feedback, );

Exporter::export_tags(qw/feedback/);

=head1 METHODS

=head2 Accessor Methods

=head2 General Methods

=over 4

=item B<sideBar>

  sideBar();

=cut

sub sideBar {
  my $self = shift;
  my $cgi = shift;

  print "This is a sidebar.\n";
  return;
}

=item B<ompHeader>

  ompHeader();

=cut

sub ompHeader {
  my $self = shift;
  my $cgi = shift;
  # throw an error here if it isn't a cgi object.

  $cgi->header();
  return;
}

=back

=cut

1;



