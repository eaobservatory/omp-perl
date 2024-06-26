package OMP::Translator;

=head1 NAME

OMP::Translator - translate science program to sequence

=head1 SYNOPSIS

    use OMP::Translator;

    $results = OMP::Translator->translate($sp);

=head1 DESCRIPTION

This class converts a science program object (an C<OMP::SciProg>)
into a sequence understood by the data acquisition system.

For ACSIS and SCUBA-2, XML configuration files are generated.

The actual translation is done in a subclass. The top level class
determines the correct class to use for the MSB and delegates the
translation of each observation within the MSB to that class.

=cut

use 5.006;
use strict;
use warnings;

use File::Spec;
use Scalar::Util qw/blessed/;
use DateTime;
use File::Path qw/mkpath/;
use Time::HiRes qw/gettimeofday/;
use Data::Dumper;

use Queue::EntryXMLIO qw/writeXML/;

use OMP::Error qw/:try/;
use OMP::Config;
use OMP::General;
use OMP::MSB;
use OMP::Translator::Base;

our $VERSION = '2.000';

=head1 METHODS

=over 4

=item B<translate>

Convert the science program object (C<OMP::SciProg>) into
a observing sequence understood by the instrument data acquisition
system.

    $xmlfile = OMP::Translator->translate($sp);
    $data = OMP::Translator->translate($sp, asdata => 1);
    @data = OMP::Translator->translate($sp, asdata => 1, simulate => 1);

The actual translation is implemented by the relevant subclass.
Currently JCMT Heterodyne and SCUBA-2 data can be translated.

By default, this method returns the name of an XML file that specifies
the location of each translated configuration using the dialect
understood by the standard JAC observing queue interface.

Optional arguments can be specified using hash technique. Allowed keys
are:

=over 4

=item simulate

Generate a translation suitable for simulate mode (if supported)

=item log

Log verbose messages to file.

=item verbose

If true, then messages will also go to stdout.  Otherwise verbosity
will be enabled in the translation class but only to log file.

=item loghandle

Handle to which to send log messages instead of a file.

=item no_log_input

Do not include the input MSB in the log output

=item asdata

If true, method will return either a list of translated
configuration objects (the type of which depends on
the instrument) or a reference to an array of such objects
(depending on context).  The expected object classes will be:

=over 4

=item ACSIS

JAC::OCS::Config

=item SCUBA-2

JAC::OCS::Config

=back

=item outputdir

Output directory. Passed on to the C<write_configs> method.

=item backwards_compatibility_mode

Option passed on to the C<write_configs> method.

=item debug

Enable additional debugging output.

=back

If there is more than one MSB to translate, REMOVED MSBs will be ignored.

=cut

