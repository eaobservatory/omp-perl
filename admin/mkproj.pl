#!/local/perl/bin/perl

=head1 NAME

mkproj - Populate project database with initial details

=head1 SYNOPSIS

  mkproj defines.ini
  mkproj -force defines.ini

=head1 DESCRIPTION

This program reads in a file containing the project information,
and adds the details to the OMP database. By default projects
that already exist in the database are ignored although this
behaviour can be over-ridden. See L<"FORMAT"> for details on the
file format.

=head1 ARGUMENTS

The following arguments are allowed:

=over 4

=item B<defines>

The project definitions file name. See L<"FORMAT"> for details on the
file format.

=back

=head1 OPTIONS

See also B<info> blurb elsewhere in relation to I<country>,
I<priority>, I<semester>, I<telescope> options.

The following options are supported:

=over 4

=item B<-force>

By default projects that already exist in the database are not
overwritten. With the C<-force> option project details in the file
always override those already in the database. Use this option
with care.

=item B<-version>

Report the version number.

=item B<-help>

A help message.

=item B<-man>

This manual page.

=item B<-country> "country" code

Specify default country code to use for a project missing one.

=item B<-priority> integer

Specify default tag priority to use.

=item B<-semester> semester

Specify default semester to use.

=item B<-telescope> UKIRT | JCMT

Specify default telescope.

=back

=cut

# Uses the infrastructure classes so each project is inserted
# independently rather than as a single transaction

use warnings;
use strict;

use OMP::Error qw/ :try /;
use Config::IniFiles;
use OMP::DBServer;
use OMP::ProjDB;
use OMP::ProjServer;
use OMP::SiteQuality;
use OMP::Password;
use OMP::UserServer;
use Pod::Usage;
use Getopt::Long;

# Options
my ($help, $man, $version,$force, %defaults );
my $status = GetOptions("help" => \$help,
                        "man" => \$man,
                        "version" => \$version,
                        "force" => \$force,

                        "country=s"   => \$defaults{'country'},
                        "priority=i"  => \$defaults{'priority'},
                        "semester=s"  => \$defaults{'semester'},
                        "telescope=s" => \$defaults{'telescope'},
                       );

pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

if ($version) {
  my $id = '$Id: mkproj.pl 16396 2009-01-23 02:50:27Z agarwal $ ';
  print "mkproj - upload project details from file\n";
  print " CVS revision: $id\n";
  exit;
}

# Read the file
my $file = shift(@ARGV);
my %alloc;
tie %alloc, 'Config::IniFiles', ( -file => $file );

# Get the defaults (if specified)
%defaults = ( %defaults, %{ $alloc{info} } )
  if $alloc{info};

# Get the support information
my %support;
%support = %{ $alloc{support} }
  if $alloc{support};

# oops
if (!keys %alloc) {
  for my $err (@Config::IniFiles::errors) {
    print "! $err\n";
  }
  die "Did not find any projects in input file!"
}

my $pass = OMP::Password->get_verified_password({
                'prompt' => 'Enter administrator password: ',
                'verify' => 'verify_administrator_password',
            }) ;

