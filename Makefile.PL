#!/usr/bin/env perl
#
# Copyright (c) 2007 Cisco Systems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

use ExtUtils::MakeMaker;

my $file = "lib/MTT/Version.pm";
my $version = "unknown";
if (-f $file) {
    require $file;
    $version = $MTT::Version::Combined;
}

WriteMakefile(
              ABSTRACT        => 'MPI Testing Tool',
              NAME            => 'MTT',
              VERSION         => $version,
              PREREQ_PM       => { 'Env::Modulecmd' => 0,
                                   'Config::IniFiles' => 0,
                                   'Text::TabularDisplay' => 0,
                                 },
              EXE_FILES       => [ "client/mtt", "client/mtt-lock-server", "client/mtt-relay", "client/mtt-submit", "client/whatami/whatami" ],
             );
