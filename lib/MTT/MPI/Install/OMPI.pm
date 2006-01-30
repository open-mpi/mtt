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

    open INFO, "$config->{bindir}/ompi_info --parsable|";
    my @have = grep { /^bindings:$lang:/ } <INFO>;
    chomp @have;
    close INFO;

    return ($have[0] eq "bindings:${lang}:yes");
}

#--------------------------------------------------------------------------

sub Install {
    my ($config) = @_;
    my $x;

    # Prepare $ret

    my $ret;
    $ret->{success} = 0;
    
    # Run configure

    $x = MTT::DoCommand::Cmd(1, "$config->{configdir}/configure $config->{configure_arguments} --prefix=$config->{installdir}");
    if ($x->{status} != 0) {
        $ret->{result_message} = "Configure failed -- skipping this build\n";
        $ret->{stdout} = $x->{stdout};
        return $ret;
    }
    $ret->{configure_stdout} = $x->{stdout};

    # Build it

    $x = MTT::DoCommand::Cmd($config->{std_combined}, "make $config->{make_all_arguments} all");
    if ($x->{status} != 0) {
        $ret->{result_message} = "Failed to build: make $config->{make_all_arguments} all\n";
        $ret->{stdout} = $x->{stdout};
        $ret->{stderr} = $x->{stderr};
        return $ret;
    }
    $ret->{make_all_stdout} = $x->{stdout};
    $ret->{make_all_stderr} = $x->{stderr};

    # Do we want to run "make check"?  If so, make sure a valid TMPDIR
    # exists.

    if ($config->{make_check} == 1) {
        my %ENV_SAVE = %ENV;
        $ENV{TMPDIR} = "$config->{installdir}/tmp";
        mkdir($ENV{TMPDIR}, 0777);
        delete $ENV{LD_LIBRARY_PATH};

        Debug("Running make check\n");
        $x = MTT::DoCommand::Cmd($config->{std_combined}, "make check");
        %ENV = %ENV_SAVE;

        if ($x->{status} != 0) {
            $ret->{result_message} = "Failed to make check\n";
            $ret->{stdout} = $x->{stdout};
            return $ret;
        }
        $ret->{make_check_stdout} = $x->{stdout};
    } else {
        Debug("Not running make check\n");
    }

    # Ensure LD_LIBRARY_PATH points to our shared libraries

    $ret->{installdir} = "$config->{installdir}";
    $ret->{bindir} = "$config->{installdir}/bin";
    $ret->{libdir} = "$config->{installdir}/lib";
    if (exists($ENV{LD_LIBRARY_PATH})) {
        $ENV{LD_LIBRARY_PATH} = "$ret->{libdir}:" . $ENV{LD_LIBRARY_PATH};
    } else {
        $ENV{LD_LIBRARY_PATH} = $ret->{libdir};
    }

    # Install it

    $x = MTT::DoCommand::Cmd(1, "make install");
    if ($x->{status} != 0) {
        $ret->{result_message} = "Failed to make install\n";
        $ret->{stdout} = $x->{stdout};
        return $ret;
    }

    # Set which bindings were compiled

    $ret->{c_bindings} = 1;
    $ret->{cxx_bindings} = _find_bindings($config, "cxx");
    $ret->{f77_bindings} = _find_bindings($config, "f77");
    $ret->{f90_bindings} = _find_bindings($config, "f90");

    ######################################################################
    # At this point, we could just set $ret->{success} and
    # $ret->{result_message} and return $ret -- that would meet the
    # requirements of this module.  But we choose to do some basic
    # compile/link tests with "hello world" MPI apps just to verify
    # that our installation is any good.
    ######################################################################

    # Try compiling and linking a simple C application

    chdir($ret->{section_dir});
    if (! -d "test-compile") {
        mkdir("test-compile", 0777);
        if (-d "test_compile") {
            $ret->{result_message} = "Could not make test compile directory: $@\n";
            $x->{stdout} = $@;
            return $ret;
        }
    }
    chdir("test-compile");

    Debug("Test compile/link sample C MPI application\n");
    open C, ">hello.c";
    print C "#include <mpi.h>
int main(int argc, char* argv[]) {
  MPI_Init(&argc, &argv);
  MPI_Finalize();
  return 0;
}\n";
    close(C);
    $x = MTT::DoCommand::Cmd(1, "$ret->{bindir}/mpicc hello.c -o hello");
    if ($x->{status} != 0) {
        $ret->{result_message} = "Failed to compile/link C \"hello world\" MPI app\n";
        $ret->{stdout} = $x->{stdout};
        return $ret;
    }
    unlink "hello.c", "hello";

    # If we have the C++ MPI bindings, try and compile and link a
    # simple C++ application

    if ($ret->{cxx_bindings}) {
        Debug("Test compile/link sample C++ MPI application\n");
        open CXX, ">hello.cc";
        print CXX "#include <mpi.h>
int main(int argc, char* argv[]) {
  MPI::Init(argc, argv);
  MPI::Finalize();
  return 0;
}\n";
        close(CXX);
        $x = MTT::DoCommand::Cmd(1, "$ret->{bindir}/mpic++ hello.cc -o hello");
        if ($x->{status} != 0) {
            $ret->{result_message} = "Failed to compile/link C++ \"hello world\" MPI app\n";
            $ret->{stdout} = $x->{stdout};
            return $ret;
        }
        unlink "hello.cc", "hello";
    } else {
        Debug("MPI C++ bindings unavailable; skipping simple compile/link test\n");
    }

    # If we have the F77 MPI bindings, try compiling and linking a
    # simple F77 application

    if ($ret->{f77_bindings}) {
        Debug("Test compile/link sample F77 MPI application\n");
        open F77, ">hello.f";
        print F77 "C
        program main
        include 'mpif.h'
        call MPI_INIT(ierr)
        call MPI_FINALIZE(ierr)
        stop
        end\n";
        close(F77);
        $x = MTT::DoCommand::Cmd(1, "$ret->{bindir}/mpif77 hello.f -o hello");
        if ($x->{status} != 0) {
            $ret->{result_message} = "Failed to compile/link F77 \"hello world\" MPI app\n";
            $ret->{stdout} = $x->{stdout};
            return $ret;
        }
        unlink "hello.f", "hello";
    } else {
        Debug("MPI F77 bindings unavailable; skipping simple compile/link test\n");
    }

    # If we have the F90 MPI bindings, try compiling and linking a
    # simple F90 application

    if ($ret->{f90_bindings}) {
        Debug("Test compile/link sample F90 MPI application\n");
        open F90, ">hello.F";
        print F90 "        program main
        use mpi
        call MPI_INIT(ierr)
        call MPI_FINALIZE(ierr)
        stop
        end program main\n";
        close(F90);
        $x = MTT::DoCommand::Cmd(1, "$ret->{bindir}/mpif90 hello.F -o hello");
        if ($x->{status} != 0) {
            $ret->{result_message} = "Failed to compile/link F90 \"hello world\" MPI app\n";
            $ret->{stdout} = $x->{stdout};
            return $ret;
        }
        unlink "hello.F", "hello";
    } else {
        Debug("MPI F90 bindings unavailable; skipping simple compile/link test\n");
    }

    # Remove test compiles dir

    chdir("..");
    MTT::DoCommand::Cmd(1, "rm -rf test-compile");

    # Dump $ret into a file in this directory in case we are not
    # building the tests now

    $ret->{success} = 1;
    $ret->{result_message} = "Success";

    # All done

    return $ret;
} 

1;
