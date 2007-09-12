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

package MTT::MPI::Install::LAM;

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

sub _run_laminfo {
    my ($bindir, $libdir, $grep_string) = @_;


    my %ENV_SAVE = %ENV;
    if (exists($ENV{LD_LIBRARY_PATH})) {
        $ENV{LD_LIBRARY_PATH} = "$libdir:$ENV{LD_LIBRARY_PATH}";
    } else {
        $ENV{LD_LIBRARY_PATH} = "$libdir";
    }

    open INFO, "$bindir/laminfo -all -parsable|";
    my @file = grep { /$grep_string/ } <INFO>;
    chomp @file;
    close INFO;

    %ENV = %ENV_SAVE;

    return \@file;
}

#--------------------------------------------------------------------------

sub _find_bindings {
    my ($bindir, $libdir, $lang) = @_;

    my $file = _run_laminfo($bindir, $libdir, "^bindings:$lang:");
    return ($file->[0] =~ /^bindings:${lang}:yes/) ? "1" : "0";
}

#--------------------------------------------------------------------------

sub _find_bitness {
    my ($bindir, $libdir) = @_;

    my $str = "^compiler:c:sizeof:pointer:";
    my $file = _run_laminfo($bindir, $libdir, $str);
    $file->[0] =~ m/${str}([0-9]+)/;
    return $1;
}

#--------------------------------------------------------------------------

sub Install {
    my ($ini, $section, $config) = @_;
    my $x;
    my $result_stdout;
    my $result_stderr;

    my $ret;
    $ret->{test_result} = MTT::Values::FAIL;
    $ret->{exit_status} = 0;
    $ret->{installdir} = $config->{installdir};
    $ret->{bindir} = "$ret->{installdir}/bin";
    $ret->{libdir} = "$ret->{installdir}/lib";

    # Get some LAM-module-specific config arguments

    my $tmp;
    $tmp = Value($ini, $section, "lam_make_all_arguments");
    $config->{make_all_arguments} = $tmp
        if (defined($tmp));

    # JMS: compiler name may have come in from "compiler_name"in
    # Install.pm.  So if we didn't define one for this module, use the
    # default from "compiler_name".  Note: to be deleted someday
    # (i.e., only rely on this module's compiler_name and not use a
    # higher-level default, per #222).
    $tmp = Value($ini, $section, "lam_compiler_name");
    $config->{compiler_name} = $tmp
        if (defined($tmp));
    return 
        if (!MTT::Util::is_valid_compiler_name($section, 
                                               $config->{compiler_name}));
    $config->{compiler_version} =
        Value($ini, $section, "lam_compiler_version");

    $tmp = Value($ini, $section, "lam_configure_arguments");
    $tmp =~ s/\n|\r/ /g;
    $config->{configure_arguments} = $tmp
        if (defined($tmp));

    $tmp = Logical($ini, $section, "lam_make_check");
    $config->{make_check} = $tmp
        if (defined($tmp));

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
    $ret->{cxx_bindings} = _find_bindings($ret->{bindir},
                                          $ret->{libdir}, "cxx");
    Debug("Have C++ bindings: $ret->{cxx_bindings}\n"); 
    $ret->{f77_bindings} = _find_bindings($ret->{bindir},
                                          $ret->{libdir}, "f77");
    Debug("Have F77 bindings: $ret->{f77_bindings}\n"); 
    $ret->{f90_bindings} = "0";
    Debug("Have F90 bindings: $ret->{f90_bindings}\n"); 

    # Calculate bitness (must be processed *after* installation)

    $config->{bitness} = _find_bitness($ret->{bindir}, $ret->{libdir});

    # Done

    $ret->{test_result} = MTT::Values::PASS;
    $ret->{result_message} = "Success";
    $ret->{exit_status} = $x->{exit_status};
    Debug("Build was a success\n");

    return $ret;
} 

1;
