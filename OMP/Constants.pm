package OMP::Constants;

=head1 NAME

OMP::Constants - Constants available to the OMP system

=head1 SYNOPSIS

  use OMP::Constants;
  use OMP::Constants qw/OMP__OK/;
  use OMP::Constants qw/:status/;

=head1 DESCRIPTION

Provide access to OMP constants, necessary to use this module if you wish
to return an OMP__ABORT or OMP__FATAL status using OMP::Error.

=cut

use strict;
use warnings;

use vars qw/ $VERSION @ISA %EXPORT_TAGS @EXPORT_OK/;
'$Revision$ ' =~ /.*:\s(.*)\s\$/ && ($VERSION = $1);

require Exporter;

@ISA = qw/Exporter/;

my @status = qw/OMP__OK OMP__ERROR OMP__FATAL/;
my @fb = qw/OMP__FB_INFO OMP__FB_IMPORTANT OMP__FB_HIDDEN OMP__FB_DELETE OMP__FB_SUPPORT/;
my @done = qw/ OMP__DONE_FETCH OMP__DONE_DONE OMP__DONE_ALLDONE
  OMP__DONE_COMMENT OMP__DONE_UNDONE OMP__DONE_ABORTED
  OMP__DONE_REJECTED OMP__DONE_SUSPENDED   /;
my @msb = qw/ OMP__MSB_REMOVED /;
my @obs = qw/ OMP__OBS_GOOD OMP__OBS_BAD OMP__OBS_QUESTIONABLE /;
my @timegap = qw/ OMP__TIMEGAP_INSTRUMENT OMP__TIMEGAP_WEATHER
                  OMP__TIMEGAP_FAULT OMP__TIMEGAP_UNKNOWN
                  OMP__TIMEGAP_PREV_PROJECT OMP__TIMEGAP_NEXT_PROJECT /;

@EXPORT_OK = (@status, @fb, @done, @msb, @obs, @timegap);

%EXPORT_TAGS = (
		'all' =>[ @EXPORT_OK ],
		'status'=>\@status,
		'fb' =>\@fb,
		'msb' => \@msb,
		'done'=> \@done,
    'obs' => \@obs,
    'timegap' => \@timegap,
	       );

Exporter::export_tags( keys %EXPORT_TAGS);

=head1 CONSTANTS

The following constants are available from this module:

=head2 General status

=over 4

=item B<OMP__OK>

This constant contains the definition of good OMP status.

=cut

use constant OMP__OK => 0;


=item B<OMP__ERROR>

This constant contains the definition of bad OMP status.

=cut

use constant OMP__ERROR => -1;

=item B<OMP__FATAL>

This constant contains the default exception value.

=cut

use constant OMP__FATAL => -2;


use constant OMP__AUTHFAIL => -3;
use constant OMP__DBCONFAIL => -4;
use constant OMP__MSBBADQUERY => -5;
use constant OMP__BADPROJ => -6;
use constant OMP__MSBMISS => -7;
use constant OMP__SPBADSTOR => -8;
use constant OMP__SPBADRET => -9;
use constant OMP__SPBADXML => -10;
use constant OMP__SPEMPTY => -11;


=back

=head2 Feedback system

=over 4

=item B<OMP__FB_INFO>

This constant contains the definition of info feedback status.

=cut

use constant OMP__FB_INFO => 1;

=item B<OMP__FB_IMPORTANT>

This constant contains the definition of important feedback status.

=cut

use constant OMP__FB_IMPORTANT => 2;

=item B<OMP__FB_HIDDEN>

This constant contains the definition of hidden feedback status.

=cut

use constant OMP__FB_HIDDEN => 0;

=item B<OMP__FB_DELETE>

This constant contains the definition of delete feedback status.

=cut

use constant OMP__FB_DELETE => -1;

=item B<OMP__FB_SUPPORT>

This constant contatins the definition of a support feedback status.

=cut

use constant OMP__FB_SUPPORT => 3;

=back

=head2 MSB Done constants

=over 4

=item OMP__DONE_FETCH

Entry was associated with a retrieval from the database. This is
used to prepopulate the table in case the MSB later disappears from
the science program.

=cut

use constant OMP__DONE_FETCH => 0;

=item OMP__DONE_DONE

Entry is associated with an observation trigger.

=cut

