#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006      Cisco Systems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Test;

use strict;
use File::Find;
use MTT::Test::Get;
use MTT::Test::Build;
use MTT::Test::Run;
use MTT::Files;

#--------------------------------------------------------------------------

# Exported sources tests handle
our $sources;

# Exported build tests handle
our $builds;

# Exported run tests handle
our $runs;
our $runs_to_be_saved;

#--------------------------------------------------------------------------

# Filename where list of test sources information is kept
my $sources_data_filename = "test_sources.dump";

# Filename where list of test build information is kept
my $builds_data_filename = "test_builds.dump";

# Subdir where test runs are kept
my $runs_subdir = "test_runs";

# Filename where list of test run information is kept
my $runs_data_filename = "test_runs.dump";

# Helper variable for when we're loading test run data
my $load_run_file_start_dir;

#--------------------------------------------------------------------------

# This function exists solely so that we don't have to invoke
# MTT::Test::Get::Get in the top level
sub Get {
    return MTT::Test::Get::Get(@_);
}

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

sub LoadSources {
    my ($dir) = @_;

    # Explicitly delete anything that was there
    $MTT::Test::sources = undef;

    # If the file exists, read it in
    my $data;
    MTT::Files::load_dumpfile("$dir/$sources_data_filename", \$data);
    $MTT::Test::sources = $data->{VAR1};
}

#--------------------------------------------------------------------------

sub SaveSources {
    my ($dir) = @_;

    MTT::Files::save_dumpfile("$dir/$sources_data_filename", 
                              $MTT::Test::sources);
}

#--------------------------------------------------------------------------

sub LoadBuilds {
    my ($dir) = @_;

    # Explicitly delete anything that was there
    $MTT::Test::builds = undef;

    # If the file exists, read it in
    my $data;
    MTT::Files::load_dumpfile("$dir/$builds_data_filename", \$data);
    $MTT::Test::builds = $data->{VAR1};
}

#--------------------------------------------------------------------------

sub SaveBuilds {
    my ($dir) = @_;

    MTT::Files::save_dumpfile("$dir/$builds_data_filename", 
                              $MTT::Test::builds);
}

#--------------------------------------------------------------------------

use Data::Dumper;
sub LoadRuns {
    my ($dir) = @_;

    # Explicitly delete anything that was there
    $MTT::Test::runs = undef;

    # See SaveRuns, below, for an explanation.  We traverse
    # directories looking for dump files and read them into the
    # appropriate section of the $MTT::Test::runs hash.

    $load_run_file_start_dir = "$dir/$runs_subdir";
    find(\&load_run_file, $load_run_file_start_dir)
        if (-d $load_run_file_start_dir);
}

sub load_run_file {
    # We only want files named $runs_data_filename
    return 0
        if (! -f $_ || $runs_data_filename ne $_);

    # Read in the file
    my $data;
    MTT::Files::load_dumpfile($File::Find::name, \$data);

    # Put the loaded data in the hash in the right place.  Per
    # SaveRuns(), below, we look at the key values in $data->{VAR1} to
    # know where to put $data->{VAR2} in the $MTT::Test::runs hash.
    my $str = "\$MTT::Test::runs";
    my $k = 1;
    do {
        $str .= "->{\"" . $data->{VAR1}->{$k} . "\"}";
        ++$k;
    } while (exists($data->{VAR1}->{$k}));
    $str .= " = \$data->{VAR2}";
    eval $str;
}

#--------------------------------------------------------------------------

sub SaveRuns {
    my ($dir) = @_;

    # Because test run data can get very, very large, we break it up
    # and store it in lots of smaller files so that we can write out
    # to disk in small portions.

    # Test runs are stored in the hash with this order of keys:

    # mpi_get_simple_section_name
    # mpi_version
    # mpi_install_simple_section_name
    # test_build_simple_section_name
    # test_run_simple_section_name
    # test_name
    # np
    # command

    # We save from test_name and down in a single file.

    # For each MPI get section
    foreach my $mpi_get_key (keys(%{$MTT::Test::runs_to_be_saved})) {
        my $mpi_get = $MTT::Test::runs->{$mpi_get_key};

        # For each source of that MPI
        foreach my $mpi_version_key (keys(%{$mpi_get})) {
            my $mpi_version = $mpi_get->{$mpi_version_key};

            # For each MPI install section
            foreach my $mpi_install_key (keys(%{$mpi_version})) {
                my $mpi_install = $mpi_version->{$mpi_install_key};
                
                # For each test build section
                foreach my $test_build_key (keys(%{$mpi_install})) {
                    my $test_build = $mpi_install->{$test_build_key};
                    
                    # For each test run section
                    foreach my $test_run_key (keys(%{$test_build})) {
                        my $test_run = $test_build->{$test_run_key};
                        
                        # For each test name
                        foreach my $test_name_key (keys(%{$test_run})) {
                            my $test_name = $test_run->{$test_name_key};

                            my $file = MTT::Files::safe_mkdir("$dir/$runs_subdir/$mpi_get_key/$mpi_version_key/$mpi_install_key/$test_build_key/$test_run_key/$test_name_key") . "/$runs_data_filename";

                            # We need to save two items in test run
                            # data files -- the actual data and where
                            # it belongs in the $MTT::Test::runs hash.
                            my $hashname = {
                                1 => $mpi_get_key,
                                2 => $mpi_version_key,
                                3 => $mpi_install_key,
                                4 => $test_build_key,
                                5 => $test_run_key,
                                6 => $test_name_key,
                            };
                            MTT::Files::save_dumpfile($file, $hashname, 
                                                      $test_name);
                        }
                    }
                }
            }
        }
    }

    # Explicitly reset the test runs to be saved
    $MTT::Test::runs_to_be_saved = undef;
}

1;
