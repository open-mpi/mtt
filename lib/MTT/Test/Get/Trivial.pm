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

package MTT::Test::Get::Trivial;

use strict;
use Cwd;
use File::Temp qw(tempfile);
use MTT::Messages;
use MTT::DoCommand;
use MTT::Values;

#--------------------------------------------------------------------------

# Local variable indicating whether we're written any new files or not
my $have_new;

#--------------------------------------------------------------------------

sub _do_write {
    my ($force, $filename, $body) = @_;
    my $ret;

    # Does the file already exist?
    if (-r $filename && !$force) {
        return undef;
    }

    # Write out the file
    if (!open FILE, ">$filename") {
        $ret->{result_message} = "Failed to write to file: $@";
        return $ret;
    }
    print FILE $body;
    close FILE;

    # All done
    $have_new = 1;
    return undef;
}

#--------------------------------------------------------------------------

sub Get {
    my ($ini, $section, $force) = @_;
    my $ret;
    my $x;

    Debug("Getting Trivial\n");
    $ret->{success} = 0;

    # We're in the source tree, so just write out some files

    $have_new = $ret->{have_new} = 0;
    $x = _do_write($force, "hello.c", "#include <stdio.h>
#include <mpi.h>
int main(int argc, char* argv[]) {
    int rank, size;
    MPI_Init(&argc, &argv);
    MPI_Finalize();
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);
    printf(\"Hello, world!  I am %d of %d\\n\", rank, size);
    return 0;
}\n");
    if ($x) {
        $ret->{result_message} = $x->{result_message};
        return $ret;
    }

    $x = _do_write($force, "hello.cc", "#include <iostream>
#include <mpi.h>
using namespace std;
int main(int argc, char* argv[]) {
    int rank, size;
    MPI::Init(argc, argv);
    MPI::Finalize();
    rank = MPI::COMM_WORLD.Get_rank();
    size = MPI::COMM_WORLD.Get_size();
    cout << \"Hello, world!  I am \" << rank << \" of \" << size << endl;   
    return 0;
}\n");
    if ($x) {
        $ret->{result_message} = $x->{result_message};
        return $ret;
    }

    $x = _do_write($force, "hello.f", "C
        program main
        implicit none
        include 'mpif.h'
        integer rank, size, ierr
        call MPI_INIT(ierr)
        call MPI_FINALIZE(ierr)
        call MPI_COMM_RANK(MPI_COMM_WORLD, rank, ierr)
        call MPI_COMM_SIZE(MPI_COMM_WORLD, size, ierr)
        print *, 'Hello Fortran world, I am ', rank, ' of ', size
        end program main\n");
    if ($x) {
        $ret->{result_message} = $x->{result_message};
        return $ret;
    }

    $x = _do_write($force, "hello.f90", "program main
    use mpi
    integer rank, size, ierr
    call MPI_INIT(ierr)
    call MPI_FINALIZE(ierr)
    call MPI_COMM_RANK(MPI_COMM_WORLD, rank, ierr)
    call MPI_COMM_SIZE(MPI_COMM_WORLD, size, ierr)
    print *, 'Hello Fortran world, I am ', rank, ' of ', size
end program main\n");
    if ($x) {
        $ret->{result_message} = $x->{result_message};
        return $ret;
    }

    # All done
    $ret->{success} = 1;
    $ret->{have_new} = $have_new;
    $ret->{result_message} = "Success";
    return $ret;
} 

1;
