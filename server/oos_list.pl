#!/local/perl-5.6/bin/perl

=head1 NAME

oos_list - DRAMA task to store current active sequencers

=head1 SYNOPSIS

  ditscmd OOS_LIST ADDOOS OOS_UFTI

=head1 DESCRIPTION

This is a DRAMA task used to keep track of the current sequencer
tasks that are active on the machine. The list of sequencers is
stored in a parameter that can be monitored by sequence consoles
to enable them to easily reconfigure themselves when new
sequencers appear.

The assumption is that an action in this task is invoked whenever
the loadORAC script is used to launch a new sequencer.

=head1 PARAMETERS

The following DRAMA parameters are accessible:

=over 4

=item OOSLIST

A string array. Each element contains the name of an sequencer
that is running.

=back

=item ACTIONS

The following DRAMA actions are supported:

=over 4

=item EXIT

Cause the task to exit.

=item ADDOOS

Explicitly add a sequencer to the list of running sequncers.

=item REMOOS

Explicitly removes a sequencer from the list of running sequencers.
No action if the sequencer is not in the list.

=item LISTOOS

List the contents of the array via MsgOut.

=back

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>.

=head1 COPYRIGHT

Copyright (C) 2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=head1 CHANGES

 $Log$
 Revision 1.1  2002/02/08 02:18:41  timj
 First version


=cut


use strict;
use warnings;

use DRAMA;
use Sdp;
use Sds;

# Init drama
DPerlInit("OOS_LIST");

# Initiate actions
my $status = new DRAMA::Status;
Dits::DperlPutActions("ADDOOS",\&add_oos,undef,0,undef,$status);
Dits::DperlPutActions("REMOOS",\&rem_oos,undef,0,undef,$status);
Dits::DperlPutActions("LISTOOS",\&list_oos,undef,0,undef,$status);



# Create the parameters.
# Dimensions of Sds array
my $NCHARS = 16;
my $NOOSES = 10;  # no more than 10 sequencers at once
my $ooslist = new OOS_LIST( $NCHARS, $NOOSES );

# And start the parameter system
my $sdp = new Sdp;
$sdp->Create($ooslist->sds->Name($status), "SDS", $ooslist->sds);

# Then enter the main loop
Dits::MainLoop( $status );


# Actions
# Argument is Argument1 (ie from ditscmd)

sub add_oos {
  my $status = shift;

  my $arg = Dits::GetArgument;

  my $item = $arg->GetString("Argument1", $status);

  # Add it to the sds
  my $changed = $ooslist->add( $item, $status);

  # Mark the parameter system with an update
  $sdp->Update( $ooslist->sds, $status)
    if $changed;

}

sub rem_oos {
  my $status = shift;

  my $arg = Dits::GetArgument;

  my $item = $arg->GetString("Argument1", $status);

  # Add it to the sds
  my $changed = $ooslist->rem( $item, $status);

  # Mark the parameter system with an update
  $sdp->Update( $ooslist->sds, $status)
    if $changed;

}


sub list_oos {
  my $status = shift;

  my @list = $ooslist->get_array( $status );

  for (@list) {
    DRAMA::MsgOut($status, $_);
  }
}

exit;


package OOS_LIST;

# Class to manipulate the Sds structure

# Constructor:
#  Args:  Dim1, Dim2  (dimensions of string array)
# Returns: Object

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;

  # Read the arguments
  my @dims = @_;

  # Have to do it as an SDS structure first.
  my $ooslist = Sds->Create( "OOSLIST", undef, Sds::CHAR, 
			     \@dims, $status);

  # Fill it with empties
  $ooslist->PutStringArrayExists([''], $status);

  # Simply bless the sds object into an array
  bless [ $ooslist ], $class;
}


# Accessor methods

# sds
#  Returns the sds object

sub sds {
  my $self = shift;
  if (@_) { $self->[0] = shift; }
  return $self->[0];
}


# Add a new element onto the array if it is not there
# already.
#    $list->add( $element, $status );

# Returns 1 if the array was modified, false otherwise

sub add {
  my $self = shift;
  my $el  = shift;
  my $status = shift;

  # Retrieve the current contents
  my @list = $self->get_array( $status );

  # Add the new element (if it isn't there)
  # Look for it
  my $found = grep { $_ eq $el } @list;

  # Do nothing if it's there already
  my $changed;
  unless ($found) {

    push(@list, $el);

    use Data::Dumper;
    print Dumper(\@list);

    # Store the array
    $self->store_array( \@list, $status);

    $changed = 1;
  }

  return $changed;
}


# Remove element from array if it is there

#  $list->rem( $el, $status );

# Returns 1 if the array was modified, false otherwise

sub rem {
  my $self = shift;
  my $el = shift;
  my $status = shift;

  # Retrieve the current contents
  my @list = $self->get_array( $status );

  # Find the position of the element in the array
  # There can be only one that matches since we
  # dont store repeats.
  my $found;
  for my $i ( 0.. $#list) {
    if ($el eq $list[$i]) {
      $found = $i;
      last;
    }
  }

  # Now remove it if we can find it
  my $changed;
  if (defined $found) {

    splice(@list, $found, 1);


    # And store the modified array
    $self->store_array(\@list, $status);

    $changed = 1;

  }

  return $changed;
}



# retrieve the string array from the sds structure
# Strips empty elements and trailing space
# @contents = $list->get_array( $status );

sub get_array {
  my $self = shift;
  my $status = shift;
  my $sds = $self->sds;

  # Retrieve the current contents
  my @list = $sds->GetStringArray( $status );

  # Strip empty elements 
  # and trailing space
  @list =  grep !/^\s+$/, @list;
  for (@list) {
    s/\s+$//;
  }
  return @list;
}

# Store the supplied array into the Sds structure
# essentially a thin layer about PutStringArrayExist
#  $list->store_array( \@array, $status );

sub store_array {
  my $self = shift;
  my $arr = shift;
  my $status = shift;

  my $sds = $self->sds;

  # Store the array
  $sds->PutStringArrayExists( $arr, $status);

}
