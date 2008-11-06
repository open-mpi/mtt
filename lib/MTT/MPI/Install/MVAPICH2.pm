#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006-2008 Cisco Systems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::MPI::Install::MVAPICH2;

use strict;
use Data::Dumper;
use MTT::DoCommand;
use MTT::Messages;
use MTT::FindProgram;
use MTT::Values;
use MTT::Files;
use MTT::Common::GNU_Install;

#--------------------------------------------------------------------------

sub Install {
    my ($ini, $section, $config) = @_;
    my $x;
    my $result_stdout;
    my $result_stderr;

    # Prepare $ret

    my $ret;
    $ret->{test_result} = MTT::Values::FAIL;
    $ret->{exit_status} = 0;
    $ret->{installdir} = $config->{installdir};
    $ret->{bindir} = "$ret->{installdir}/bin";
    $ret->{libdir} = "$ret->{installdir}/lib";

    # Get some MVAPICH2-module-specific config arguments

    my $tmp;
    $tmp = Value($ini, $section, "mvapich2_make_all_arguments");
    $config->{make_all_arguments} = $tmp
        if (defined($tmp));

    # JMS: compiler name may have come in from "compiler_name"in
    # Install.pm.  So if we didn't define one for this module, use the
    # default from "compiler_name".  Note: to be deleted someday
    # (i.e., only rely on this module's compiler_name and not use a
    # higher-level default, per #222).
    $tmp = Value($ini, $section, "mvapich2_compiler_name");
    $config->{compiler_name} = $tmp
        if (defined($tmp));
    return undef
        if (!MTT::Util::is_valid_compiler_name($section, 
                                               $config->{compiler_name}));
    $config->{compiler_version} =
        Value($ini, $section, "mvapich2_compiler_version");

    # Need to specify an MVAPICH build script
    my $build_script =
        Value($ini, $section, "mvapich2_build_script");
    if (!defined($build_script)) {
        Warning("Build script not defined for mvapich2 module; skipping");
        return undef;
    }

    # Get any environment variables that were specified
    my %ENV_SAVE = %ENV;
    $tmp = Value($ini, $section, "mvapich2_setenv");
    if (defined($tmp)) {
        my @vals = split(/\n/, $tmp);
        foreach my $v (@vals) {
            $v =~ m/^(\w+)\s+(.+)$/;
            $ENV{$1} = $2;
            Debug("Setenv MVAPICH2 env var: $1 = $ENV{$1}\n");
        }
    }

    # We know that we need to specify prefix
    $ENV{'PREFIX'} = $config->{installdir};

    my $x = MTT::DoCommand::Cmd(1, "$config->{configdir}/$build_script", -1, $config->{stdout_save_lines}, $config->{stderr_save_lines});
    %ENV = %ENV_SAVE;
    
    if (!MTT::DoCommand::wsuccess($x->{exit_status})) {
        $ret->{result_message} = "MVAPICH build script failed -- skipping this build";
        # Put the output of the failure into $ret so that it gets
        # reported (result_stdout/result_stderr was combined into
        # just result_stdout)
        $ret->{result_stdout} = $x->{result_stdout};
        $ret->{exit_status} = $x->{exit_status};
        $ret->{fail} = 1;
        return $ret;
    }

    # Set which bindings were compiled

    $ret->{c_bindings} = 1;
    Debug("Have C bindings: 1\n");
    my $func = \&MTT::Values::Functions::MPI::MPICH2::find_bindings;
    $ret->{cxx_bindings} = &{$func}($ret->{bindir}, "CXX:");
    Debug("Have C++ bindings: $ret->{cxx_bindings}\n"); 
    $ret->{f77_bindings} = &{$func}($ret->{bindir}, "F77:");
    Debug("Have F77 bindings: $ret->{f77_bindings}\n"); 
    $ret->{f90_bindings} = &{$func}($ret->{bindir}, "F90:");
    Debug("Have F90 bindings: $ret->{f90_bindings}\n"); 

    # Are we adjusting the wrapper compilers?

    my $tmp1;
    my $tmp2;
    $tmp1 = Value($ini, $section, "mvapich2_additional_wrapper_ldflags");
    $tmp2 = Value($ini, $section, "mvapich2_additional_wrapper_libs");
    $tmp = "";
    $tmp = $tmp1
        if (defined($tmp1));
    $tmp .= " $tmp2"
        if (defined($tmp2));
    if ("" ne $tmp) {
        my $b = $ret->{bindir};
        my $func = \&MTT::Values::Functions::MPI::MPICH2::adjust_wrapper;
        &{$func}("$b/mpicc", "MPI_LDFLAGS", $tmp);
        &{$func}("$b/mpicxx", "MPI_LDFLAGS", $tmp);
        &{$func}("$b/mpif77", "MPI_LDFLAGS", $tmp);
        &{$func}("$b/mpif90", "MPI_LDFLAGS", $tmp);
    }

    # Calculate bitness (must be processed *after* installation)

    my $func = \&MTT::Values::Functions::MPI::MPICH2::find_bitness;
    $config->{bitness} = &{$func}($ret->{bindir});

    # Done!

    $ret->{test_result} = MTT::Values::PASS;
    $ret->{result_message} = "Success";
    $ret->{exit_status} = $x->{exit_status};
    Debug("Build was a success\n");

    return $ret;
} 


1;
