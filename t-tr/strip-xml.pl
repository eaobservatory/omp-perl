undef $/;
$_=<>;
s/<!--.*?-->//sg;
s/"OCS config filename"\s*VALUE=\K"[a-z0-9._]*"/""/s;
print;