sub translate {
    my $self = shift;
    my $thisclass = ref($self) || $self;
    my $sp = shift;

    my %opts = (
        asdata => 0,
        simulate => 0,
        log => 0,
        verbose => 0,
        debug => 0,
        @_);

    print join("\n", $sp->summary('asciiarray')) . "\n" if $opts{'debug'};

    # See how many MSBs we have (after pruning)
    my @msbs = OMP::Translator::Base->PruneMSBs($sp->msb);
    print "Number of MSBS to translate: " . scalar(@msbs) . "\n"
        if $opts{'debug'};

    # Return immediately if we have nothing to translate
    return () if scalar(@msbs) == 0;

    # The high level translator classes must process each MSB in turn
    # and on the basis of the instrument content, delegate the content
    # to an instrument specific translator.
    # The complication is that if an MSB includes multiple Observations
    # each of which is a different instrument, the translator must
    # delegate each Observation to each instrument in turn.

    # What we will end up doing is
    #   1. Unrolling the MSBs into individual observes
    #   2. sending the unrolled information one at a time to each translator
    #   3. hold the translated output in memory
    #   4. write out everything at once

    # Translator class associated with each instrument
    # This should be configuration driven
    #  OMP::Config->getData( 'translator.SCUBA' );
    my %class_lut = (
        WB => 'ACSIS',
        RXWB => 'ACSIS',
        HARP => 'ACSIS',
        # the backend name is the one that counts
        ACSIS => 'ACSIS',
        SCUBA2 => 'SCUBA2',
        "SCUBA-2" => "SCUBA2",
    );

    # Array of file handles that we should write verbose messages to
    my @handles = ();
    push(@handles, \*STDOUT) if $opts{'verbose'};  # we want stdout messages if verbose

    # Decide on low-level verbosity setting. Should be derived from the
    # "verbose" option and also the logging functionality.
    my $verbose = $opts{'verbose'};
    my $logh;
    if ($opts{log}) {
        try {
            # get hi resolution time
            my ($sec, $mic_sec) = gettimeofday();
            my $ut = DateTime->from_epoch(epoch => $sec, time_zone => 'UTC');

            # need ut date (in eval if logdir does not exist)
            my $logdir = OMP::Config->getData('translator.logdir', utdate => $ut);

            # try to make the directory - which may fail hence the try block
            mkpath($logdir);

            # filename with date stamp
            my $fname = "translation_"
                . $ut->strftime("%Y%m%d_%H%M%S") . "_"
                . sprintf("%06d", $mic_sec) . ".log";

            # now try to open a file
            open($logh, ">", File::Spec->catfile($logdir, $fname))
                || die "Error opening log file $fname: $!";

            # Have logging so force verbose and store filehandle
            $verbose = 1;
            push(@handles, $logh);
        }
        otherwise {
            # no logging around
        };
    }
    elsif (exists $opts{'loghandle'}) {
        $logh = $opts{'loghandle'};
        $verbose = 1;
        push @handles, $logh;
    }

    # Log the translation details with the OMP
    my $projectid = $sp->projectID;
    my @checksums = map {$_->checksum . "\n"} $sp->msb;
    OMP::General->log_message(
        "Translate request: Project:$projectid Checksums:\n\t"
        . join("\t", @checksums));

    # Loop over each MSB
    my @configs;  # Somewhere to put the translated output
    my @classes;  # and translator class used
    my @translators;  # and the translator objects
    for my $msb (@msbs) {
        # Survey Containers in child nodes present a problem since
        # the _get_SpObs method does not return clones for each target
        # that is present in the survey container (maybe it should)
        # That logic is currently contained in the SpSurveyContainer
        # parse and the MSB stringification. MSB stringification also
        # correctly handles the override targets from a parent survey
        # container

        # rather than duplicating container logic in another place
        # we either need to
        # 1. Fix _get_SpObs (or add a new method) to return cloned
        #    SpObs nodes with the correct target available
        # 2. Reparse from a stringified form

        # 2 is quicker but we also need to solve the suspend problem
        # since survey containers do not currently deal with obs_counters
        # properly when summarising.

        # Force stringify
        my $msbxml = "$msb";

        # regenerate
        my $fullmsb = OMP::MSB->new(
            XML => $msbxml,
            PROJECTID => $msb->projectID,
            OTVERSION => $msb->ot_version,
            TELESCOPE => $msb->telescope,
        );

        # Get all the component nodes (Sp* is fine
        # since we want SpInst and SpObsComp)
        # unless this MSB is actually an SpObs
        my @components;
        @components = grep {$_->getName =~ /Sp.*/ && $_->getName ne 'SpObs'}
            $fullmsb->_tree->findnodes('child::*')
            unless $fullmsb->_tree->getName eq 'SpObs';

        # Need to include all the code for determining whether the MSB
        # was suspended and whether to skip the observation or not
        my $suspend = $msb->isSuspended;

        # by default do not skip observations unless we are suspended
        my $skip = (defined $suspend ? 1 : 0);

        # Loop over each SpObs separately since that controls the
        # instrument granularity (each SpObs can only refer to a single instrument)
        my $spobs_count = 0;
        for my $spobs ($fullmsb->_get_SpObs) {
            $spobs_count ++;

            # We need to create a mini MSB object derived from each SpObs
            # For this to work, we need to copy the Component nodes from the
            # main SpMSB into the start of the SpObs itself

            # Get the first child of the SpObs (as an insertion point)
            my $child = $spobs->firstChild;

            # Insert telescope information

            # now insert the component nodes
            for my $node (@components) {
                $spobs->insertBefore($node, $child);
            }

            # Create a dummy MSB object (which will be fine so long as we
            # do not access attributes of an MSB such as isSuspended)
            my $tmpmsb = OMP::MSB->new(
                TREE => $spobs,
                PROJECTID => $msb->projectID,
                OTVERSION => $msb->ot_version,
            );

            # Copy the MSB title.
            $tmpmsb->msbtitle($msb->msbtitle());

            # This may have trashed the checksum so we need to make sure
            # it's consistent
            $tmpmsb->checksum($msb->checksum);

            # Now we can ask this MSB for its instrument
            # First we need to summarise the observation
            my @sum = $tmpmsb->obssum();

            # And verify that we can load the correct translator
            # by getting the instrument
            my $inst = uc($sum[0]->{instrument});

            # and overriding this with backend if we have one
            $inst = uc($sum[0]->{freqconfig}->{beName})
                if (exists $sum[0]->{freqconfig}
                && exists $sum[0]->{freqconfig}->{beName});

            # check we have the class
            throw OMP::Error::TranslateFail(
                "Instrument '$inst' has no corresponding Translator class")
                unless exists $class_lut{$inst};

            # Create the full class name
            my $class = $thisclass . '::' . $class_lut{$inst};
            print "Class is : $class\n" if $opts{'debug'};

            # Load the class
            eval "require $class;";
            if ($@) {
                throw OMP::Error::FatalError(
                    "Error loading class '$class': $@\n");
            }

            my $translator = $class->new;

            # Set DEBUGGING in the translator depending on the debugging state here
            $translator->debug($opts{'debug'});

            # enable verbose logging
            $translator->verbose($verbose) if $translator->can("verbose");

            # and register filehandles
            $translator->outhdl(@handles) if $translator->can("outhdl");

            if (defined $logh) {
                print $logh "---------------------------------------------\n";
            }

            # For large MSBs (and large science programmes with multiple msbs)
            # it is helpful to report the MSB title and SpObs count
            my $title = $msb->msbtitle;
            $title = "<no title>" unless defined $title;
            for my $h (@handles) {
                print $h "Translating Obs #$spobs_count from MSB $title\n";
            }

            # And forward to the correct translator
            # We always get objects, sometimes multiple objects
            my @new = $translator->translate($tmpmsb, simulate => $opts{simulate});

            if (defined $logh and not $opts{'no_log_input'}) {
                # Basic XML
                print $logh "---------------------------------------------\n";
                print $logh "Input MSB:\n";
                print $logh "$tmpmsb\n";
                print $logh "---------------------------------------------\n";

                # Summary
                my $info = $tmpmsb->info();
                my $summary = $info->summary("hashlong");

                print $logh "Observation Summary:\n";
                print $logh Dumper($summary);
                print $logh "---------------------------------------------\n";
            }

            # Now force translator directory into config
            # All of the objects returned by translate() support the outputdir() method
            $_->outputdir($translator->transdir) foreach @new;

            # Store them in the main config array
            push @configs, @new;

            # and store the class for each config
            push @classes, $class foreach @new;
            push @translators, $translator foreach @new;
        }
    }

    # Post process the config files to insert any additional items needed for
    # observing. Send them to the relevant translator class in bulk
    if (@configs) {
        my @contiguous;
        for my $i (0 .. $#configs) {
            if (@contiguous && $contiguous[-1]->{class} eq $classes[$i]) {
                push @{$contiguous[-1]->{configs}}, $configs[$i];
            }
            else {
                push @contiguous, {
                    class => $classes[$i],
                    translator => $translators[$i],
                    configs => [$configs[$i]]};
            }
        }

        my @newconfigs;
        for my $groups (@contiguous) {
            my $translator = $groups->{'translator'};
            my @theseconfigs = @{$groups->{configs}};
            if ($translator->can('insert_setup_obs')) {
                push @newconfigs,
                    $translator->insert_setup_obs(
                        {simulate => $opts{simulate}},
                        @theseconfigs);
            }
            else {
                push @newconfigs, @theseconfigs;
            }
        }

        @configs = @newconfigs;
    }

    # Clear logging handles.
    @handles = ();

    # Now we have an array of translated objects
    # Array of JAC::OCS::Config objects
    #
    # Now need to either return them or write them to disk
    # If we write them to disk we return the QueueEntry XML to the
    # caller.

    # If they want the data we do not write anything
    if ($opts{asdata}) {
        # disable the loggin
        for (@configs) {
            $_->outhdl(undef) if $_->can("outhdl");
        }

        if (wantarray) {
            return @configs;
        }
        else {
            return \@configs;
        }
    }
    else {
        my %write_options = ();

        $write_options{'transdir'} = $opts{'outputdir'}
            if exists $opts{'outputdir'};

        $write_options{'backwards_compatibility_mode'} = $opts{'backwards_compatibility_mode'}
            if exists $opts{'backwards_compatibility_mode'};

        # We write to disk and return the name of the wrapper file
        my $xml = $self->write_configs(\@configs, %write_options);

        # clear logging
        for (@configs) {
            $_->outhdl(undef) if $_->can("outhdl");
        }

        # return
        return $xml;
    }
}

