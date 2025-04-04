use strict;

use Test::More tests => 10;

use JAC::Setup qw/jsa dataverify hdrtrans/;
use OMP::Info::Obs;
use OMP::DateTools;
use OMP::EnterData;

my $never = '2031-01-01';

foreach (
        # CLS: one year from end 14B unless non-science.
        ['MJLSC01', 20120401, 1, '2016-03-01'],
        ['MJLSC01', 20150115, 1, '2016-03-01'],
        ['MJLSC01', 20120401, 0, '2012-04-01'],

        # EC: release immediately only if EC05 and science.
        ['M13AEC05', 20130401, 1, '2013-04-01'],
        ['M13AEC04', 20130401, 1, $never],
        ['M13AEC05', 20130401, 0, $never],
        ['M13AEC04', 20130401, 0, $never],

        # Any other non-science: release immediately.
        ['M12BU99', 20120909, 0, '2012-09-09'],

        # Otherwise: release 1 year after semester end.
        ['M12BU99', 20120909, 1, '2014-02-01'],
        ['M14BC99', 20150111, 1, '2016-03-01'],
        ) {
    my ($projectid, $utdate, $science, $expect) = @$_;

    my $obs = OMP::Info::Obs->new(
        telescope => 'JCMT',
        projectid => $projectid,
        utdate => $utdate
    );
    $obs->isScience($science);

    $science = $science ? 'science' : 'non-science';

    is(OMP::EnterData::calculate_release_date($obs)->ymd(),
        $expect,
        "$projectid $utdate $science -> $expect");
}
