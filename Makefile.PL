use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME'      => 'OMP',
    'VERSION'   => '0.01',
    'PREREQ_PM' => {
                    Test::More => 0,
                    Number::Interval => 0,
                    Digest::MD5 => '2.20',
                    Astro::PAL  => '1.02',
                    Astro::Coords => '0.05',
                    Astro::Coords::TLE => 0,
                    Astro::FITS::HdrTrans => 0,
                    Astro::WaveBand => 0,
                    Astro::FITS::Header => 0,
                    Astro::Catalog => 0,
                    Mail::Internet => 0,
                    MIME::Entity => 0,
                    Date::Manip => 0,
                    SCUBA::ODF => 0,       # for translator
                    SCUBA::FlatField => 0, # for translator
                    JCMT::DAS => 0,        # For WORF
                    XML::LibXML => '1.50',
                    PDL => '2.3',
                    PGPLOT => 0,
                    Error => 0,
                    HTML::TreeBuilder => 0,
                    HTML::FormatText => 0,
                    Config::IniFiles => 0,
                    DBI => 0,
                    Time::Piece => '1.00',
                    Starlink::ATL::Region => '0.01',
                    JSON => 0,
                    Test::Number::Delta => 0,
                    Encode => '2.50',  # this version no-longer untaints data
                   },
    dist          => { COMPRESS => "gzip -9f" },
   ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
     (ABSTRACT => 'Classes related to the observation management project',
      AUTHOR   => 'Tim Jenness <t.jenness@jach.hawaii.edu>') : ()),
    );