=item B<write_configs>

Write each config object to disk and return the name of an XML
file containing all the information required for loading the OCS queue.

    $qxml = OMP::Translator->write_configs(\@configs, %options);

This method does not care what type of object is passed in so long
as the following methods are supported:

=over 4

=item telescope

Name of telescope.

=item instrument

Name of instrument.

=item duration

Estimated duration (Time::Seconds).

=item write_file

Write file to disk and return name of file.

=back

An exception is thrown if the telescope is not the same for each
config.

Options include:

=over 4

=item transdir

By default the configs are written to the directory suitable for each type of
translation (ie whatever is in each object), unless an explicit directory
is provided to this method through the C<transdir> option.

    $qxml = OMP::Translator->write_configs(\@configs, transdir => $dir);

=item backwards_compatibility_mode

By default, files are written in a format suitable for uploading to
the new OCS queue using an XML format.

If this switch is enabled, the file name returned by the translator
will be instrument specific and multiple instruments can not be
combined within a single translation.

=back

=cut

sub write_configs {
    my $class = shift;
    my $configs = shift;
    my %opts = @_;

    # Specified transdir overrides default
    my $outdir;
    if (defined $opts{transdir}) {
        $outdir = $opts{transdir};
    }

    if ($opts{'backwards_compatibility_mode'}) {
        # check our config objects are all the same type
        my $class = blessed($configs->[0]);
        my $inst = $configs->[0]->instrument;
        for my $c (@$configs) {
            if (blessed($c) ne $class) {
                throw OMP::Error::TranslateFail(
                    "Attempting to write different instrument configurations to incompatible output files. Compatibility mode only supports a single translated instrument/backend [$inst vs "
                    . $c->instrument . "]");
            }
        }

        # Now work out the container class
        my $cclass = $configs->[0]->container_class();
        eval "require $cclass;";
        throw OMP::Error::FatalError(
            "Unable to load container class $cclass: $@")
            if $@;

        # And create it blank
        my $container = $cclass->new();

        # Store the configs inside
        $container->push_config(@$configs);

        # Now write the container
        return $container->write_file(
            (defined $outdir ? $outdir : ()),
            {chmod => 0666});
    }
    else {
        # Arguments
        my %args = (
            fprefix => 'translated',
            chmod => 0666,
        );
        $args{outputdir} = $outdir if defined $outdir;

        # XML location is required for the queue. This is not instrument
        # dependent but if $outdir is defined we must use it. Else
        # we use the config system
        if (defined $outdir) {
            $args{xmldir} = $outdir;
        }
        else {
            # specify our default location
            my $qdir;
            eval {
                $qdir = OMP::Config->getData("translator.queuedir");
            };
            $qdir = File::Spec->curdir() unless defined $qdir;
            $args{xmldir} = $qdir;
        }

        # Delegate the writing to the XMLIO class
        return Queue::EntryXMLIO::writeXML(\%args, @$configs);
    }
}

1;

__END__

=back

=head1 COPYRIGHT

Copyright (C) 2007-2008 Science and Technology Facilities Council.
Copyright (C) 2002-2007 Particle Physics and Astronomy Research Council.
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

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut
