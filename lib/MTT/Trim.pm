#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006-2007 Cisco Systems, Inc.  All rights reserved.
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
use MTT::DoCommand;

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

    # General algorithm for trim:

    # 1. The units of trimming are in terms of "MPI get"s.  If any
    # test from any phase stemming from an individual MPI get fails,
    # the entire "MPI get" is deemed a failure.  Otherwise, it is
    # deemed a success.

    # 2. Trim the last N successes and M failures, meaning keep only
    # the last N success and M failure chains.  Remove all others
    # (i.e., remove *everything* that stemmed from trimmed MPI gets --
    # the corresponding MPI installs, test builds, and test runs).

    # 3. For failures that are kept, trim the successful sub-parts
    # (this helps keep disk utilization down).  Since you can view MTT
    # phases as a tree, simply trim out any sub trees that contain
    # only successes.  This helps limit disk space that is used.

    # 4. Trimming occurs on a per-MPI-get-section basis (i.e., all the
    # versions for a particular MPI get are grouped together and then
    # trimmed accordingly).

    my $succeeded;
    my $failed;

    # For each MPI get
    foreach my $get_key (keys(%{$MTT::MPI::sources})) {
        my $get = $MTT::MPI::sources->{$get_key};
        Debug("=== trimming mpi get: $get_key\n");

        # Flag indicating whether *everything* in this version of the
        # MPI get succeeded or not.
        my $successful = 1;

        # For each version of each MPI get
        foreach my $version_key (keys(%{$get})) {
            my $version = $get->{$version_key};
            my $timestamp = time;

            # For each installation of that MPI version
            foreach my $install_key (keys(%{$MTT::MPI::installs->{$get_key}->{$version_key}})) {
                my $install = $MTT::MPI::installs->{$get_key}->{$version_key}->{$install_key};

                # Was the install successful?
                if (MTT::Values::PASS != $install->{test_result}) {
                    Debug("  MPI install failed: $version_key / $install_key\n");
                    $successful = 0;
                    last;
                }

                # For each test build that used that MPI version
                foreach my $build_key (keys(%{$MTT::Test::builds->{$get_key}->{$version_key}->{$install_key}})) {
                    my $build = $MTT::Test::builds->{$get_key}->{$version_key}->{$install_key}->{$build_key};

                    # Was the build successful?
                    if (MTT::Values::PASS != $build->{test_result}) {
                        Debug("  Test build failed: $version_key / $install_key / $build_key\n");
                        $successful = 0;
                        last;
                    }

                    # For each run section that used that test build
                    foreach my $run_key (keys(%{$MTT::Test::runs->{$get_key}->{$version_key}->{$install_key}->{$build_key}})) {
                        my $run = $MTT::Test::runs->{$get_key}->{$version_key}->{$install_key}->{$build_key}->{$run_key};

                        # For each test in that run section
                        foreach my $test_key (keys(%{$run})) {
                            my $test = $run->{$test_key};

                            # For each NP value in that test
                            foreach my $np_key (keys(%{$test})) {
                                my $np = $test->{$np_key};

                                # For each variant in that NP value
                                foreach my $cmd_key (keys(%{$np})) {
                                    my $cmd = $np->{$cmd_key};

                                    # Did this individual test pass?
                                    if (MTT::Values::PASS !=
                                        $cmd->{test_result}) {
                                        Debug("  Test run failed: $get_key / $version_key / $install_key / $build_key / $run_key / $test_key / $np_key / $cmd_key\n");
                                        $successful = 0;
                                        last;
                                    }
                                }

                                # If we were not successful in a
                                # deeper level, there's no point in
                                # continuing
                                last if (!$successful);
                            }

                            # If we were not successful in a deeper
                            # level, there's no point in continuing
                            last if (!$successful);
                        }

                        # If we were not successful in a deeper level,
                        # there's no point in continuing
                        last if (!$successful);
                    }

                    # If we were not successful in a deeper level,
                    # there's no point in continuing
                    last if (!$successful);
                }

                # If we were not successful in a deeper level, there's
                # no point in continuing
                last if (!$successful);
            }

            my $item = {
                timestamp => $MTT::MPI::sources->{$get_key}->{$version_key}->{start_timestamp},
                get => $get,
                version => $version,

                get_key => $get_key,
                version_key => $version_key,
            };
            # Save this version in the relevant list
            if ($successful) {
                Debug("THIS VERSION CHAIN PASSED: $get_key / $version_key\n");
                push(@{$succeeded->{$get_key}}, $item);
            } else {
                Debug("THIS VERSION CHAIN FAILED: $get_key / $version_key\n");
                push(@{$failed->{$get_key}}, $item);
            }
        }
    }

    # Remove trimmed successes
    foreach my $key (keys(%{$succeeded})) {
        sort _timestamp_compare $succeeded->{$key};
        for (my $i = $#{$succeeded->{$key}} - 
             $MTT::Globals::Values->{trim_save_successful};
             $i >= 0; --$i) {
            my $item = ${$succeeded->{$key}}[$i];
            _trim_mpi_install($item, 1);
        }
    }

    # Remove trimmed failures
    foreach my $key (keys(%{$failed})) {
        sort _timestamp_compare $failed->{$key};
        for (my $i = $#{$failed->{$key}} - 
             $MTT::Globals::Values->{trim_save_failed};
             $i >= 0; --$i) {
            my $item = $$failed->{$key}[$i];
            _trim_mpi_install($item, 1);
        }

        # For the failures that we're saving, trim the successful sub-trees
        for (my $i = 0; $i < $MTT::Globals::Values->{trim_save_failed}; ++$i) {
            my $item = $$failed->{$key}[$i];
            _trim_mpi_install($item, 0);
        }
    }

    # Directories have been deleted and meta data tables have been
    # updated.  Re-save all the meta-data.
    MTT::MPI::SaveSources();
    MTT::MPI::SaveInstalls();
    MTT::Test::SaveSources();
    MTT::Test::SaveBuilds();
    MTT::Test::TrimRuns();

    # All done
    Verbose("*** Trim phase complete\n");
}

