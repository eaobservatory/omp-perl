#!/local/perl/bin/perl

=head1 NAME

installcgi - install OMP web software

=head1 SYNOPSIS

installcgi

=head1 DESCRIPTION

This program installs cgi scripts, as well as general web support files.

=cut

use warnings;
use strict;

use FindBin;
use File::Copy;
use File::Spec;
use Getopt::Long;

use constant OMPLIB => "$FindBin::RealBin/../lib";
use lib OMPLIB;

use OMP::Config;
use OMP::Error qw[ :try ];

my $dry_run = undef;
my $status = GetOptions("dry-run" => \$dry_run);

my $config = OMP::Config->new;

my $pubdest = $config->getData('web-install.public');
my $privdest = $config->getData('web-install.private');

my @srcdirs = qw/ cgi server web /;

my @pubfiles = qw/ faultrss.pl faultsum.pl fbcomment.pl fbfault.pl fblogout.pl
                   fbmsb.pl fbobscomment.pl fbshiftlog.pl fbsummary.pl fbworf.pl
                   fbworfthumb.pl feedback.pl filefault.pl
                   findtarget.pl
                   get_resource.pl
                   index.html issuepwd.pl
                   listprojects.pl msbhist.pl nightrep.pl obslog_text.pl
                   ompusers.pl
                   projecthome.pl projusers.pl props.pl
                   qstatus.pl queryfault.pl shiftlog.pl
                   sourceplot.pl spregion.pl
                   spsrv.pl staffobscomment.pl staffworf.pl staffworfthumb.pl
                   updatefault.pl updateresp.pl update_user.pl userdetails.pl
                   utprojlog.pl
                   viewfault.pl worf.pl worf_file.pl worf_fits.pl worf_graphic.pl
                   worf_image.pl worf_ndf.pl worf_thumb.pl wwwobserved.pl /;

# Files to be installed in both public and private roots
my @sharedfiles = qw/ omp-cgi-init.pl omp-srv-init.pl omp.css omp.js LookAndFeelConfig robots.txt /;

my %pub = map {$_, undef} @pubfiles;
my %shared = map {$_, undef} @sharedfiles;

for my $subdir (@srcdirs) {
  my $dir = File::Spec->catdir(OMPLIB, File::Spec->updir(), $subdir);
  opendir(DIR, $dir) or die "Could not open directory $dir: $!\n";
  my @files = grep {/(\.js|\.css|Feel|Config|\.html|\.pl|\.txt)$/} readdir(DIR);
  closedir(DIR);

  for my $file (@files) {
    my $srcfile = File::Spec->catfile($dir, $file);
    my $dest;
    my @paths;
    if (exists $pub{$file}) {
      push @paths, [$pubdest];
    } elsif (exists $shared{$file}) {
      push @paths, [$pubdest];
      push @paths, [$privdest];

    } else {
      push @paths, [$privdest];
    }

    for my $path (@paths) {
      push(@$path, 'cgi-bin') if ($file =~ /.pl$/);
      $dest = File::Spec->catfile(@$path, $file);
      print "Copying $srcfile to $dest\n";
      unless ($dry_run) {
        copy($srcfile, $dest) or
          warn "Error copying file $srcfile to $dest: $!";
      }
    }
  }
}

__END__

=head1 AUTHOR

Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2005 Particle Physics and Astronomy Research Council.
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
