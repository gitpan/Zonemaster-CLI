use 5.014002;
use strict;
use warnings FATAL => 'all';
use inc::Module::Install;

name     'Zonemaster-CLI';
author   q{Calle Dybedahl <calle@init.se>};
license  'bsd';
all_from 'lib/Zonemaster/CLI.pm';

perl_version 5.014002;

tests_recursive('t');

resources (
   license    => 'http://www.opensource.org/licenses/BSD-3-Clause',
   repository => 'https://github.com/dotse/zonemaster-cli',
   bugtracker => 'https://github.com/dotse/zonemaster-cli/issues',
);

configure_requires (
   'Module::Install' => 0,
);

build_requires (
   'Test::More' => 0,
);

requires (
    'Zonemaster' => '0.0.4',
    'MooseX::Getopt' => 0,
    'Getopt::Long::Descriptive' => 0,
    'Net::LDNS' => 0.65,
    'Locale::TextDomain' => 0,
    'Text::Reflow' => 0,
    'JSON::XS' => 0,
);

install_script 'zonemaster-cli';
install_share;

WriteAll;
