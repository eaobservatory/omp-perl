undef $/;
$_=<>;
s/<!--.*?-->//sg;
s/("OCS config filename"\s*VALUE=)"[a-z0-9._]*"/$1""/s;
print;
