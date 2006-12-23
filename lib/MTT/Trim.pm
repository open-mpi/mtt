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

package MTT::Trim;

use strict;

use Config::IniFiles;
use Data::Dumper;
use File::Basename;
use MTT::Messages;
use MTT::Values;
use MTT::Globals;
use MTT::Test;
use MTT::MPI;

#--------------------------------------------------------------------------

# Exported constant
use constant {
    TRIM_KEY => "TO_BE_TRIMMED",
};

#--------------------------------------------------------------------------

# Trim old trees after a run
sub Trim {
    my ($ini, $source_dir, $install_dir) = @_;

    Verbose("*** Trim phase starting\n");

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

    _trim_test_runs($install_dir);
    _trim_test_builds($install_dir);
    _trim_test_gets($source_dir);
    _trim_mpi_installs($install_dir);
    _trim_mpi_gets($source_dir);

    Verbose("*** Trim phase complete\n");
}

#--------------------------------------------------------------------------

sub _trim_test_runs {
    my $install_dir = shift;

    # In this step, we're:

    # 1. Decreasing refcounts on MTT::Test::builds
    # 2. Removing data from MTT::Test::runs (and removing their
    #    corresponding back-end data files)

    # For each run, we declare it successful if *all* of its tests
    # passed.  Otherwise, it's classified as failed.  We then pass
    # through all the runs for a given section in the INI file and
    # save the last N (per the save_successful_test_runs and
    # save_failed_test_runs limits).

    my $successful;
    my $failed;

    # For each MPI source
    foreach my $get_key (keys(%{$MTT::Test::runs})) {
        my $get = $MTT::Test::runs->{$get_key};

        foreach my $version_key (keys(%{$get})) {
            my $version = $get->{$version_key};

            foreach my $install_key (keys(%{$version})) {
                my $install = $version->{$install_key};

                foreach my $build_key (keys(%{$install})) {
                    my $build = $install->{$build_key};

                    foreach my $run_key (keys(%{$build})) {
                        my $run = $build->{$run_key};

                        # We're now in the run itself.  Tabulate
                        # successes and failures for this run to
                        # determine if the overall run failed or
                        # succeeded.

                        my $succeeded = 1;
                        my $timestamp = time;

                        foreach my $test_key (keys(%{$run})) {
                            my $test = $run->{$test_key};

                            foreach my $np_key (keys(%{$test})) {
                                my $np = $test->{$np_key};

                                foreach my $cmd_key (keys(%{$np})) {
                                    my $cmd = $np->{$cmd_key};

                                    # Did this individual test pass?
                                    if (MTT::Test::PASS !=
                                        $cmd->{test_result}) {
                                        $succeeded = 0;
                                        last;
                                    }

                                    # Save the earliest timestamp in
                                    # this test run
                                    if ($cmd->{start_timestamp} < $timestamp) {
                                        $timestamp = $cmd->{start_timestamp};
                                    }
                                }
                            }
                        }

                        # Make one record for all the tests in this
                        # run (this effectively groups all the tests
                        # from one section of the INI file).
                        my $item = {
                            timestamp => $timestamp,
                            test_run_name => $run_key,
                            test_run_data => $run,

                            # Information used to decrement the
                            # refcount on MTT::Test::builds
                            mpi_get => $get_key,
                            mpi_version => $version_key,
                            mpi_install => $install_key,
                            test_build => $build_key,
                        };
                        if ($succeeded) {
                            push(@{$successful->{$run_key}}, $item);
                        } else {
                            push(@{$failed->{$run_key}}, $item);
                        }
                    }
                }
            }
        }
    }

    # For each test run section, sort them so that the oldest is first
    # and the youngest is last.  Then trim accordingly.

    # First do the successes
    foreach my $run_key (keys(%{$successful})) {
        my $successes = $successful->{$run_key};
        _trim_test_run_work("successful", $run_key, $successes, 
                            $MTT::Globals::Values->{save_successful_test_runs});
    }

    # Then do the failures
    foreach my $run_key (keys(%{$failed})) {
        my $fails = $failed->{$run_key};
        _trim_test_run_work("failed", $run_key, $fails, 
                            $MTT::Globals::Values->{save_failed_test_runs});
    }

    # Now that the data structure is marked, invoke a routine that
    # actually goes through and deletes the data from the structure
    # and removes the back-end files.
    MTT::Test::TrimRuns($install_dir);
}

#--------------------------------------------------------------------------

sub _trim_test_run_work {
    my ($adj, $test_name, $data, $num_to_save) = @_;
    my $n = $#$data + 1;
    my $text = "run";
    $text .= "s"
        if ($n > 1);
    if ($n > $num_to_save) {
        Verbose("Found $n $adj test $text for $test_name; trimming to $num_to_save\n");
        sort _timestamp_compare $data;
        for (my $i = $#$data - $num_to_save; $i >= 0; --$i) {
            my $f = $$data[$i];
            Verbose("Trimming test run: [$f->{mpi_get}] / [$f->{mpi_version}] / [$f->{mpi_install}] / [$f->{test_build}] / [$f->{test_run_name}]\n");

            # Mark this tree in the hash for deletion
            $f->{test_run_data}->{$MTT::Trim::TRIM_KEY} = 1;

            # Decrement the refcount on the corresponding test build
            --$MTT::Test::builds->{$f->{mpi_get}}->{$f->{mpi_version}}->{$f->{mpi_install}}->{$f->{test_build}}->{refcount};
            
        }
    } else {
        Verbose("Found $n $adj test $text for $test_name; no trim necessary ($num_to_save)\n");
    }
}

#--------------------------------------------------------------------------

