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

package MTT::Test::Build::NPB_OMPI_Tests;

use strict;
use Cwd;
use MTT::Messages;
use MTT::DoCommand;
use MTT::Values;
use MTT::Files;
use Data::Dumper;

#--------------------------------------------------------------------------
# module
sub Build {
    my ($ini, $mpi_install, $config) = @_;
    my $ret;

    Debug("Building NPB_ompi_tests\n");
    $ret->{success} = 0;

    # Clean it (just to be sure)
    MTT::DoCommand::Chdir("NPB2.3-MPI");
    my $x = MTT::DoCommand::Cmd($config->{merge_stdout_stderr}, "make clean");
    if ($x->{status} != 0) {
        $ret->{result_message} = "NPB_ompi_tests: make clean failed; skipping";
        $ret->{result_stdout} = $x->{result_stdout};
        $ret->{result_stderr} = $x->{result_stderr};
        return $ret;
    }
    MTT::Files::mkdir("bin") if (! -x "bin");

    # Check for "npbs" field.  If this exists, use that as a list of
    # suffices to "benchmarks_<suffix>", "classes_<suffix>",
    # "nprocs_<suffix>", "skip_<suffix>".  If it doesn't exist, only
    # look for "benchmarks", "classes", "nprocs", and "skip".

    my $npbs = Value($ini, $config->{section_name}, "npb_ompi_tests");
    if ($npbs) {
        # Did we get a single string, or an array?
        if (ref($npbs) eq "") {
            $x = _build($ini, $config->{section_name}, 
                        $config->{merge_stdout_stderr},
                        "benchmarks_$npbs",
                        "classes_$npbs", "nprocs_$npbs");
        } else {
            foreach my $n (@$npbs) {
                $x = _build($ini, $config->{section_name},
                            $config->{merge_stdout_stderr},
                            "benchmarks_$n",
                            "classes_$n", "nprocs_$n");
                if (0 == $x->{status}) {
                    last;
                }
            }
        }
    } else {
        # There was no "npbs" field, so just use the naked field names
        # with no suffix
        $x = _build($ini, $config->{section_name}, 
                    $config->{merge_stdout_stderr},
                    "benchmarks", "classes", "nprocs");
    }
    if (0 == $x->{status}) {
        $ret->{success} = 0;
        $ret->{result_message} = $x->{result_message};
        $ret->{result_stdout} = $x->{result_stdout};
    } else {
        $ret->{success} = 1;
        $ret->{result_message} = "Success";
    }
    return $ret;
} 

sub _build {
    my ($ini, $section, $merge, $bm_arg, $cl_arg, $np_arg) = @_;

    my $ret;
    my $benchmarks = Value($ini, $section, $bm_arg);
    my $classes = Value($ini, $section, $cl_arg);
    my $nprocs = Value($ini, $section, $np_arg);

    if (!$benchmarks || !$classes || !$nprocs) {
        Warning("Could not find all three fields (benchmarks, classes, nprocs) with a common suffix ($bm_arg)\n");
        return;
    }

    foreach my $bm (@$benchmarks) {
        foreach my $cl (@$classes) {
            foreach my $np (@$nprocs) {
                my $cmd = "make $bm CLASS=$cl NPROCS=$np";
                my $x = MTT::DoCommand::Cmd($merge, $cmd);
                if ($x->{status} != 0) {
                    $ret->{success} = 0;
                    $ret->{result_message} =
                        "NPB_ompi_tests: $cmd failed; aborting";
                    $ret->{result_stdout} = $x->{result_stdout};
                    return $ret;
                }
            }
        }
    }
    $ret->{success} = 1;
    return $ret;
}

1;
