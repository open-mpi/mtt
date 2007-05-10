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

    # Prepare $ret

    my $ret;
    $ret->{test_result} = MTT::Values::FAIL;
    $ret->{exit_status} = 0;

    # Get some LAM-module-specific config arguments

    my $tmp;
    $tmp = Value($ini, $section, "lam_make_all_arguments");
    $config->{make_all_arguments} = $tmp
        if (defined($tmp));

    $config->{compiler_name} =
        Value($ini, $section, "lam_compiler_name");
    if ($MTT::Defaults::System_config->{known_compiler_names} !~ /$config->{compiler_name}/) {
        Warning("Unrecognized compiler name in [$section] ($config->{compiler_name}); the only permitted names are: \"$MTT::Defaults::System_config->{known_compiler_names}\"; skipped\n");
        return;
    }
    $config->{compiler_version} =
        Value($ini, $section, "lam_compiler_version");

    my $tmp = Value($ini, $section, "lam_configure_arguments");
    $config->{configure_arguments} = $tmp
        if (defined($tmp));

    # Run configure

    $ret->{installdir} = $config->{installdir};
    $ret->{bindir} = "$ret->{installdir}/bin";
    $ret->{libdir} = "$ret->{installdir}/lib";

    $x = MTT::DoCommand::Cmd(1, "$config->{configdir}/configure $config->{configure_arguments} --prefix=$ret->{installdir}", -1, $config->{stdout_save_lines}, $config->{stderr_save_lines});
    $result_stdout = $x->{result_stdout} ? "--- Configure result_stdout/result_stderr ---\n$x->{result_stdout}" :
        undef;
    if (!MTT::DoCommand::wsuccess($x->{exit_status})) {
        $ret->{result_message} = "Configure failed -- skipping this build";
        # Put the output of the failure into $ret so that it gets
        # reported (result_stdout/result_stderr was combined into just result_stdout)
        $ret->{result_stdout} = $result_stdout;
        $ret->{exit_status} = $x->{exit_status};
        return $ret;
    }
    # We don't need this in the main result_stdout
    $ret->{configure_stdout} = $result_stdout;

    # Build it

    $x = MTT::DoCommand::Cmd($config->{merge_stdout_stderr}, "make $config->{make_all_arguments} all", -1, $config->{stdout_save_lines});
    $result_stdout = undef;
    if ($x->{result_stdout}) {
        $result_stdout = "--- \"make all ";
        $result_stdout .= "result_stdout"
            if ($x->{result_stdout});
        $result_stdout .= "/result_stderr"
            if ($config->{merge_stdout_stderr});
        $result_stdout .= " ---\n$x->{result_stdout}";
    }
    $result_stderr = $x->{result_stderr} ? "--- \"make all\" result_stderr ---\n$x->{result_stderr}" : 
        undef;
    if (!MTT::DoCommand::wsuccess($x->{exit_status})) {
        $ret->{result_message} = "Failed to build: make $config->{make_all_arguments} all";
        # Put the output of the failure into $ret so that it gets
        # reported (result_stdout/result_stderr *may* be separated, so assign them
        # both -- if they were combined, then $result_stderr will be empty)
        $ret->{result_stdout} = $result_stdout;
        $ret->{result_stderr} = $result_stderr;
        $ret->{exit_status} = $x->{exit_status};
        return $ret;
    }
    $ret->{make_all_stdout} = $result_stdout;
    $ret->{make_all_stderr} = $result_stderr;

    # Install it.  Merge the result_stdout/result_stderr because we
    # really only want to see the output if something went wrong.
    # Things sent to result_stderr are common during "make install"
    # (e.g., notices about re-linking libraries when they are
    # installed)

    $x = MTT::DoCommand::Cmd(1, "make install", -1, $config->{stdout_save_lines}, $config->{stderr_save_lines});
    if (!MTT::DoCommand::wsuccess($x->{exit_status})) {
        $ret->{result_stdout} .= "--- \"make install\" result_stdout ---\n$x->{result_stdout}"
            if ($x->{result_stdout});
        $ret->{result_message} = "Failed to make install";
        # Put the output of the failure into $ret so that it gets
        # reported (result_stdout/result_stderr were combined)
        $ret->{result_stdout} = $x->{result_stdout};
        $ret->{exit_status} = $x->{exit_status};
        return $ret;
    }
    $ret->{make_install_stdout} = $result_stdout;

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