# Loop over each project and add it in
for my $proj (sort { uc $a cmp uc $b } keys %alloc) {
  next if $proj eq 'support';
  next if $proj eq 'info';

  reset_err();

  # Copy the data from the file and merge with the defaults
  my %details = ( %defaults, %{ $alloc{$proj} });

  for my $key ( keys %details ) {

    next unless defined $details{ $key };

    $details{ $key } =~ s/\s*#.*$//;
  }

  collect_err( "No country code given" )
   unless exists $details{'country'}
     and defined $details{'country'}
     and length  $details{'country'}
     ;

  # Upper case country for lookup table
  # and split on comma in case we have more than one
  $details{country} = [split /,/,uc($details{country}) ];
    #if exists $details{country};

  upcase( \%details, qw/ pi coi support semester telescope / );

  # Validate country (if we add a new country we should remove
  # this test for the first upload
  my $projdb = OMP::ProjDB->new( DB => OMP::DBServer->dbConnection );
  my %allowed = map { $_ => undef } $projdb->listCountries;
  for my $c (@{$details{country}}) {
    if (!exists $allowed{$c}) {
      collect_err( "Unrecognized country code: $c" );
    }
  }

  # TAG priority
  my @tag;
  @tag = split /,/, $details{tagpriority}
    if exists $details{tagpriority};

  collect_err( "Number of TAG priorities is neither 1 nor number of countries [$proj]" )
    unless ($#tag == 0 || $#tag == $#{$details{country}});
  $details{tagpriority} = \@tag if scalar(@tag) > 1;

  # TAG adjustment
  my @tagadj;
  if ($details{tagadjustment}) {
    @tagadj = split /,/, $details{tagadjustment};
    $details{tagadjustment} = \@tagadj if scalar(@tagadj) > 1;
  }

  # Deal with support issues
  # but do not overrride one if it is already set
  if (!defined $details{support}) {
    if (exists $support{$details{country}->[0]}) {
      $details{support} = $support{$details{country}->[0]};
    } else {
      collect_err( "Can not find support for country " . $details{country}->[0] );
    }
  }

  collect_err( "Must supply a telescope!!!" )
    unless exists $details{telescope};

  # Now weather bands
  my ($taumin, $taumax) = OMP::SiteQuality::default_range('TAU');
  if (exists $details{taurange}) {
    ($taumin, $taumax) = split_range( $details{taurange} );
  } elsif (exists $details{band}) {
    # Get the tau range from the weather bands if it exists
    my @bands = split_range( $details{band} );
    my $taurange = OMP::SiteQuality::get_tauband_range($details{telescope},
                                                       @bands);
    collect_err( "Error determining tau range from band '$details{band}' !" )
      unless defined $taurange;

    ($taumin, $taumax) = $taurange->minmax;

  }

  # And seeing
  my ($seemin, $seemax) = OMP::SiteQuality::default_range('SEEING');
  if (exists $details{seeing}) {
    ($seemin, $seemax) = split_range( $details{seeing} );
  }

  # cloud
  my ($cloudmin, $cloudmax) = OMP::SiteQuality::default_range('CLOUD');
  if (exists $details{cloud}) {
    # if we have no comma, assume this is a cloudmax and "upgrade" it
    if ($details{cloud} !~ /[-,]/) {
      my $r = OMP::SiteQuality::upgrade_cloud( $details{cloud} );
      ($cloudmin, $cloudmax) = $r->minmax;
    } else {
      ($cloudmin, $cloudmax) = split_range( $details{cloud} );
    }
  }

  # And sky brightness
  my ($skymin, $skymax) = OMP::SiteQuality::default_range('SKY');
  if (exists $details{sky}) {
    ($skymin, $skymax) = split_range( $details{sky} );
  }

  # Now convert the allocation to seconds instead of hours
  collect_err( "[project $proj] Allocation is mandatory!" )
    unless defined $details{allocation};
  collect_err( "[project $proj] Allocation must be positive!" )
    unless $details{allocation} >= 0;
  $details{allocation} *= 3600;

  # User ids
  if ( my @unknown = unverified_users( @details{qw/pi coi support/} ) ) {

    collect_err( 'Unverified user(s): ' . join ', ', @unknown );
  }

  print "Adding [$proj]\n";

  if ( any_err() ) {

    print " skipped due to ... \n", get_err();
    next;
  }

  # Now add the project
  try {
    OMP::ProjServer->addProject( $pass, $force,
                                $proj,  # project id
                                $details{pi},
                                $details{coi},
                                $details{support},
                                $details{title},
                                $details{tagpriority},
                                $details{country},
                                $details{tagadjustment},
                                $details{semester},
                                "xxxxxx", # default password
                                $details{allocation},
                                $details{telescope},
                                $taumin, $taumax,
                                $seemin,$seemax,
                                $cloudmin, $cloudmax,
                                $skymin, $skymax,
                               );

  } catch OMP::Error::ProjectExists with {
    print " - but the project already exists. Skipping.\n";

  };
}

# Given a a list of users (see "FORMAT" section of pod elsewhere) for a project,
# returns a list of unverified users. C<OMP::Error> exceptions are caught &
# saved for later display elsewhere.
#
# OMP::UserServer->addProject throws exceptions for each user one at a time.  So
# user id verification is also done for all the user ids related to a project in
# one go.
sub unverified_users {

  my ( @list ) = @_;

  # For reference, see C<OMP::ProjServer->addProject()>.
  my $id_sep = qr/[,:]+/;

  my @user;
  for my $user ( map {  $_ ? split /$id_sep/, $_ : () } @list ) {

    try {
      push @user, $user
        unless OMP::UserServer->verifyUser( $user );
    }
    catch OMP::Error with {

      my $E = shift;
      collect_err( "Error while checking user id [$user]: $E" );
    }
  }
  return sort { uc $a cmp uc $b } @user;
}

# Collect the errors for a project.
{
  my ( @err );

  # To reset the error string list, say, while looping over a list of projects.
  sub reset_err { undef @err ; return; }

  # Tell if any error strings have been saved yet.
  sub any_err { return scalar @err; }

  # Save errors.
  sub collect_err { push @err, @_; return; }

  # Returns a list of error strings with newlines at the end.  Optionally takes
  # a truth value to disable addition of a newline.
  sub get_err {

    my ( $no_newline ) = @_;

    return unless any_err() ;
    return
      map
        {
          my $nl =  $no_newline || $_ =~ m{\n\z}x ? '' : "\n";
          sprintf " - %s$nl", $_ ;
        }
        @err ;
  }
}

# Changes case of values (plain scalars or array references) to upper case in
# place, given a hash reference and a list of interesting keys.
sub upcase {

  my ( $hash, @key ) = @_;

  KEY:
  for my $k ( @key ) {

    next unless exists $hash->{ $k };

    for ( $hash->{ $k } ) {

      next KEY unless defined $_;

      # Only an array reference is expected.
      $_ = ref $_ ? [ map { uc $_ } @{ $_ } ] : uc $_;
    }
  }
  return;
}

sub split_range {

  my ( $in ) = @_;

  return
    unless defined $in
    && length $in;

  return split /[-,]/, $in;
}

=head1 FORMAT

The input project definitions file is in the C<.ini> file format
with the following layout. A header C<[info]> and C<[support]>
provide general defaults that should apply to all projects
in the file, with support indexed by country:


 [info]
 semester=02B
 telescope=JCMT

 [support]
 UK=IMC
 CN=GMS
 INT=GMS
 UH=GMS
 NL=RPT

Individual projects are specified in the following sections, indexed
by project ID. C<pi>, C<coi> and C<support> must be valid OMP User IDs
(comma-separated).

 [m01bu32]
 tagpriority=1
 country=UK
 pi=HOLLANDW
 coi=GREAVESJ,ZUCKERMANB
 title=The Vega phenomenom around nearby stars
 allocation=24
 band=1

 [m01bu44]
 tagpriority=2
 country=UK
 pi=RICHERJ
 coi=FULLERG,HATCHELLJ
 title=Completion of the SCUBA survey
 allocation=28
 band=1

Allocations are in hours and "band" is the weather band. C<taurange>
can be used directly (as a comma delimited range) if it is known.

Multiple countries can be specified (comma-separated). If there is
more than one TAG priority (comma-separated) then there must
be one priority for every country. SUPPORT lookups only used the
first country. The first country is the primary key.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2005 Particle Physics and Astronomy Research Council.
All Rights Reserved.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful,but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 59 Temple
Place,Suite 330, Boston, MA  02111-1307, USA

=cut



