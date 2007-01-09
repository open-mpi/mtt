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

package MTT::MPI::Install::Copytree;

use strict;
use Cwd;
use File::Basename;
use Data::Dumper;
use MTT::DoCommand;
use MTT::Messages;
use MTT::Values;
use MTT::Files;

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
    my ($ini, $section, $config) = @_;
    my $x;
    my $val;

    # Prepare $ret

    my $ret;
    $ret->{test_result} = MTT::Values::FAIL;
    $ret->{exit_status} = 1;
    Verbose("*** MPI INSTALL COPYTREE PLUGIN IS OUT OF DATE.  CONTACT AUTHORS\n");
    return $ret;


    Debug(">> copytree copying to $config->{installdir}\n");
    if (-d $config->{installdir}) {
        system("rm -rf $config->{installdir}");
        MTT::Files::mkdir($config->{installdir});
    }

    # Pre copy
    $val = Value($ini, $section, "copytree_pre_copy");
    if ($val) {
        Debug("Copytree running pre_copy command: $val\n");
        $x = MTT::DoCommand::CmdScript(1, $val);
        if (!MTT::DoCommand::wsuccess($x->{exit_status})) {
            Warning("Pre-copy command failed: $@\n");
            return undef;
        }
    }

    # Copy the tree
    my $start_dir = cwd();
    MTT::DoCommand::Chdir($config->{installdir});
    $x = MTT::Files::copy_tree("$config->{abs_srcdir}", 1);
    MTT::DoCommand::Chdir($start_dir);
    return undef
        if (!$x);

    # copy_tree() copies the entire tree, to include the final
    # directory name.  So we just ended up with everything copied to
    # $config->{installdir}/basename($config->{abs_srcdir}).  So we
    # need to move everything in that directory back one, and then
    # rmdir the resulting empty directory.
    my $b = basename($config->{abs_srcdir});
    system("mv $config->{installdir}/$b/* $config->{installdir} ; rmdir $config->{installdir}/$b");

    # Post copy
    $val = Value($ini, $section, "copytree_post_copy");
    if ($val) {
        Debug("Copytree running pre_copy command: $val\n");
        $x = MTT::DoCommand::CmdScript(1, $val);
        if (!MTT::DoCommand::wsuccess($x->{exit_status})) {
            Warning("Post-copy command failed: $@\n");
            return undef;
        }
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

    # Set which bindings were provided

    $ret->{c_bindings} = 1;
    $ret->{cxx_bindings} = _find_bindings($config, "cxx");
    $ret->{f77_bindings} = _find_bindings($config, "f77");
    $ret->{f90_bindings} = _find_bindings($config, "f90");

    ######################################################################
    # At this point, we could just set $ret->{test_result} and
    # $ret->{result_message} and return $ret -- that would meet the
    # requirements of this module.  But we choose to do some basic
    # compile/link tests with "hello world" MPI apps just to verify
    # that our installation is any good.
    ######################################################################

    # Try compiling and linking a simple C application

    MTT::DoCommand::Chdir($config->{section_dir});
    if (! -d "test-compile") {
        mkdir("test-compile", 0777);
        if (-d "test_compile") {
            $ret->{result_message} = "Could not make test compile directory: $@\n";
            $x->{result_stdout} = $@;
            return $ret;
        }
    }
    MTT::DoCommand::Chdir("test-compile");

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
    if (!MTT::DoCommand::wsuccess($x->{exit_status})) {
        $ret->{result_message} = "Failed to compile/link C \"hello world\" MPI app: $@\n";
        $ret->{result_stdout} = $x->{result_stdout};
        print "test_Stdout: $ret->{result_stdout}\n";
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
        if (!MTT::DoCommand::wsuccess($x->{exit_status})) {
            $ret->{result_message} = "Failed to compile/link C++ \"hello world\" MPI app\n";
            $ret->{result_stdout} = $x->{result_stdout};
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
        if (!MTT::DoCommand::wsuccess($x->{exit_status})) {
            $ret->{result_message} = "Failed to compile/link F77 \"hello world\" MPI app\n";
            $ret->{result_stdout} = $x->{result_stdout};
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
        if (!MTT::DoCommand::wsuccess($x->{exit_status})) {
            $ret->{result_message} = "Failed to compile/link F90 \"hello world\" MPI app\n";
            $ret->{result_stdout} = $x->{result_stdout};
            return $ret;
        }
        unlink "hello.F", "hello";
    } else {
        Debug("MPI F90 bindings unavailable; skipping simple compile/link test\n");
    }

    # Remove test compiles dir

    MTT::DoCommand::Chdir("..");
    MTT::DoCommand::Cmd(1, "rm -rf test-compile");

    # Dump $ret into a file in this directory in case we are not
    # building the tests now

    $ret->{test_result} = MTT::Values::PASS;
    $ret->{result_message} = "Success";

    # All done

    return $ret;
} 

1;
