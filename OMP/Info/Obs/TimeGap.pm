package OMP::Info::Obs::TimeGap;

=head1 NAME

OMP::Info::Obs::TimeGap - Observation sequence timegap information

=head1 SYNOPSIS

use OMP::Info::Obs::TimeGap;

$timegap = new OMP::Info::Obs::TimeGap( %hash );

@comments = $timegap->comments;

%nightlog = $timegap->nightlog;

=head1 DESCRIPTION

A way of handling information associated with a time gap between
observations. It includes possible comments and information on the
cause of the time gap.

This class is a subclass of C<OMP::Info::Obs>.

=cut

use 5.006;
use strict;
use Carp;

use OMP::Constants;

use base qw/ OMP::Info::Obs /;

our $VERSION = (qw$Revision$)[1];

=head1 METHODS

=head2 Accessors

=over 4

=item B<projectid>

Retrieve the project ID.

  $id = $timegap->projectid;

The project ID for C<OMP::Info::Obs::TimeGap> objects will always
be TIMEGAP.

=cut

sub projectid {
  return 'TIMEGAP';
}

=item B<status>

Retrieve or store the status of the timegap.

  $status = $timegap->status;
  $timegap->status( $status );

See C<Obs::Constants> for the valid statuses. I

=cut

sub status {
  my $self = shift;
  if( @_ ) {
    my $status = shift;
    $self->{status} = $status;

    my @comments = $self->comments;
    if( defined( $comments[0] ) ) {
      $comments[0]->status( $status );
      $self->comments( \@comments );
    }
  }

  if( !exists( $self->{status} ) ) {
    my @comments = $self->comments;
    if( defined( $comments[0] ) ) {
      $self->{status} = $comments[0]->status;
    } else {
      $self->{status} = OMP__TIMEGAP_UNKNOWN;
    }
  }

  return $self->{status};
}

=back

=head2 General Methods

=over 4

=item B<nightlog>

Returns a hash containing two strings used to summarize an
C<Obs::TimeGap> object.

  %nightlog = $timegap->nightlog;

The hash contains {_STRING => string} and {_STRING_LONG} key-value
pairs that give a summary of the time gap, including any comments
that may be associated with that time gap.

=cut

sub nightlog {
  my $self = shift;

  my %return;

  $return{'_STRING'} = $return{'_STRING_LONG'} = "Time gap: ";

  if( $self->status == OMP__TIMEGAP_INSTRUMENT ) {
    $return{'_STRING'} = $return{'_STRING_LONG'} .= "INSTRUMENT";
  } elsif( $self->status == OMP__TIMEGAP_WEATHER ) {
    $return{'_STRING'} = $return{'_STRING_LONG'} .= "WEATHER";
  } elsif( $self->status == OMP__TIMEGAP_FAULT ) {
    $return{'_STRING'} = $return{'_STRING_LONG'} .= "FAULT";
  } else {
    $return{'_STRING'} = $return{'_STRING_LONG'} .= "UNKNOWN";
  }

  foreach my $comment ($self->comments) {
    if(defined($comment)) {
      if( exists( $return{'_STRING'} ) ) {
        $return{'_STRING'} .= sprintf("\n %19s UT / %s: %-50s",
                                      $comment->date->ymd . ' ' . $comment->date->hms,
                                      $comment->author->name,
                                      $comment->text
                                     );
      }
      if( exists( $return{'_STRING_LONG'} ) ) {
        $return{'_STRING_LONG'} .= sprintf("\n %19s UT / %s: %-50s",
                                           $comment->date->ymd . ' ' . $comment->date->hms,
                                           $comment->author->name,
                                           $comment->text
                                          );
      }
    }
  }

  return %return;

}

=back

=head1 SEE ALSO

L<OMP::Info::Obs>

=head1 AUTHORS

Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
