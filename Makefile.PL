use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME'      => 'OMP',
    'VERSION'   => '0.01',
    dist          => { COMPRESS => "gzip -9f" },
   ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
     (ABSTRACT => 'Classes related to the observation management project',
      AUTHOR   => 'Tim Jenness <t.jenness@jach.hawaii.edu>') : ()),
    );