use constant OMP__DONE_DONE => 1;

=item OMP__DONE_UNDONE

Entry is associated with a reversal of the observation done
status.

=cut

use constant OMP__DONE_UNDONE => 4;

=item OMP__DONE_ALLDONE

Entry is associated with an action setting all the remaining
MSB counts to zero.

=cut

use constant OMP__DONE_ALLDONE => 2;

=item OMP__DONE_COMMENT

Entry is associated with a simple comment.

=cut

use constant OMP__DONE_COMMENT => 3;

=item OMP__DONE_ABORTED

The MSB was started but was aborted part way through.

=cut

use constant OMP__DONE_ABORTED => 7;

=item OMP__DONE_REJECTED

All the observations in an MSB were completed but the observer
decided that it was not suitable.

=cut

use constant OMP__DONE_REJECTED => 5;

=item OMP__DONE_SUSPENDED

The MSB was started but it was unable to be completed. The observer
determined that useful data was obtained and that the MSB could safely
be completed another day without repeating the initial observations.

=cut

use constant OMP__DONE_SUSPENDED => 6;


=back

=head2 MSBs

=over 4

=item OMP__MSB_REMOVED

The MSB has been removed from consideration even though it may
not have been observed.

=cut

use constant OMP__MSB_REMOVED => -999;

=back

=head2 Observation status

=over 4

=item OMP__OBS_GOOD

Flags an observation as good.

=cut

use constant OMP__OBS_GOOD => 0;

=item OMP__OBS_QUESTIONABLE

Flags an observation as questionable -- neither good nor bad.

=cut

use constant OMP__OBS_QUESTIONABLE => 1;

=item OMP__OBS_BAD

Flags an observation as bad.

=cut

use constant OMP__OBS_BAD => 2;

=back

=head2 Timegap reasons

=over 4

=item OMP__TIMEGAP_INSTRUMENT

Flags a timegap as being caused by an instrument change.

=cut

use constant OMP__TIMEGAP_INSTRUMENT => 10;

=item OMP__TIMEGAP_WEATHER

Flags a timegap as being caused by weather.

=cut

use constant OMP__TIMEGAP_WEATHER => 11;

=item OMP__TIMEGAP_FAULT

Flags a timegap as being caused by a fault.

=cut

use constant OMP__TIMEGAP_FAULT => 12;

=item OMP__TIMEGAP_NEXT_PROJECT

Flags a timegap so that the time lost will be charged to
the project to which the observation following the timegap
belongs.

=cut

use constant OMP__TIMEGAP_NEXT_PROJECT => 14;

=item OMP__TIMEGAP_PREV_PROJECT

Flags a timegap so that the time lost will be charged to
the project to which the observation preceding the timegap
belongs.

=cut

use constant OMP__TIMEGAP_PREV_PROJECT => 15;

=item OMP__TIMEGAP_UNKNOWN

Flags a timegap as being caused by unknown reasons.

=cut

use constant OMP__TIMEGAP_UNKNOWN => 13;

=back

=head1 TAGS

Individual sets of constants can be imported by 
including the module with tags. For example:

  use OMP::Constants qw/:status/;

will import all constants associated with OMP status checking.

The available tags are:

=over 4

=item :all

Import all constants.

=item :status

Constants associated with OMP status checking: OMP__OK and OMP__ERROR.

=item :fb

Constants associated with the feedback system.

=item :done

Constants associated with the MSB done table.

=item :msb

Constants associated with MSBs.

=item :obs

Constants associated with observation statuses.

=back

=head1 USAGE

The constants can be used as if they are subroutines.
For example, if I want to print the value of OMP__ERROR I can

  use OMP::Constants;
  print OMP__ERROR;

or

  use OMP::Constants ();
  print OMP::Constants::OMP__ERROR;

=head1 SEE ALSO

L<constants>

=head1 REVISION

$Id$

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>,
Frossie Economou E<lt>frossie@jach.hawaii.eduE<gt>,
Kynan Delorey E<lt>kynan@jach.hawaii.eduE<gt>, and
Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>

=head1 REQUIREMENTS

The C<constants> package must be available. This is a standard
perl package.

=head1 COPYRIGHT

Copyright (C) 1998-2002 Particle Physics and Astronomy Research
Council. All Rights Reserved.

=cut



1;
