#!/local/perl/bin/perl

=head1 NAME

remsciprog - Remove a science program from the database

=head1 SYNOPSIS

  remsciprog

=head1 DESCRIPTION

Remove the science program associated with the supplied project ID
from the database.

This program is intentionally interactive in order to prevent this
from happening without thinking very hard.


=head1 ARGUMENTS

The following arguments are supported:

=over 4

=item B<-help>

A help message.

=item B<-man>

This manual page.

=back

=cut



use warnings;
use strict;

use Pod::Usage;
use Getopt::Long;
use Term::ReadLine;

# This does not use a SOAP server since we want to be local
# Does mean we need to connect to the database though
use OMP::MSBDB;
use OMP::DBbackend;


# Options
my ($help, $man);
my $status = GetOptions("help" => \$help,
                        "man" => \$man,
                       );

pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;


# Ask for the project id
my $term = new Term::ReadLine 'Rem Sci Prog';
my $project = $term->readline( "Project ID of science program to delete: ");

# Needs Term::ReadLine::Gnu
my $attribs = $term->Attribs;
$attribs->{redisplay_function} = $attribs->{shadow_redisplay};
my $password = $term->readline( "Password [project or admin]: ");
$attribs->{redisplay_function} = $attribs->{rl_redisplay};

# Create the new object
my $db = new OMP::MSBDB( 
			Password => $password,
			ProjectID => $project,
			DB => new OMP::DBbackend,
		       );

# First list a summary of the project by retrieving the science
# program (disabling feedback notification)
my $sp = $db->fetchSciProg(1);

print join("\n",$sp->summary),"\n";

my $confirm = $term->readline("Confirm removal? [y/n] ");

if ($confirm =~ /^[yY]/) {
  $db->removeSciProg();
} else {
  print "Removal aborted\n";
}


exit;

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut
