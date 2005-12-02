#!/usr/bin/env perl
#
# Copyright (c) 2004-2005 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2004-2005 The Trustees of the University of Tennessee.
#                         All rights reserved.
# Copyright (c) 2004-2005 High Performance Computing Center Stuttgart, 
#                         University of Stuttgart.  All rights reserved.
# Copyright (c) 2004-2005 The Regents of the University of California.
#                         All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Test;

use strict;
use MTT::Test::Build;
use MTT::Test::Run;
use XML::Simple;

#--------------------------------------------------------------------------

# Exported build tests handle
our $tests;

#--------------------------------------------------------------------------

# Filename where list of test build information is kept
my $builds_data_filename = "test_builds.xml";

# XML options for the test builds
my $builds_xs;

#--------------------------------------------------------------------------

# This function exists solely so that we don't have to invoke
# MTT::Test::Build::Build in the top level
sub Build {
    return MTT::Test::Build::Build(@_);
}

#--------------------------------------------------------------------------

# This function exists solely so that we don't have to invoke
# MTT::Test::Run::Run in the top level
sub Run {
    return MTT::Test::Run::Run(@_);
}

#--------------------------------------------------------------------------

sub _setup_builds_xml {
    $builds_xs = new XML::Simple(KeyAttr => { mpi_section => "name",
                                              mpi_unique => "id",
                                              install_section => "name",
                                              test_build => "name",
                                            },
                                   ForceArray => [ "mpi_section", 
                                                   "mpi_unique",
                                                   "install_section",
                                                   "test_build" ],
                                   AttrIndent => 1,
                                   RootName => "test_builds",
                                   );
}

#--------------------------------------------------------------------------

sub LoadBuilds {
    my ($dir) = @_;

    # Explicitly delete anything that was there
    $MTT::Test::builds = undef;

    _setup_builds_xml()
        if (!$builds_xs);
    
    # If the file exists, read it in
    if (-f "$dir/$builds_data_filename") {
        my $in = $builds_xs->XMLin("$dir/$builds_data_filename");

        # Now transform this to the form suitable for
        # $MTT::Test::builds (see comment in SaveSources).  Wow.
        # For each MPI source
        foreach my $mpi_section_key (keys(%{$in->{mpi_section}})) {
            my $mpi_section = $in->{mpi_section}->{$mpi_section_key};

            # For each instance of that source
            foreach my $mpi_unique_key (keys(%{$mpi_section->{mpi_unique}})) {
                my $mpi_unique = $mpi_section->{mpi_unique}->{$mpi_unique_key};

                # For each install of that source
                foreach my $install_section_key (keys(%{$mpi_unique->{install_section}})) {
                    my $install_section = $mpi_unique->{install_section}->{$install_section_key};

                    # For each test build
                    foreach my $test_build_key (keys(%{$install_section->{test_build}})) {
                        my $test_build = $install_section->{test_build}->{$test_build_key};

                        $MTT::Test::builds->{$mpi_section_key}->{$mpi_unique_key}->{$install_section_key}->{$test_build_key} = 
                            $in->{mpi_section}->{$mpi_section_key}->{mpi_unique}->{$mpi_unique_key}->{install_section}->{$install_section_key}->{test_build}->{$test_build_key};
                    }
                }
            }
        }
    }
}

#--------------------------------------------------------------------------

use Data::Dumper;
sub SaveBuilds {
    my ($dir) = @_;

    _setup_builds_xml()
        if (!$builds_xs);

    # Transform $MTT::Test::builds to something XML::Simple can write
    # into valid XML (see comment in SaveSources).  Wow.
    my $transformed;

    # For each MPI source
    foreach my $mpi_section_key (keys(%{$MTT::Test::builds})) {
        my $mpi_section = $MTT::Test::builds->{$mpi_section_key};

        # For each instance of that source
        foreach my $mpi_unique_key (keys(%{$mpi_section})) {
            my $mpi_unique = $mpi_section->{$mpi_unique_key};

            # For each install of that source
            foreach my $install_section_key (keys(%{$mpi_unique})) {
                my $install_section = $mpi_unique->{$install_section_key};

                # For each test build
                foreach my $test_build_key (keys(%{$install_section})) {
                    my $test_build = $install_section->{$test_build_key};

                    $transformed->{mpi_section}->{$mpi_section_key}->{mpi_unique}->{$mpi_unique_key}->{install_section}->{$install_section_key}->{test_build}->{$test_build_key} = 
                    $MTT::Test::builds->{$mpi_section_key}->{$mpi_unique_key}->{$install_section_key}->{$test_build_key};
                }
            }
        }
    }

    # Write out the file
    my $xml = $builds_xs->XMLout($transformed);
    my $file = "$dir/$builds_data_filename";
    open(FILE, ">$file.new");
    print FILE $xml;
    close(FILE);
    system("mv $file.new $file");
}

1;
