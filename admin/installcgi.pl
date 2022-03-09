#!/local/perl/bin/perl

=head1 NAME

installcgi - install OMP web software

=head1 SYNOPSIS

    installcgi [--dry-run] [--images]

=head1 DESCRIPTION

This program installs cgi scripts, as well as general web support files.

It is controlled by the following configuration file options:

=over

=item web-install.public

Base directory for public web service.

=item web-install.private

Base directory for private web service.

=item web-install.omplib

(If set) the path to the OMP libraries, to be used to replace that in the
"init" files.

=item web-install.initpath

(If set) the path to the "init" files, for use with web servers which
do not change to a CGI script's directory before running it.

=back

=cut

use warnings;
use strict;

use FindBin;
use File::Copy qw/cp/;
use File::Path qw/make_path/;
use File::Spec;
use Getopt::Long;
use IO::File;

use constant OMPLIB => "$FindBin::RealBin/../lib";
use lib OMPLIB;

use OMP::Config;
use OMP::Error qw[ :try ];

my $dry_run = undef;
my $install_images = undef;
my $status = GetOptions(
    "dry-run" => \$dry_run,
    'images' => \$install_images,
);

my $config = OMP::Config->new;

my $pubdest = $config->getData('web-install.public');
my $privdest = $config->getData('web-install.private');
my $omplib = $config->getData('web-install.omplib');
my $initpath = $config->getData('web-install.initpath');

my @srcdirs = qw/ cgi server web /;
push @srcdirs, File::Spec->catdir(qw/web images/) if $install_images;

my @pubfiles = qw/ add_user.pl alterproj.pl edit_support.pl edsched.pl
                   faultrss.pl fbcomment.pl fbfault.pl fblogout.pl
                   fbmsb.pl fbobscomment.pl fbshiftlog.pl fbsummary.pl fbworf.pl
                   fbworfthumb.pl feedback.pl filefault.pl
                   findtarget.pl
                   get_resource.pl
                   index.pl
                   listprojects.pl login_hedwig.pl msbhist.pl nightrep.pl obslog_text.pl
                   ompusers.pl
                   projecthome.pl projusers.pl projsum.pl props.pl pubsched.pl
                   qstatus.pl queryfault.pl retrieve_data.pl
                   sched.pl schedcal.pl schedcallist.pl schedstat.pl shiftlog.pl
                   sourceplot.pl spregion.pl spsummary.pl
                   spsrv.pl staffobscomment.pl staffworf.pl staffworfthumb.pl
                   updatefault.pl updateresp.pl update_user.pl userdetails.pl
                   utprojlog.pl
                   viewfault.pl worf_fits.pl worf_graphic.pl
                   worf_image.pl worf_ndf.pl worf_thumb.pl wwwobserved.pl
                   sched_edit.js /;

# Files to be installed in both public and private roots
my @sharedfiles = qw/ omp-cgi-init.pl omp-srv-init.pl omp.css omp.js jquery.js LookAndFeelConfig robots.txt /;

# Files which are renamed.
my %renamed_files = (
    'index_private.html' => 'index.html',
);

# Files which are not installed.
my %no_install_files = map {$_ => undef} qw/
/;

my %pub = map {$_, undef} @pubfiles;
my %shared = map {$_, undef} @sharedfiles;
my %seen_dir = ();

for my $subdir (@srcdirs) {
  my $dir = File::Spec->catdir(OMPLIB, File::Spec->updir(), $subdir);
  opendir(DIR, $dir) or die "Could not open directory $dir: $!\n";
  my @files = grep {/(\.js|\.css|Feel|Config|\.html|\.pl|\.txt|\.png|\.gif|\.ico)$/} readdir(DIR);
  closedir(DIR);

  for my $file (@files) {
    next if exists $no_install_files{$file};
    my $srcfile = File::Spec->catfile($dir, $file);
    my $destfile = $renamed_files{$file} // $file;
    my @paths;
    if (exists $pub{$file}) {
      push @paths, [$pubdest];
    } elsif (exists $shared{$file} or $file =~ /(?:\.gif|\.png|\.ico)$/) {
      push @paths, [$pubdest];
      push @paths, [$privdest];

    } else {
      push @paths, [$privdest];
    }

    for my $path (@paths) {
      push(@$path, 'cgi-bin') if ($file =~ /\.pl$/);
      push(@$path, 'images') if ($file =~ /(?:\.gif|\.png|\.ico)$/);

      my $pathdir = File::Spec->catdir(@$path);
      if (not exists $seen_dir{$pathdir} and not -e $pathdir) {
        $seen_dir{$pathdir} = 1;
        print "Making directory $pathdir\n";
        unless ($dry_run) {
          make_path($pathdir);
        }
      };

      my $dest = File::Spec->catfile(@$path, $destfile);
      print "Copying $srcfile to $dest\n";
      unless ($dry_run) {
        if ($file =~ /\.pl$/ and ($initpath or $omplib)) {
          my $in = new IO::File($srcfile, 'r');
          unless ($in) {warn "Error opening file $srcfile for reading: $!"; next};
          my $out = new IO::File($dest, O_WRONLY|O_CREAT|O_TRUNC, ((-x $srcfile) ? 0775 : 0664));
          unless ($out) {warn "Error opening file $dest for writing: $!"; close $in; next};
          while (defined (my $line = <$in>)) {
            if ($initpath) {
              $line =~ s/(\$retval = do ")\.(\/omp-(?:cgi|srv)-init.pl";)/$1$initpath$2/;
            }
            if ($omplib) {
              $line =~ s/(use constant OMPLIB => ")[-_a-zA-Z0-9\/]*(";)/$1$omplib$2/;
            }
            print $out $line;
          }
          close $in;
          close $out;
        } else {
          cp($srcfile, $dest) or
            warn "Error copying file $srcfile to $dest: $!";
        }
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
