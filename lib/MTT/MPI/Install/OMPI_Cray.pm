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

package MTT::MPI::Install::OMPI_Cray;

use strict;
use Cwd;
use Data::Dumper;
use MTT::DoCommand;
use MTT::Messages;
use MTT::FindProgram;
use MTT::Values;
use MTT::Files;
use MTT::Common::GNU_Install;
use MTT::Values::Functions::MPI::OMPI;

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
    $ret->{installdir} .= "/$config->{mpi_version}/ompi/$config->{compiler_variant}";
    $ret->{bindir} = "$config->{installdir}/bin"; 
    $ret->{libdir} = "$config->{installdir}/lib"; 

    # Cray requires MPICHBASEDIR to be set to the installdir up until
    # and including the "ompi" subdir, but not the compiler variant (!).
    # JMS ...need to continue here

    # Get some OMPI-Cray-module-specific config arguments

    my $tmp;
    $tmp = Value($ini, $section, "ompi_cray_make_all_arguments");
    $config->{make_all_arguments} = $tmp
        if (defined($tmp));

    # JMS: compiler name may have come in from "compiler_name"in
    # Install.pm.  So if we didn't define one for this module, use the
    # default from "compiler_name".  Note: to be deleted someday
    # (i.e., only rely on this module's compiler_name and not use a
    # higher-level default, per #222).
    $tmp = Value($ini, $section, "ompi_cray_compiler_name");
    $config->{compiler_name} = $tmp
        if (defined($tmp));
    return 
        if (!MTT::Util::is_valid_compiler_name($section, 
                                               $config->{compiler_name}));

    $tmp = Value($ini, $section, "ompi_cray_mpi_version");
    if (!defined($tmp)) {
	$tmp = "unknown_mpi_version";
    }
    $config->{mpi_version} = $tmp;
    $tmp = Value($ini, $section, "ompi_cray_compiler_variant");
    if (!defined($tmp)) {
	$tmp = "P2";
    }
    $config->{compiler_variant} = $tmp;

    # JMS: Same as above
    $tmp = Value($ini, $section, "ompi_cray_compiler_version");
    $config->{compiler_version} = $tmp
        if (defined($tmp));

    $tmp = Value($ini, $section, "ompi_cray_configure_arguments");
    $tmp =~ s/\n|\r/ /g;
    $config->{configure_arguments} = $tmp
        if (defined($tmp));

    $tmp = Logical($ini, $section, "ompi_cray_make_check");
    $config->{make_check} = $tmp
        if (defined($tmp));

    # Run configure / make all / make check / make install

    my $gnu = {
        configdir => $config->{configdir},
        configure_arguments => $config->{configure_arguments},
        vpath => "no",
        installdir => $ret->{installdir},
        bindir => $ret->{bindir},
        libdir => $ret->{libdir},
        make_all_arguments => $config->{make_all_arguments},
        make_check => $config->{make_check},
        stdout_save_lines => $config->{stdout_save_lines},
        stderr_save_lines => $config->{stderr_save_lines},
        merge_stdout_stderr => $config->{merge_stdout_stderr},
    };
    my $install = MTT::Common::GNU_Install::Install($gnu);
    foreach my $k (keys(%{$install})) {
        $ret->{$k} = $install->{$k};
    }
    return $ret
        if (exists($ret->{fail}));

    # Set which bindings were compiled

    $ret->{c_bindings} = 1;
    Debug("Have C bindings: 1\n");
    my $func = \&MTT::Values::Functions::MPI::OMPI::find_bindings;
    $ret->{cxx_bindings} = &{$func}($ret->{bindir}, $ret->{libdir}, "cxx");
    Debug("Have C++ bindings: $ret->{cxx_bindings}\n"); 
    $ret->{f77_bindings} = &{$func}($ret->{bindir}, $ret->{libdir}, "f77");
    Debug("Have F77 bindings: $ret->{f77_bindings}\n"); 
    $ret->{f90_bindings} = &{$func}($ret->{bindir}, $ret->{libdir}, "f90");
    Debug("Have F90 bindings: $ret->{f90_bindings}\n"); 

    # Calculate bitness (must be processed *after* installation)

    my $func = \&MTT::Values::Functions::MPI::OMPI::find_bitness;
    $config->{bitness} = &{$func}($ret->{bindir}, $ret->{libdir});

    # Write out the OMPI cleanup script and be done.

    $ret->{test_result} = MTT::Values::PASS;
    $ret->{result_message} = "Success";
    $ret->{exit_status} = $x->{exit_status};
    Debug("Build was a success\n");

    return $ret;
} 

1;
