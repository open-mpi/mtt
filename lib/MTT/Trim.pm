#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Trim;

use strict;

use Config::IniFiles;
use Data::Dumper;
use MTT::Messages;
use MTT::Values;

#--------------------------------------------------------------------------

# Number of trees to save
my $save_successful_gets;
my $save_failed_gets;

my $save_successful_installs;
my $save_failed_installs;

my $save_successful_builds;
my $save_failed_builds;

my $save_successful_runs;
my $save_failed_runs;

#--------------------------------------------------------------------------

# Trim old trees after a run
sub Trim {
    my ($ini) = @_;

    Verbose("*** Trim phase starting\n");

    # Look up various values from the ini file
    _load_values($ini);

    # Go in "reverse" order:
    #
    # - delete expired failed test runs
    # - delete expired successful test runs
    # - delete expired failed test builds
    # - delete expired successful test builds
    # - delete expired failed MPI installs
    # - delete expired successful MPI installs
    # - delete expired failed MPI gets
    # - delete expired successful MPI gets
    #
    # Do it in this order because deleting, for example, test runs may
    # orphan some test builds, MPI installs, and MPI gets.  If we did
    # the deleting the other way around, then we'd have to go back and
    # look for the orphans to delete them.

    _trim_runs();
    _trim_builds();
    _trim_installs();
    _trim_gets();

    Verbose("*** Trim phase complete\n");
}

#--------------------------------------------------------------------------

sub _load_values {
    my ($ini) = @_;
    my $val;

    # Look for the overall "saved_failed" and "save_successful" params
    # that provide defaults for all the rest
    $val = Value($ini, "MTT", "save_successful");
    $save_successful_gets = $save_successful_installs = 
        $save_successful_builds = $save_successful_runs = $val
        if (defined($val));

    $val = Value($ini, "MTT", "save_failed");
    $save_failed_gets = $save_failed_installs = 
        $save_failed_builds = $save_failed_runs = $val
        if (defined($val));

    # Now look for the individual values
    $val = Value($ini, "MTT", "save_successful_gets");
    $save_successful_gets = $val
        if (defined($val));
    $val = Value($ini, "MTT", "save_failed_gets");
    $save_failed_gets = $val
        if (defined($val));

    $val = Value($ini, "MTT", "save_successful_installs");
    $save_successful_installs = $val
        if (defined($val));
    $val = Value($ini, "MTT", "save_failed_installs");
    $save_failed_installs = $val
        if (defined($val));

    $val = Value($ini, "MTT", "save_successful_builds");
    $save_successful_builds = $val
        if (defined($val));
    $val = Value($ini, "MTT", "save_failed_builds");
    $save_failed_builds = $val
        if (defined($val));

    $val = Value($ini, "MTT", "save_successful_runs");
    $save_successful_runs = $val
        if (defined($val));
    $val = Value($ini, "MTT", "save_failed_runs");
    $save_failed_runs = $val
        if (defined($val));
}

#--------------------------------------------------------------------------

sub _trim_runs {

    # For each MPI source
    foreach my $mpi_section_key (keys(%{$MTT::Test::runs})) {
        my $mpi_section = $MTT::Test::runs->{$mpi_section_key};

        # For each instance of that source
        foreach my $mpi_unique_key (keys(%{$mpi_section})) {
            my $mpi_unique = $mpi_section->{$mpi_unique_key};

            # For each install of that source
            foreach my $install_section_key (keys(%{$mpi_unique})) {
                my $install_section = $mpi_unique->{$install_section_key};

                # For each test build
                foreach my $test_build_key (keys(%{$install_section})) {
                    my $test_build = $install_section->{$test_build_key};

                    # For each test run section
                    foreach my $test_run_key (keys(%{$test_build})) {
                        my $test_run = $test_build->{$test_run_key};

                        # For each test name
                        foreach my $test_name_key (keys(%{$test_run})) {
                            my $test_name = $test_run->{$test_name_key};

                            # For each np
                            foreach my $test_np_key (keys(%{$test_name})) {
                                my $test_np = $test_name->{$test_np_key};

                                # For each cmd
                                foreach my $test_cmd_key (keys(%{$test_np})) {
                                    my $test_cmd = $test_np->{$test_cmd_key};

                                    # Check to see if this was a
                                    # successful test build
                                    if ($test_cmd->{test_pass}) {
#                                        print "FOUND SUCCESSFUL RUN\n";
                                        1;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

#--------------------------------------------------------------------------

sub _trim_builds {
}

#--------------------------------------------------------------------------

sub _trim_installs {
}

#--------------------------------------------------------------------------

sub _trim_gets {
}


1;


