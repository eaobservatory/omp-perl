undef $/;
$_=<>;
s/<!--.*?-->//sg;
s/("OCS config filename"\s*VALUE=)"[a-z0-9._]*"/$1""/s;
s/<(pointing_offset|dr_disp_machine) [-+_=a-zA-Z0-9". ]*\/>/<!-- \1 removed -->/g;
print;
