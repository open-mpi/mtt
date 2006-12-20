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
use MTT::Messages;
use MTT::Values;

#--------------------------------------------------------------------------

# Trim old trees after a run
sub Trim {
    my ($ini) = @_;

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

    _trim_runs();
    _trim_builds();
    _trim_installs();
    _trim_gets();

    Verbose("*** Trim phase complete\n");
}

#--------------------------------------------------------------------------

sub _trim_runs {

    # In this step, we're:

    # 1. Decreasing refcounts on MTT::Test::builds
    # 2. Removing data from MTT::Test::runs (and removing their
    #    corresponding back-end data files)

    # For each run, we declare it successful if *all* of its tests
    # passed.  Otherwise, it's classified as failed.

    my @successful;
    my @failed;

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
                            run => $run,
                        };
                        if ($succeeded) {
                            push(@successful, $item);
                        } else {
                            push(@failed, $item);
                        }
                    }
                }
            }
        }
    }

    # Now we've got them all -- sort so that the oldest is first and
    # the youngest is last.

    Verbose("Successful test runs: $#successful\n");
    Verbose("Failed test runs: $#failed\n");
    sort _run_compare @successful;
    _run_remove($MTT::Globals::Values->{test_run_save_successful}, 
                \@successful);
    sort _run_compare @failed;
    _run_remove($MTT::Globals::Values->{test_run_save_failed}, \@failed);
}

#--------------------------------------------------------------------------

sub _run_compare {
    my ($a, $b) = @_;
    return ($a->{timestamp} - $b->{timestamp});
}

#--------------------------------------------------------------------------

sub _run_remove {
    my ($num_to_save, $entries) = @_;

    print "Entries: $#$entries -- saving $num_to_save\n";
#    my $d = new Data::Dumper($entries);
#    $d->Purity(1)->Indent(1);
#    print "TRIM ENTRIES\n" . $d->Dump;
    for (my $i = $#$entries - $num_to_save; $i >= 0; $i--) {
#        print Dumper($$entries[$i]);
#        print "$i: rm -rf " . $$entries[$i]->{$name} . "\n";
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
