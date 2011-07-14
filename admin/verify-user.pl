#!/local/perl/bin/perl

use warnings;
use strict;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
$Data::Dumper::Indent = 1;
$Data::Dumper::Deepcopy = 1;

use OMP::UserServer;

my @file = @ARGV;

for my $file ( @file ) {

  print "Processing $file ... \n";
  my @user = parse_file( $file );

  next unless scalar @user;

  for my $user ( @user ) {

    my $name = $user->{'name'};

    print "  Verifying existance of $name\n";

    my @exist = verify( map { $user->{ $_ } } qw[ name userid email ] );

    unless ( scalar @exist ) {

      print "    O K to add\n", Dumper( \@exist );
      next;
    }

    print Dumper( [ '    already E X I S T S',  $user ] );
  }
}

exit;

sub verify {

  my ( $name, $id, $email ) = @_;

  return
    OMP::UserServer
    ->getUserExpensive( 'name' => $name,
                         'email' => $email,
                          map { $_ => $id } qw[ userid alias cadcuser ]
                        ) ;
}

sub parse_file {
  my ( $file ) = @_;

  my $fh;
  if ( $file eq '-' ) {

    open $fh, '<-' or die "Cannot open '$file' to read: $!\n";
  }
  else {

    open $fh, '<', $file or die "Cannot open '$file' to read: $!\n";
  }

  my @user;

  while ( my $line = <$fh> ) {

    next
      if $line =~ /^\s*#/
      or $line =~ /^\s*$/;

    for ( $line ) {

      s/\#.*$//;
      s/^\s+//;
      s/\s+$//;
    }

    next unless $line;

    push @user, parse_line( $line );
  }

  close $fh or die "Cannot close '$file': $!\n";

  return @user;
}

sub parse_line {

  my ( $line ) = @_;

  my ( $id, $name, $email );
  my @in = split /\s*,\s*/, $line;

  if ( scalar @in == 3 ) {

    ( $id, $name, $email ) = @in;
  }
  elsif ( scalar @in == 2 ) {

    ( $name, $email ) = @in;
  }
  else {

    $name = $in[0];
  }

  for ( $id, $name ) {

    next unless defined;
    s/^\s+//;
    s/\s+$//;
  }

  $id = OMP::User->infer_userid( $name )
    unless defined $id
        && length $id;

  printf "id for '%s' is '%s'\n", $name, $id;

  if ( defined $email ) {

    $email =~ s/\s+//g;
    $email = undef unless $email =~ /\@/;
  }

  return
    { 'name'   => $name,
      'userid' => $id,
      'email'  => $email
    };
}