#--------------------------------------------------------------------------

sub _trim_mpi_get {
    my ($item) = @_;

    Debug("=== Trimming mpi get\n");
    # JMS Continue here
    Debug("=== Trimming mpi get done\n");
}

#--------------------------------------------------------------------------

# We always trim successfull sub-trees.  The question is whether the
# caller wants us to trim failed sub-trees or not.
sub _trim_mpi_install {
    my ($item, $want_trim_failed) = @_;

    Debug("=== Trimming mpi install\n");
    my $data_still_in_tree = 0;
    Verbose("   Trimming mpi install: [$item->{get_key}] / [$item->{version_key}]\n");

    # For each installation of that MPI version
    foreach my $install_key (keys(%{$MTT::MPI::installs->{$item->{get_key}}->{$item->{version_key}}})) {
        my $install = $MTT::MPI::installs->{$item->{get_key}}->{$item->{version_key}}->{$install_key};

        # Deep copy the item and add some more fields
        my $derived_item;
        %{$derived_item} = %{$item};
        $derived_item->{install} = $install;
        $derived_item->{install_key} = $install_key;

        my $children_still_exist = 
            _trim_test_build($derived_item, $want_trim_failed);

        # If there's nothing left in the tree, this item is eligible
        # for trimming
        if (!$children_still_exist) {
            if (MTT::Values::PASS == $install->{test_result} ||
                $want_trim_failed) {
                # Ok, trim it.

                _trim_mpi_get($item);

                # Delete the directories associated with the MPI install
                DebugDump($install);
                MTT::DoCommand::Cmd(0, "rm -rf $install->{version_dir}");

                # These rmdir()'s will succeed if they are empty
                # (i.e., this is the last directory in the tree),
                # otherwise they'll fail (which is ok, because there
                # are still subdirs lieft).
                rmdir($install->{install_section_dir});
                rmdir($install->{get_section_dir});

                # Delete data from the hash tree
                delete $MTT::MPI::installs->{$item->{get_key}}->{$item->{version_key}}->{$install_key};

                # If the version_key had no other children, whack it
                # as well
                my @tmp = keys(%{$MTT::MPI::installs->{$item->{get_key}}->{$item->{version_key}}});
                if ($#tmp < 0) {
                    delete $MTT::MPI::installs->{$item->{get_key}}->{$item->{version_key}};
                    # If the get_key had no other children, whack it
                    # as well
                    my @tmp = keys(%{$MTT::MPI::installs->{$item->{get_key}}});
                    if ($#tmp < 0) {
                        delete $MTT::MPI::installs->{$item->{get_key}};
                    }
                }
            }
        } else {
            $data_still_in_tree = 1;
        }
    }

    if ($data_still_in_tree) {
        Verbose("   --> Some data still exists for manual examination\n");
    }
    Debug("=== Trimming mpi install done: data still in tree - $data_still_in_tree\n");
    return $data_still_in_tree;
}

#--------------------------------------------------------------------------

sub _trim_test_get {
    my ($f, $want_trim_failed, $install) = @_;

    Debug("=== Trimming test get\n");
# JMS continue here
    Debug("=== Trimming test get done\n");
}

#--------------------------------------------------------------------------

