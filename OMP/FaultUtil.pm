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
  if ($printer =~ /^(\w+)$/) {
    $printer = $1;
  }

  # If we're printing multiple faults, combine them and send it off as a
  # single print job
  if ($faultids[1]) {
    my $toprint;

    for (@faultids) {
      # Get the fault
      my $f = OMP::FaultServer->getFault($_);

      # Get the subject
      my $subject = $f->subject;

      # Get the raw fault text
      my $text = OMP::FaultUtil->format_fault($f, 1);

      # Convert it to plaintext
      my $plaintext = OMP::Display->html2plain($text);

      $toprint .= "Subject: $subject\n\n$plaintext\f";
    }

    # Set up printer. Should check that enscript can be found.
    my $printcom =  "/usr/bin/enscript -G -fCourier10 -b\"Faults\" -P$printer";
    open(my $PRTHNDL, "| $printcom");
    print $PRTHNDL $toprint;

    close($PRTHNDL);

  } else {
    # Get the fault
    my $f = OMP::FaultServer->getFault($faultids[0]);

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

=item B<compare>

Compare two C<OMP::Fault> or C<OMP::Fault::Response> objects.

  @diff = OMP::FaultUtil->compare($fault_a, $fault_b);

Takes two C<OMP::Fault> or C<OMP::Fault::Response> objects as the only arguments.
Returns a list containing the elements where the two objects differed.  The elements
are conveniently named after the accessor methods of each object type.  Some keys
are not included in the comparison.  For C<OMP::Response> objects only the text and author keys
are compared.  For C<OMP::Fault> objects the faultid keys are not compared.

=cut

sub compare {
  my $self = shift;
  my $obja = shift;
  my $objb = shift;

  my @diff;
  my @comparekeys;

  if (UNIVERSAL::isa($obja, "OMP::Fault") and UNIVERSAL::isa($objb, "OMP::Fault")) {

    # Comparing OMP::Fault objects
    @comparekeys = qw/subject system type timelost faultdate urgency projects/;

  } elsif (UNIVERSAL::isa($obja, "OMP::Fault::Response") and UNIVERSAL::isa($objb, "OMP::Fault::Response")) {

    # Comparing OMP::Fault::Response objects
    @comparekeys = qw/text author/;

  } else {
    throw OMP::Error::BadArgs("Both Arguments to compare must be of the same object type (that of either OMP::Fault or OMP::Fault::Response)\n");
    return;
  }

  for (@comparekeys) {
    my $keya;
    my $keyb;

    # Be more specific about what we want to compare in some cases
    if ($_ =~ /author/) {
      $keya = $obja->author->userid;
      $keyb = $objb->author->userid;
    } elsif ($_ =~ /projects/) {
      $keya = @{$obja->projects};
      $keyb = @{$objb->projects};
    } elsif ($_ =~ /faultdate/) {
      if ($obja->faultdate and $objb->faultdate) {
	$keya = $obja->faultdate->strftime("%Y%m%d%T");
	$keyb = $objb->faultdate->strftime("%Y%m%d%T");
      } else {
	next;
      }
    } else {
      $keya = $obja->$_;
      $keyb = $objb->$_;
    }

    next if (! $keya and ! $keyb);

    if (! defined $keya and defined $keyb) {
      push @diff, $_;
    } elsif (! defined $keyb and defined $keya) {
      push @diff, $_;
    } elsif ($keya ne $keyb) {
      push @diff, $_;
    }
  }

  return @diff;
}

=item B<getResponse>

Return the response object with the given response ID.

  $resp = OMP::FaultUtil->getResponse($respid, $fault);

where C<$respid> is the ID of the response to be returned and C<$fault>
is an object of type C<OMP::Fault>.

=cut

sub getResponse {
  my $self = shift;
  my $respid = shift;
  my $fault = shift;

  if (UNIVERSAL::isa($fault, "OMP::Fault")) {
    for (@{$fault->responses}) {
      ($_->id eq $respid) and return $_;
    }
  } else {
    throw OMP::Error::BadArgs("Argument to getResponse must be an object of the type OMP::Fault\n");
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