sub _trim_test_builds {
    my $install_dir = shift;

    # In this step, we're:

    # 1. Decreasing refcounts on MTT::Test::sources and
    #    MTT::MPI::installs
    # 2. Removing data from MTT::Test::builds

    # General algorithm:

    # - Do for {successful, failed} builds
    #   - Find them and put them in timestamp order
    #   - Save the most recent N (number to be saved)
    #   - Save all after N that have (refcount!=0)
    #   - Mark the rest for deletion
    #     - Decrement refcount on corresponding MPI install and Test get
    #     - "rm -rf" the appropriate directories
    #     - Delete from the MTT::Test::builds hash

    my $successful;
    my $failed;

    # For each MPI source
    foreach my $get_key (keys(%{$MTT::Test::builds})) {
        my $get = $MTT::Test::builds->{$get_key};

        foreach my $version_key (keys(%{$get})) {
            my $version = $get->{$version_key};

            foreach my $install_key (keys(%{$version})) {
                my $install = $version->{$install_key};

                foreach my $build_key (keys(%{$install})) {
                    my $build = $install->{$build_key};

                    # Make one record for all the tests in this run
                    # (this effectively groups all the tests from one
                    # section of the INI file).

                    my $item = {
                        timestamp => $build->{start_timestamp},
                        test_build_name => $build_key,
                        test_build_data => $build,

                        # Information used to decrement parent refcounts
                        mpi_get => $get_key,
                        mpi_version => $version_key,
                        mpi_install => $install_key,
                        test_get => $build->{test_get_simple_section_name},
                    };
                    if (MTT::Test::PASS == $build->{test_result}) {
                        push(@{$successful->{$build_key}}, $item);
                    } else {
                        push(@{$failed->{$build_key}}, $item);
                    }
                }
            }
        }
    }

    # For each test build section, sort them so that the oldest is
    # first and the youngest is last.  Then trim accordingly.

    # First do the successes
    foreach my $build_key (keys(%{$successful})) {
        my $successes = $successful->{$build_key};
        _trim_test_build_work("successful", $build_key, $successes, 
                              $MTT::Globals::Values->{save_successful_test_builds});
    }

    # Then do the failures
    foreach my $build_key (keys(%{$failed})) {
        my $fails = $failed->{$build_key};
        _trim_test_build_work("failed", $build_key, $fails, 
                              $MTT::Globals::Values->{save_failed_test_builds});
    }


    # Now go save the trimmed test builds meta data
    MTT::Test::SaveBuilds($install_dir);
}

#--------------------------------------------------------------------------

sub _trim_test_build_work {
    my ($adj, $test_name, $data, $num_to_save) = @_;
    my $n = $#$data + 1;
    my $text = "build";
    $text .= "s"
        if ($n > 1);

    if ($n > $num_to_save) {
        Verbose("Found $n $adj test $text for $test_name; trimming to $num_to_save\n");
        sort _timestamp_compare $data;
        for (my $i = $#$data - $num_to_save; $i >= 0; --$i) {
            my $f = $$data[$i];
            Verbose("Trimming test build: [$f->{mpi_get}] / [$f->{mpi_version}] / [$f->{mpi_install}] / [$f->{test_build_name}]\n");

            # Decrement the refcount on the corresponding test get
            --$MTT::Test::sources->{$f->{test_get}}->{refcount};

            # Decrement the refcount on the corresponding MPI install
            --$MTT::MPI::installs->{$f->{mpi_get}}->{$f->{mpi_version}}->{$f->{mpi_install}}->{refcount};

            # Delete the corresponding files in the filesystem
            my $d = dirname($f->{test_build_data}->{srcdir});
            MTT::DoCommand::Cmd(0, "rm -rf $d");
            # Then just try to rmdir the parent directory (which will
            # be named "tests").  If the parent is empty (i.e., if
            # this was the last test section in it), it'll be removed.
            rmdir(dirname($d));

            # Delete this data from the MTT::Test::builds hash
            delete $MTT::Test::builds->{$f->{mpi_get}}->{$f->{mpi_version}}->{$f->{mpi_install}}->{$f->{test_build_name}};
            # Go up the hierarchy in the hash and see if there are now
            # keys that have no children.  If so, delete them.
            my @k = keys(%{$MTT::Test::builds->{$f->{mpi_get}}->{$f->{mpi_version}}->{$f->{mpi_install}}});
            if ($#k < 0) {
                delete $MTT::Test::builds->{$f->{mpi_get}}->{$f->{mpi_version}}->{$f->{mpi_install}};

                # Grandparent
                @k = keys(%{$MTT::Test::builds->{$f->{mpi_get}}->{$f->{mpi_version}}});
                if ($#k < 0) {
                    delete $MTT::Test::builds->{$f->{mpi_get}}->{$f->{mpi_version}};
                    # Great-grandparent
                    @k = keys(%{$MTT::Test::builds->{$f->{mpi_get}}});
                    if ($#k < 0) {
                        delete $MTT::Test::builds->{$f->{mpi_get}};
                    }
                }
            }
        }
    } else {
        Verbose("Found $n $adj test $text for $test_name; no trim necessary ($num_to_save)\n");
    }
}

#--------------------------------------------------------------------------

sub _trim_test_gets {
    my $source_dir = shift;
}

#--------------------------------------------------------------------------

sub _trim_mpi_installs {
    my $install_dir = shift;
}

#--------------------------------------------------------------------------

sub _trim_mpi_gets {
    my $source_dir = shift;
}

#--------------------------------------------------------------------------

sub _timestamp_compare {
    my ($a, $b) = @_;
    return ($a->{timestamp} - $b->{timestamp});
}

1;