sub _trim_test_build {
    my ($item, $want_trim_failed) = @_;

    my $data_still_in_tree = 0;
    Debug("=== Trimming test build\n");
#    DebugDump($item);

    foreach my $build_key (keys(%{$MTT::Test::builds->{$item->{get_key}}->{$item->{version_key}}->{$item->{install_key}}})) {
        my $build = $MTT::Test::builds->{$item->{get_key}}->{$item->{version_key}}->{$item->{install_key}}->{$build_key};

        # Deep copy the item and add some more fields
        my $derived_item;
        %{$derived_item} = %{$item};
        $derived_item->{build} = $build;
        $derived_item->{build_key} = $build_key;

        my $children_still_exist = 
            _trim_test_run($derived_item, $want_trim_failed);

        # If there's nothing left in the tree, this item is eligible
        # for trimming
        if (!$children_still_exist) {
            if (MTT::Values::PASS == $build->{test_result} || 
                $want_trim_failed) {
                # Ok, trim it.

                _trim_test_get($item);

                # Delete the directories associated with the Test build
                my $d = dirname($build->{srcdir});
                MTT::DoCommand::Cmd(0, "rm -rf $d");
                
                # These rmdir()'s will succeed if they are empty
                # (i.e., this is the last directory in the tree),
                # otherwise they'll fail (which is ok, because there
                # are still subdirs lieft).
                rmdir(dirname($d));

                # Delete data from the hash tree
                delete $MTT::Test::builds->{$item->{get_key}}->{$item->{version_key}}->{$item->{install_key}}->{$build_key};

                # If the install_key had no other children, whack it
                # as well
                my @tmp = keys(%{$MTT::Test::builds->{$item->{get_key}}->{$item->{version_key}}->{$item->{install_key}}});
                if ($#tmp < 0) {
                    delete $MTT::Test::builds->{$item->{get_key}}->{$item->{version_key}}->{$item->{install_key}};

                    # If the version_key had no other children, whack
                    # it as well
                    @tmp = keys(%{$MTT::Test::builds->{$item->{get_key}}->{$item->{version_key}}});
                    if ($#tmp < 0) {
                        delete $MTT::Test::builds->{$item->{get_key}}->{$item->{version_key}};

                        # If the get_key had no other children,
                        # whack it as well
                        @tmp = keys(%{$MTT::Test::builds->{$item->{get_key}}});
                        if ($#tmp < 0) {
                            delete $MTT::Test::builds->{$item->{get_key}};
                        }
                    }
                }
            }
        } else {
            $data_still_in_tree = 1;
        }
    }

    Debug("=== Trimming test build done: data still in tree - $data_still_in_tree\n");
    return $data_still_in_tree;
}

#--------------------------------------------------------------------------

sub _trim_test_run {
    my ($item, $want_trim_failed) = @_;

    Debug("=== Trimming test run\n");
    my $data_still_in_tree = 0;
#    DebugDump($item);

    foreach my $run_key (keys(%{$MTT::Test::runs->{$item->{get_key}}->{$item->{version_key}}->{$item->{install_key}}->{$item->{build_key}}})) {
        my $run = $MTT::Test::runs->{$item->{get_key}}->{$item->{version_key}}->{$item->{install_key}}->{$item->{build_key}}->{$run_key};

        my $ok_to_trim = 1;

        # For each test in that run section
        foreach my $test_key (keys(%{$run})) {
            my $test = $run->{$test_key};

            # For each NP value in that test
            foreach my $np_key (keys(%{$test})) {
                my $np = $test->{$np_key};

                # For each variant in that NP value
                foreach my $cmd_key (keys(%{$np})) {
                    my $cmd = $np->{$cmd_key};

                    # Is this test eligible for trimming?
                    if (MTT::Values::PASS == $cmd->{test_result} ||
                        MTT::Values::SKIPPED == $cmd->{test_result} ||
                        $want_trim_failed) {
                        # Ok, trim it.

                        next;
                    } else {
                        $ok_to_trim = 0;
                    }
                }
            }
        }

        # Were all the tests successful?  If so, set the trim key to
        # 1.  Because test run data is not stored in a single meta
        # data file, we have to mark the trees in the MTT::Test::runs
        # hash that we want deleted and then call a back-end function
        # (in MTT::Test) to do the actual deletion.

        if ($ok_to_trim) {
            $run->{$MTT::Trim::TRIM_KEY} = 1;
        } else {
            $data_still_in_tree = 1;
        }
    }

    Debug("=== Trimming test run done: data still in tree - $data_still_in_tree\n");
    return $data_still_in_tree;
}

#--------------------------------------------------------------------------

sub _timestamp_compare {
    my ($a, $b) = @_;
    return ($a->{timestamp} - $b->{timestamp});
}

1;
