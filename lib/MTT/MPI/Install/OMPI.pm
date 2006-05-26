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
        $ENV{LD_LIBRARY_PATH} .= ":$libdir";
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

    # Prepare $ret

    my $ret;
    $ret->{success} = 0;

    # Run configure

    $ret->{installdir} = $config->{installdir};
    $ret->{bindir} = "$ret->{installdir}/bin";
    $ret->{libdir} = "$ret->{installdir}/lib";

    $x = MTT::DoCommand::Cmd(1, "$config->{configdir}/configure $config->{configure_arguments} --prefix=$ret->{installdir}");
    $ret->{configure_stdout} = "--- Configure stdout/stderr ---\n$x->{stdout}"
        if ($x->{stdout});
    if ($x->{status} != 0) {
        $ret->{result_message} = "Configure failed -- skipping this build\n";
        return $ret;
    }

    # Build it

    $x = MTT::DoCommand::Cmd($config->{merge_stdout_stderr}, "make $config->{make_all_arguments} all");
    $ret->{make_all_stdout} .= "--- \"make all\" stdout" .
        ($config->{merge_stdout_stderr} ? "/stderr" : "") .
        " ---\n$x->{stdout}"
        if ($x->{stdout});
    $ret->{make_all_stderr} .= "--- \"make all\" stderr ---\n$x->{stderr}"
        if ($x->{stderr});
    if ($x->{status} != 0) {
        $ret->{result_message} = "Failed to build: make $config->{make_all_arguments} all\n";
        return $ret;
    }

    # Do we want to run "make check"?  If so, make sure a valid TMPDIR
    # exists.  Also, merge the stdout/stderr because we really only
    # want to see it if something fails (i.e., it's common to display
    # junk to stderr during "make check"'s normal execution).

    if ($config->{make_check} == 1) {
        my %ENV_SAVE = %ENV;
        $ENV{TMPDIR} = "$ret->{installdir}/tmp";
        mkdir($ENV{TMPDIR}, 0777);
        # We may need to revisit this later -- there are definitely
        # cases where simply deleting the entire LD_LIBRARY_PATH is
        # not a Good Thing (e.g., if there are libraries in there
        # necessary for the compiler that are not in the default ld.so
        # search path).  The intent here is just to ensure that the
        # LD_LIBRARY_PATH in the environment does not point to shared
        # libraries outside of MTT's scope that would interfere with
        # "make check" (e.g., another libmpi.so outside of MTT).  I
        # don't quite know how to do that, though, so we just
        # currently delete the whole thing.  :-)
        delete $ENV{LD_LIBRARY_PATH};

        Debug("Running make check\n");
        $x = MTT::DoCommand::Cmd(1, "make check");
        %ENV = %ENV_SAVE;

        if ($x->{status} != 0) {
            $ret->{make_check_stdout} .= "--- \"make check\" stdout ---\n$x->{stdout}"
                if ($x->{stdout});
            $ret->{result_message} = "Failed to make check\n";
            return $ret;
        }
        $ret->{make_check_stdout} = $x->{stdout};
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
        $ret->{result_message} = "Failed to make install\n";
        return $ret;
    }

    # Set which bindings were compiled

    $ret->{c_bindings} = 1;
    $ret->{cxx_bindings} = _find_bindings($ret->{bindir},
                                          $ret->{libdir}, "cxx");
    $ret->{f77_bindings} = _find_bindings($ret->{bindir},
                                          $ret->{libdir}, "f77");
    $ret->{f90_bindings} = _find_bindings($ret->{bindir},
                                          $ret->{libdir}, "f90");

    # All done

    $ret->{success} = 1;
    $ret->{result_message} = "Success";
    return $ret;
} 

1;
