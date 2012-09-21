package OMP::CGIDBHelper;

=head1 NAME

OMP::CGIComponent - Helper DB subroutines for building CGI pages

=head1 SYNOPSIS

  use OMP::CGIDBHelper;

  my $sp = OMP::CGIDBHelper::safeFetchSciProg( $projectid, $password );
  my $details = OMP::CGIDBHelper::safeProgramDetails( $projectid,
                   $password, $mode );

=head1 DESCRIPTION

Provides helper subroutines that have been factored out from the
specific CGIPage and CGIComponent classes relating to database access.

Not included in C<CGIComponent::Helper> since the dependencies are more
extreme for this module.

=cut

use 5.006;
use strict;
use warnings;
use OMP::Error qw/ :try /;

use OMP::MSBDB;

=head1 SUBROUTINES

=over 4

=item B<safeFetchSciProg>

Retrieves the specified science program from the database without leaving
a feedback entry. Handles exceptions and prints HTML to stdout when reporting
errors.

  $sp = safeFetchSciProg( $projectid, $password );

$sp will be undef if an error occurred.

=cut

sub safeFetchSciProg {
  my $projectid = uc(shift);
  my $password = shift;

  my $sp;
  try {

    # Use the lower-level method to fetch the science program so we
    # can disable the feedback comment associated with this action
    my $db = new OMP::MSBDB( Password => $password,
			     ProjectID => $projectid,
			     DB => new OMP::DBbackend, );
    $sp = $db->fetchSciProg(1);
  } catch OMP::Error::UnknownProject with {
    print "<p>Science program for <em>$projectid</em> not present in database<p>";
  } catch OMP::Error::SpTruncated with {
    print "<p>Science program for <em>$projectid</em> is in the database but has been truncated. Please report this problem.<p>";
  } otherwise {
    my $E = shift;
    print "<p>Error obtaining science program details for project <em>$projectid</em> <p><pre>$E</pre><p>";
  };

  return $sp;
}

=item B<safeProgramDetails>

Similar to the OMP::SpServer->programDetails method, except exceptions are
caught and errors written to stdout in HTML.

  $details = safeProgramDetails( $projectid, $password, $type );

Returns undef on error. An optional 4th argument can be used to suppress
the error messages to stdout if true.

  $details = safeProgramDetails( $projectid, $password, $type, 1 );

=cut

sub safeProgramDetails {
  my $projectid = uc(shift);
  my $password = shift;
  my $type = shift;
  my $quiet = shift;

  my $msbsum;
  try {
    $msbsum = OMP::SpServer->programDetails($projectid,
					    $password,
					    $type);
  } catch OMP::Error::UnknownProject with {
    print "<p>Science program for <em>$projectid</em> not present in database<p>"
      unless $quiet;
  } catch OMP::Error::SpTruncated with {
    print "<p>Science program for <em>$projectid</em> is in the database but has been truncated. Please report this problem.<p>"
      unless $quiet;
  } otherwise {
    my $E = shift;
    print "<p>Error obtaining science program details for project <em>$projectid</em> <p><pre>$E</pre><p>"
      unless $quiet;
  };

  return $msbsum;
}

=back

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2004 Particle Physics and Astronomy Research Council.
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
along with this program; if not, write to the
Free Software Foundation, Inc., 59 Temple Place, Suite 330,
Boston, MA  02111-1307  USA

=cut

1;
