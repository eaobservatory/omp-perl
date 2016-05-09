undef $/;
$_=<>;
s/<!--.*?-->//sg;
s/("OCS config filename"\s*VALUE=)"[a-z0-9._]*"/$1""/s;
s/<pointing_offset [-+=A-Z0-9". ]* \/>/<!-- pointing_offset removed -->/g;
print;
