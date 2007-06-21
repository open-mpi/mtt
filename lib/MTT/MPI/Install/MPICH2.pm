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

package MTT::MPI::Install::MPICH2;

use strict;
use Cwd;
use Data::Dumper;
use MTT::DoCommand;
use MTT::Messages;
use MTT::FindProgram;
use MTT::Values;
use MTT::Files;
use MTT::Common::GNU_Install;

#--------------------------------------------------------------------------

sub _find_bindings {
    my ($bindir, $lang) = @_;

    open INFO, "$bindir/mpich2version|";
    my @file = grep { /^$lang/ } <INFO>;
    chomp @file;
    close INFO;

    $file[0] =~ s/^$lang\s*//g;
    return ("" ne $file[0]) ? "1" : "0";
}

#--------------------------------------------------------------------------

sub _find_bitness {
    my ($bindir) = @_;

    # JMS still need to write this
    return "64";
}

#--------------------------------------------------------------------------

sub _adjust_wrapper {
    my ($wrapper, $field, $value) = @_;
    print "Adjusting wrapper: $wrapper / $field / $value\n";
    if (-f $wrapper && open(WIN, $wrapper) && open(WOUT, ">$wrapper.new")) {
        while (<WIN>) {
            if (m/^$field="(.+)"/) {
                print WOUT "$field=\"$1 $value\"\n";
            } else {
                print WOUT $_;
            }
        }
        close(WIN);
        close(WOUT);
        system("cp $wrapper.new $wrapper");
        unlink("$wrapper.new");
   }
}

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

    # Get some MPICH2-module-specific config arguments

    my $tmp;
    $tmp = Value($ini, $section, "mpich2_make_all_arguments");
    $config->{make_all_arguments} = $tmp
        if (defined($tmp));

    $config->{compiler_name} =
        Value($ini, $section, "mpich2_compiler_name");
    if ($MTT::Defaults::System_config->{known_compiler_names} !~ /$config->{compiler_name}/) {
        Warning("Unrecognized compiler name in [$section] ($config->{compiler_name}); the only permitted names are: \"$MTT::Defaults::System_config->{known_compiler_names}\"; skipped\n");
        return;
    }
    $config->{compiler_version} =
        Value($ini, $section, "mpich2_compiler_version");

    $tmp = Value($ini, $section, "mpich2_configure_arguments");
    $config->{configure_arguments} = $tmp
        if (defined($tmp));

    $config->{make_check} = 0;

    # Run configure / make all / make check / make install

    my $gnu = {
        configdir => $config->{configdir},
        configure_arguments => $config->{configure_arguments},
        vpath => "no",
        installdir => $config->{installdir},
        bindir => $config->{bindir},
        libdir => $config->{libdir},
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
    $ret->{cxx_bindings} = _find_bindings($ret->{bindir}, "CXX:");
    Debug("Have C++ bindings: $ret->{cxx_bindings}\n"); 
    $ret->{f77_bindings} = _find_bindings($ret->{bindir}, "F77:");
    Debug("Have F77 bindings: $ret->{f77_bindings}\n"); 
    $ret->{f90_bindings} = _find_bindings($ret->{bindir}, "F90:");
    Debug("Have F90 bindings: $ret->{f90_bindings}\n"); 

    # Are we adjusting the wrapper compilers?

    my $tmp1;
    my $tmp2;
    $tmp1 = Value($ini, $section, "mpich2_additional_wrapper_ldflags");
    $tmp2 = Value($ini, $section, "mpich2_additional_wrapper_libs");
    $tmp = "";
    $tmp = $tmp1
        if (defined($tmp1));
    $tmp .= " $tmp2"
        if (defined($tmp2));
    if ("" ne $tmp) {
        my $b = $ret->{bindir};
        _adjust_wrapper("$b/mpicc", "MPI_LDFLAGS", $tmp);
        _adjust_wrapper("$b/mpicxx", "MPI_LDFLAGS", $tmp);
        _adjust_wrapper("$b/mpif77", "MPI_LDFLAGS", $tmp);
        _adjust_wrapper("$b/mpif90", "MPI_LDFLAGS", $tmp);
    }

    # Calculate bitness (must be processed *after* installation)

    $config->{bitness} = _find_bitness($ret->{bindir});

    # Done!

    $ret->{test_result} = MTT::Values::PASS;
    $ret->{result_message} = "Success";
    $ret->{exit_status} = $x->{exit_status};
    Debug("Build was a success\n");

    return $ret;
} 


1;
