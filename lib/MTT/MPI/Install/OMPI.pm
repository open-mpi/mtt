#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
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
    my ($config, $lang) = @_;

    my %ENV_SAVE = %ENV;
    if (exists($ENV{LD_LIBRARY_PATH})) {
        $ENV{LD_LIBRARY_PATH} .= ":$config->{libdir}";
    } else {
        $ENV{LD_LIBRARY_PATH} = "$config->{libdir}";
    }

    open INFO, "$config->{bindir}/ompi_info --parsable|";
    my @have = grep { /^bindings:$lang:/ } <INFO>;
    chomp @have;
    close INFO;

    %ENV = %ENV_SAVE;

    return ($have[0] eq "bindings:${lang}:yes");
}

#--------------------------------------------------------------------------

sub Install {
    my ($ini, $section, $config) = @_;
    my $x;

    # Prepare $ret

    my $ret;
    $ret->{success} = 0;

    # Run configure

    $x = MTT::DoCommand::Cmd(1, "$config->{configdir}/configure $config->{configure_arguments} --prefix=$config->{installdir}");
    $ret->{stdout} = "--- Configure stdout/stderr ---\n$x->{stdout}"
        if ($x->{stdout});
    if ($x->{status} != 0) {
        $ret->{result_message} = "Configure failed -- skipping this build\n";
        return $ret;
    }

    # Build it

    $x = MTT::DoCommand::Cmd($config->{merge_stdout_stderr}, "make $config->{make_all_arguments} all");
    $ret->{stdout} .= "--- \"make all\" stdout" .
        ($config->{merge_stdout_stderr} ? "/stderr" : "") .
        " ---\n$x->{stdout}"
        if ($x->{stdout});
    $ret->{stderr} .= "--- \"make all\" stderr ---\n$x->{stderr}"
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
        $ENV{TMPDIR} = "$config->{installdir}/tmp";
        mkdir($ENV{TMPDIR}, 0777);
        delete $ENV{LD_LIBRARY_PATH};

        Debug("Running make check\n");
        $x = MTT::DoCommand::Cmd(1, "make check");
        %ENV = %ENV_SAVE;

        if ($x->{status} != 0) {
            $ret->{stdout} .= "--- \"make check\" stdout ---\n$x->{stdout}"
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
    $ret->{cxx_bindings} = _find_bindings($config, "cxx");
    $ret->{f77_bindings} = _find_bindings($config, "f77");
    $ret->{f90_bindings} = _find_bindings($config, "f90");

    # All done

    $ret->{success} = 1;
    $ret->{result_message} = "Success";
    return $ret;
} 

1;
