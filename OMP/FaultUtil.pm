package OMP::FaultUtil;

=head1 NAME

OMP::FaultUtil - Fault content manipulation

=head1 SYNOPSIS

  use OMP::FaultUtil;

  $text = OMP::FaultUtil->format_fault($fault, $bottompost);

=head1 DESCRIPTION

This class provides general functions for manipulating the components
of C<OMP::Fault> and C<OMP::Fault::Response> objects (and sometimes components
that are not necessarily part of an object yet) for display purposes or for preparation for storage to the database or to an object.

=cut

use 5.006;
use warnings;
use strict;
use Carp;

use Text::Wrap;

use OMP::Config;

=head1 METHODS

=head2 General Methods

=over 4

=item <format_fault>

Format a fault in such a way that it is readable in a mail viewer.  This
method retains the HTML in fault responses and uses HTML for formatting.

  $text = OMP::Fault::Util->format_fault($fault, $bottompost);

The first argument should be an C<OMP::Fault> object.  If the second argument
is true then responses are displayed in ascending order (newer responses appear
at the bottom).

=cut

sub format_fault {
  my $self = shift;
  my $fault = shift;
  my $bottompost = shift;

  my $faultid = $fault->id;

  # Get the fault system URL
  my $baseurl = OMP::Config->getData('omp-url') . OMP::Config->getData('cgidir');

  # Get the fault response(s)
  my @responses = $fault->responses;

  # Store fault meta info to strings
  my $system = $fault->systemText;
  my $type = $fault->typeText;
  my $loss = $fault->timelost;
  my $category = $fault->category;

  # Don't show the status if there is only the initial filing and it is 'Open'
  my $status = "<b>Status:</b> " . $fault->statusText
    unless (!$responses[1] and $fault->statusText eq /open/i);

  my $faultdatetext = "hrs at ". $fault->faultdate . " UT"
    if $fault->faultdate;

  my $faultauthor = $fault->author->html;

  # Create the fault meta info portion of our message
  my $meta =
"<pre>".
sprintf("%-58s %s","<b>System:</b> $system","<b>Fault type:</b> $type<br>").
sprintf("%-58s %s","<b>Time lost:</b> $loss" . "$faultdatetext","$status ").
"</pre><br>";

  my @faulttext;

  # Create the fault text

  if ($responses[1]) {
    my %authors;

    # Make it noticeable if this fault is urgent
    push(@faulttext, "<div align=center><b>* * * * * URGENT * * * * *</b></div><br>")
      if $fault->isUrgent;

    # If we aren't bottom posting arrange the responses in descending order
    my @order;
    ($bottompost) and @order = @responses or
      @order = reverse @responses;

    for (@order) {
      my $user = $_->author;
      my $author = $user->html; # This is an html mailto
      my $date = $_->date->ymd . " " . $_->date->hms;
      my $text = $_->text;

      # Wrap the message text
      $text = wrap('', '', $text);

      # Now turn fault IDs into links
      $text =~ s!([21][90][90]\d[01]\d[0-3]\d\.\d{3})!<a href='$baseurl/viewfault.pl?id=$1'>$1</a>!g;

      if ($_->isfault) {
	 push(@faulttext, "$category fault filed by $author on $date<br><br>");

	 # The meta data should appear right after the initial filing unless
	 # we are bottom posting in which case it appears right before
	 if (!$bottompost) {
	   push(@faulttext, "<br>$text<br>~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~<br>$meta");
	 } else {
	   push(@faulttext, "$meta~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~<br>$text<br>--------------------------------------------------------------------------------<br>");
	 }

       } else {
	 push(@faulttext, "Response filed by $author on $date<br><br>$text<br>");
	 push(@faulttext, "--------------------------------------------------------------------------------<br>");
       }
    }

  } else {

    # This is an initial filing so arrange the message with the meta info first
    # followed by the initial report
    my $author = $responses[0]->author->html; # This is an html mailto
    my $date = $responses[0]->date->ymd . " " . $responses[0]->date->hms;
    my $text = $responses[0]->text;

    # Wrap the message text
    $text = wrap('', '', $text);

    # Now turn fault IDs into links
    $text =~ s!([21][90][90]\d[01]\d[0-3]\d\.\d{3})!<a href='$baseurl/viewfault.pl?id=$1'>$1</a>!g;

    push(@faulttext, "$category fault filed by $author on $date<br><br>");

    # Make it noticeable if this fault is urgent
    push(@faulttext, "<div align=center><b>* * * * * URGENT * * * * *</b></div><br>")
      if $fault->isUrgent;
    push(@faulttext, "$meta~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~<br>$text<br><br>");
  }

  # Set link to response page
  my $url = ($category eq "BUG" ?
	     "http://omp-dev.jach.hawaii.edu/cgi-bin/viewreport.pl?id=$faultid" :
	     "$baseurl/viewfault.pl?id=$faultid");

  my $responselink = "<a href='$url'>here</a>";

  # Add the response link to the bottom of our message
  push(@faulttext, "--------------------------------<br>To respond to this fault go $responselink<br><br>$url");

  return join('',@faulttext);
}

=item B<print_faults>

Print faults using enscript

  print_faults($printer, @faultids);

=cut

sub print_faults {
  my $self = shift;
  my $printer = shift;
  my @faultids = @_;

  # Untaint the printer param
  ($printer =~ /(^\w+$)/) and $printer = $1;

  for (@faultids) {
    # Get the fault
    my $f = OMP::FaultServer->getFault($_);

    my $faultid = $f->id;

    # Get the subject
    my $subject = $f->subject;

    # Get the raw fault text
    my $text = OMP::FaultUtil->format_fault($f, 1);

    # Convert it to plaintext
    my $plaintext = OMP::Display->html2plain($text);

    # Set up printer. Should check that enscript can be found.
    my $printcom =  "/usr/bin/enscript -G -fCourier10 -b\"[$faultid] $subject\" -P$printer";
    open(my $PRTHNDL, "| $printcom");
    print $PRTHNDL $plaintext;

    close($PRTHNDL);
  }
}

=back

=head1 AUTHORS

Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
