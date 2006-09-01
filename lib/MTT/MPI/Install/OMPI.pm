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

package MTT::MPI::Install::OMPI;

use strict;
use Cwd;
use MTT::DoCommand;
use MTT::Messages;
use Data::Dumper;

#--------------------------------------------------------------------------

sub _find_bindings {
    my ($bindir, $libdir, $lang) = @_;

    my %ENV_SAVE = %ENV;
    if (exists($ENV{LD_LIBRARY_PATH})) {
        $ENV{LD_LIBRARY_PATH} = "$libdir:$ENV{LD_LIBRARY_PATH}";
    } else {
        $ENV{LD_LIBRARY_PATH} = "$libdir";
    }

    open INFO, "$bindir/ompi_info --parsable|";
    my @have = grep { /^bindings:$lang:/ } <INFO>;
    chomp @have;
    close INFO;

    %ENV = %ENV_SAVE;

    return ($have[0] =~ /^bindings:${lang}:yes/) ? "1" : "0";
}

#--------------------------------------------------------------------------

sub Install {
    my ($ini, $section, $config) = @_;
    my $x;
    my $stdout;
    my $stderr;

    # Prepare $ret

    my $ret;
    $ret->{success} = 0;

    # Run configure

    $ret->{installdir} = $config->{installdir};
    $ret->{bindir} = "$ret->{installdir}/bin";
    $ret->{libdir} = "$ret->{installdir}/lib";

    $x = MTT::DoCommand::Cmd(1, "$config->{configdir}/configure $config->{configure_arguments} --prefix=$ret->{installdir}");
    $stdout = $x->{stdout} ? "--- Configure stdout/stderr ---\n$x->{stdout}" :
        undef;
    if ($x->{status} != 0) {
        $ret->{result_message} = "Configure failed -- skipping this build";
        # Put the output of the failure into $ret so that it gets
        # reported (stdout/stderr was combined into just stdout)
        $ret->{stdout} = $stdout;
        return $ret;
    }
    # We don't need this in the main stdout
    $ret->{configure_stdout} = $stdout;

    # Build it

    $x = MTT::DoCommand::Cmd($config->{merge_stdout_stderr}, "make $config->{make_all_arguments} all");
    $stdout = undef;
    if ($x->{stdout}) {
        $stdout = "--- \"make all ";
        $stdout .= "stdout"
            if ($x->{stdout});
        $stdout .= "/stderr"
            if ($config->{merge_stdout_stderr});
        $stdout .= " ---\n$x->{stdout}";
    }
    $stderr = $x->{stderr} ? "--- \"make all\" stderr ---\n$x->{stderr}" : 
        undef;
    if ($x->{status} != 0) {
        $ret->{result_message} = "Failed to build: make $config->{make_all_arguments} all";
        # Put the output of the failure into $ret so that it gets
        # reported (stdout/stderr *may* be separated, so assign them
        # both -- if they were combined, then $stderr will be empty)
        $ret->{stdout} = $stdout;
        $ret->{stderr} = $stderr;
        return $ret;
    }
    $ret->{make_all_stdout} = $stdout;
    $ret->{make_all_stderr} = $stderr;

    # Do we want to run "make check"?  If so, make sure a valid TMPDIR
    # exists.  Also, merge the stdout/stderr because we really only
    # want to see it if something fails (i.e., it's common to display
    # junk to stderr during "make check"'s normal execution).

    if ($config->{make_check} == 1) {
        my %ENV_SAVE = %ENV;
        $ENV{TMPDIR} = "$ret->{installdir}/tmp";
        mkdir($ENV{TMPDIR}, 0777);
        # The intent here is just to ensure that the LD_LIBRARY_PATH
        # in the environment does not point to shared libraries
        # outside of MTT's scope that would interfere with "make
        # check" (e.g., another libmpi.so outside of MTT).  Just
        # prepend our own $libdir to LD_LIBRARY_PATH and hope that
        # that's Good Enough.  :-)
        if (exists($ENV{LD_LIBRARY_PATH})) {
            $ENV{LD_LIBRARY_PATH} = "$ret->{libdir}:$ENV{LD_LIBRARY_PATH}";
        } else {
            $ENV{LD_LIBRARY_PATH} = "$ret->{libdir}";
        }

        Debug("Running make check\n");
        $x = MTT::DoCommand::Cmd(1, "make check");
        %ENV = %ENV_SAVE;

        $stdout = "--- \"make check\" stdout ---\n$x->{stdout}"
            if ($x->{stdout});
        if ($x->{status} != 0) {
            $ret->{result_message} = "Failed to make check";
            # Put the output of the failure into $ret so that it gets
            # reported (stdout/stderr were combined)
            $ret->{stdout} = $x->{stdout};
            return $ret;
        }
        $ret->{make_check_stdout} = $stdout;
    } else {
        Debug("Not running make check\n");
    }

    # Install it.  Merge the stdout/stderr because we really only want
    # to see the output if something went wrong.  Things sent to
    # stderr are common during "make install" (e.g., notices about
    # re-linking libraries when they are installed)

    $x = MTT::DoCommand::Cmd(1, "make install");
    if ($x->{status} != 0) {
        $ret->{stdout} .= "--- \"make install\" stdout ---\n$x->{stdout}"
            if ($x->{stdout});
        $ret->{result_message} = "Failed to make install";
        # Put the output of the failure into $ret so that it gets
        # reported (stdout/stderr were combined)
        $ret->{stdout} = $x->{stdout};
        return $ret;
    }
    $ret->{make_install_stdout} = $stdout;

    # Set which bindings were compiled

    $ret->{c_bindings} = 1;
    Debug("Have C bindings: 1\n");
    $ret->{cxx_bindings} = _find_bindings($ret->{bindir},
                                          $ret->{libdir}, "cxx");
    Debug("Have C++ bindings: $ret->{cxx_bindings}\n"); 
    $ret->{f77_bindings} = _find_bindings($ret->{bindir},
                                          $ret->{libdir}, "f77");
    Debug("Have F77 bindings: $ret->{f77_bindings}\n"); 
    $ret->{f90_bindings} = _find_bindings($ret->{bindir},
                                          $ret->{libdir}, "f90");
    Debug("Have F90 bindings: $ret->{f90_bindings}\n"); 

    # All done

    $ret->{success} = 1;
    $ret->{result_message} = "Success";
    Debug("Build was a success\n");
    return $ret;
} 

1;
