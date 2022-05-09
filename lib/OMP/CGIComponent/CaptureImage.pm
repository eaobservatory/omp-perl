package OMP::CGIComponent::CaptureImage;

=head1 NAME

OMP::CGIComponent::CaptureImage - Routine for capturing images

=cut

use strict;

use CGI::Carp qw/set_message/;
use MIME::Base64 qw/encode_base64/;
use POSIX qw/WNOHANG/;

use base qw/OMP::CGIComponent/;

=head1 METHODS

=over 4

=item $comp->capture_png_as_data(sub {...})

Runs the given subroutine, which is expected to produce a PNG image
on its standard output.  Then returns the image as a data URI.

=cut

sub capture_png_as_data {
    my $self = shift;
    my $code = shift;

    # Note: the original implementation of this routine was to use the
    # Capture::Tiny module to capture the output, but some of the output from
    # PGPLOT would escape and end up in the caller's standard output stream.
    # This appears to be a similar issue to that described here:
    #     https://github.com/dagolden/Capture-Tiny/issues/10
    # So this implementation is based on the suggested solution to
    # that issue.  (Which unfortunately no longer uses Capture::Tiny.)

    my $pid = open FH, '-|';
    die 'Can\'t fork' unless defined $pid;

    unless ($pid) {
        # Prevent CGI::Carp wrapping error messages with a header and footer.
        set_message(sub {print shift;});

        # Call the routine to produce the image.
        $code->();
        exit 0;
    }

    my $png = '';
    my $buffer;
    my $exitcode = 0;

    # Read the child process's output until it exits and grab its exit
    # code if we see a valid value in $?.  This is to prevent the
    # child process hanging due to its output buffer filling up.
    while (waitpid($pid, WNOHANG) != -1) {
        $exitcode = $? unless $? == -1;
        read FH, $buffer, 1024;
        $png .= $buffer;
    };

    # Read any remaining output.
    while (read FH, $buffer, 1024) {
        $png .= $buffer;
    }

    close FH;

    # If the child process exited with bad status, check whether it looks
    # like it started to output a PNG or not.  If not, assume it gave
    # diagnostic text and try to show it, but be sure to remove any
    # unexpected characters in case what we have isn't all text!
    if ($exitcode) {
        if ($png !~ /^\x89PNG/) {
            my @output = ();

            foreach my $line (split "\n", $png) {
                next unless $line && $line !~ /^Content-type/;
                $line =~ s/[^-_ 0-9a-zA-Z.:!?\/]/#/g;
                push @output, $line;
            }

            die 'Error creating image: ' . join ' ', @output;
        }
        else {
            die 'Error after start of image';
        }
    }

    # At this point we should have a valid PNG image -- base64
    # encode it to create the data URI.
    return 'data:image/png;base64,' . encode_base64($png, '');
}

1;

__END__

=back

=head1 COPYRIGHT

Copyright (C) 2015 East Asian Observatory.
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
