#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006-2012 Cisco Systems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Test::Get::Trivial;

use strict;
use File::Temp qw(tempfile);
use MTT::Messages;
use MTT::DoCommand;
use MTT::Values;
use MTT::Files;

#--------------------------------------------------------------------------

sub Get {
    my ($ini, $section, $force) = @_;
    my $ret;
    my $x;

    Debug("Getting Trivial\n");
    $ret->{test_result} = MTT::Values::FAIL;

    # We're in the source tree, so just write out some files

    $ret->{have_new} = 0;

    #
    # C
    #

    $x = MTT::Files::SafeWrite($force, "hello.c", "/*
 * This program is automatically generated via the \"Trivial\" Test::Get
 * module of the MPI Testing Tool (MTT).  Any changes you make here may
 * get lost!
 *
 * Copyrights and licenses of this file are the same as for the MTT.
 */

#include <stdio.h>
#include <mpi.h>
int main(int argc, char* argv[]) {
    int rank, size;
    MPI_Init(&argc, &argv);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);
    printf(\"Hello, C world!  I am %d of %d\\n\", rank, size);
    MPI_Finalize();
    return 0;
}\n");
    if (! $x->{success}) {
        $ret->{result_message} = $x->{result_message};
        return $ret;
    }

    $x = MTT::Files::SafeWrite($force, "ring.c", "/*
 * This program is automatically generated via the \"Trivial\" Test::Get
 * module of the MPI Testing Tool (MTT).  Any changes you make here may
 * get lost!
 *
 * Copyrights and licenses of this file are the same as for the MTT.
 */

#include <stdlib.h>
#include <mpi.h>

#define SIZE 20
#define POS 10
#define INITIAL_VALUE 10

int main(int argc, char *argv[])
{
    int i, rank, size, next, prev, tag = 201;
    int array_size = SIZE;
    int pos = POS;
    int *send_array;
    int *recv_array;

    MPI_Init(&argc, &argv);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);

    next = (rank + 1) % size;
    prev = (rank + size - 1) % size;
    send_array = malloc(sizeof(int) * SIZE);
    recv_array = malloc(sizeof(int) * SIZE);

    for (i = 0; i < array_size; ++i) {
        send_array[i] = 17;
        recv_array[i] = -1;
    }

    if (0 == rank) {
        send_array[pos] = INITIAL_VALUE;
        MPI_Send(send_array, array_size, MPI_INT, next, tag,
                 MPI_COMM_WORLD);
    }

    while (1) {
        recv_array[pos] = -1;
        MPI_Recv(recv_array, array_size, MPI_INT, prev, tag,
                 MPI_COMM_WORLD, MPI_STATUS_IGNORE);
        send_array[pos] = recv_array[pos];
        if (rank == 0) {
            --send_array[pos];
        }
        MPI_Send(send_array, array_size, MPI_INT, next, tag, MPI_COMM_WORLD);
        if (0 == send_array[pos]) {
            break;
        }
    }

    if (rank == 0) {
        MPI_Recv(recv_array, array_size, MPI_INT, prev, tag,
                 MPI_COMM_WORLD, MPI_STATUS_IGNORE);
    }

    MPI_Barrier(MPI_COMM_WORLD);
    MPI_Finalize();
    return 0;
}\n");
    if (! $x->{success}) {
        $ret->{result_message} = $x->{result_message};
        return $ret;
    }

    #
    # C++
    #

    $x = MTT::Files::SafeWrite($force, "hello.cc", "//
// This program is automatically generated via the \"Trivial\" Test::Get
// module of the MPI Testing Tool (MTT).  Any changes you make here may
// get lost!
//
// Copyrights and licenses of this file are the same as for the MTT.
//

#include <iostream>
#include <mpi.h>
using namespace std;
int main(int argc, char* argv[]) {
    int rank, size;
    MPI::Init(argc, argv);
    rank = MPI::COMM_WORLD.Get_rank();
    size = MPI::COMM_WORLD.Get_size();
    cout << \"Hello, C++ world!  I am \" << rank << \" of \" << size << endl;
    MPI::Finalize();
    return 0;
}\n");
    if (! $x->{success}) {
        $ret->{result_message} = $x->{result_message};
        return $ret;
    }

    $x = MTT::Files::SafeWrite($force, "ring.cc", "//
// This program is automatically generated via the \"Trivial\" Test::Get
// module of the MPI Testing Tool (MTT).  Any changes you make here may
// get lost!
//
// Copyrights and licenses of this file are the same as for the MTT.
//

#include <mpi.h>

#define SIZE 20
#define POS 10
#define INITIAL_VALUE 10

int main(int argc, char *argv[])
{
    int i, rank, size, next, prev, tag = 201;
    int array_size = SIZE;
    int pos = POS;
    int *send_array;
    int *recv_array;

    MPI::Init(argc, argv);
    rank = MPI::COMM_WORLD.Get_rank();
    size = MPI::COMM_WORLD.Get_size();

    next = (rank + 1) % size;
    prev = (rank + size - 1) % size;
    send_array = new int[SIZE];
    recv_array = new int[SIZE];

    for (i = 0; i < array_size; ++i) {
        send_array[i] = 17;
        recv_array[i] = -1;
    }

    if (0 == rank) {
        send_array[pos] = INITIAL_VALUE;
        MPI::COMM_WORLD.Send(send_array, array_size, MPI_INT, next, tag);
    }

    while (1) {
        recv_array[pos] = -1;
        MPI::COMM_WORLD.Recv(recv_array, array_size, MPI_INT, prev, tag);
        send_array[pos] = recv_array[pos];
        if (rank == 0) {
            --send_array[pos];
        }
        MPI::COMM_WORLD.Send(send_array, array_size, MPI_INT, next, tag);
        if (0 == send_array[pos]) {
            break;
        }
    }

    if (rank == 0) {
        MPI::COMM_WORLD.Recv(recv_array, array_size, MPI_INT, prev, tag);
    }

    MPI::COMM_WORLD.Barrier();
    MPI::Finalize();
    return 0;
}\n");
    if (! $x->{success}) {
        $ret->{result_message} = $x->{result_message};
        return $ret;
    }

    #
    # Fortran mpif.h interface
    #

    $x = MTT::Files::SafeWrite($force, "hello_mpifh.f90", "!
! This program is automatically generated via the \"Trivial\" Test::Get
! module of the MPI Testing Tool (MTT).  Any changes you make here may
! get lost!
!
! Copyrights and licenses of this file are the same as for the MTT.
!

        program hello_mpifh
        implicit none
        include 'mpif.h'
        integer rank, size, ierr
        call MPI_INIT(ierr)
        call MPI_COMM_RANK(MPI_COMM_WORLD, rank, ierr)
        call MPI_COMM_SIZE(MPI_COMM_WORLD, size, ierr)
        print *, 'Hello, Fortran mpif.h world, I am ', rank, ' of ', size
        call MPI_FINALIZE(ierr)
        end\n");
    if (! $x->{success}) {
        $ret->{result_message} = $x->{result_message};
        return $ret;
    }

    $x = MTT::Files::SafeWrite($force, "ring_mpifh.f90", "!
! This program is automatically generated via the \"Trivial\" Test::Get
! module of the MPI Testing Tool (MTT).  Any changes you make here may
! get lost!
!
! Copyrights and licenses of this file are the same as for the MTT.
!

      program ring_mpifh
      implicit none
      include 'mpif.h'
      integer rank, size, tag, next, from, ierr
      integer done
      integer length, pos
      integer num(20)
      integer initial_value

      tag = 201
      length = 20
      pos = length - 10
      initial_value = 10

      call mpi_init(ierr)
      call mpi_comm_rank(MPI_COMM_WORLD, rank, ierr)
      call mpi_comm_size(MPI_COMM_WORLD, size, ierr)

      next = mod((rank + 1), size)
      from = mod((rank + size - 1), size)
      if (rank .eq. 0) then
         num(pos) = 30
         call mpi_send(num, length, MPI_INTEGER, next, tag, MPI_COMM_WORLD, ierr)
      endif

 10   call mpi_recv(num, length, MPI_INTEGER, from, tag, MPI_COMM_WORLD, MPI_STATUS_IGNORE, ierr)
      if (rank .eq. 0) then
         num(pos) = num(pos) - 1
      endif
      call mpi_send(num, length, MPI_INTEGER, next, tag, MPI_COMM_WORLD, ierr)
      
      if (num(pos) .eq. 0) then
         goto 20
      endif
      goto 10

 20   if (rank .eq. 0) then
         call mpi_recv(num, length, MPI_INTEGER, from, tag, MPI_COMM_WORLD, MPI_STATUS_IGNORE, ierr)
      endif

      call mpi_barrier(MPI_COMM_WORLD, ierr)
      call mpi_finalize(ierr)
      end\n");
    if (! $x->{success}) {
        $ret->{result_message} = $x->{result_message};
        return $ret;
    }

    #
    # Fortran "use mpi" interface
    #

    $x = MTT::Files::SafeWrite($force, "hello_usempi.f90", "!
! This program is automatically generated via the \"Trivial\" Test::Get
! module of the MPI Testing Tool (MTT).  Any changes you make here may
! get lost!
!
! Copyrights and licenses of this file are the same as for the MTT.
!

program hello_mpi
    use mpi
    implicit none
    integer rank, size, ierr
    call MPI_INIT(ierr)
    call MPI_COMM_RANK(MPI_COMM_WORLD, rank, ierr)
    call MPI_COMM_SIZE(MPI_COMM_WORLD, size, ierr)
    print *, 'Hello, Fortran mpi world, I am ', rank, ' of ', size
    call MPI_FINALIZE(ierr)
end program hello_mpi\n");
    if (! $x->{success}) {
        $ret->{result_message} = $x->{result_message};
        return $ret;
    }

    $x = MTT::Files::SafeWrite($force, "ring_usempi.f90", "!
! This program is automatically generated via the \"Trivial\" Test::Get
! module of the MPI Testing Tool (MTT).  Any changes you make here may
! get lost!
!
! Copyrights and licenses of this file are the same as for the MTT.
!

program ring_mpi
    use mpi
    implicit none
    integer rank, size, tag, next, from, ierr
    integer done
    integer length, pos
    integer num(20)
    integer initial_value
  
    tag = 201
    length = 20
    pos = length - 10
    initial_value = 10

    call mpi_init(ierr)
    call mpi_comm_rank(MPI_COMM_WORLD, rank, ierr)
    call mpi_comm_size(MPI_COMM_WORLD, size, ierr)

    next = mod((rank + 1), size)
    from = mod((rank + size - 1), size)
    if (rank .eq. 0) then
       num(pos) = 30
       call mpi_send(num, length, MPI_INTEGER, next, tag, MPI_COMM_WORLD, ierr)
    endif
  
10  call mpi_recv(num, length, MPI_INTEGER, from, tag, MPI_COMM_WORLD, MPI_STATUS_IGNORE, ierr)
    if (rank .eq. 0) then
        num(pos) = num(pos) - 1
    endif
    call mpi_send(num, length, MPI_INTEGER, next, tag, MPI_COMM_WORLD, ierr)
  
    if (num(pos) .eq. 0) then
        goto 20
    endif
    goto 10
  
20  if (rank .eq. 0) then
        call mpi_recv(num, length, MPI_INTEGER, from, tag, MPI_COMM_WORLD, MPI_STATUS_IGNORE, ierr)
    endif
  
    call mpi_barrier(MPI_COMM_WORLD, ierr)
    call mpi_finalize(ierr)
end program ring_mpi\n");
    if (! $x->{success}) {
        $ret->{result_message} = $x->{result_message};
        return $ret;
    }

    #
    # Fortran "use mpi_f08" interface
    #

    $x = MTT::Files::SafeWrite($force, "hello_usempif08.f90", "!
! This program is automatically generated via the \"Trivial\" Test::Get
! module of the MPI Testing Tool (MTT).  Any changes you make here may
! get lost!
!
! Copyrights and licenses of this file are the same as for the MTT.
!

program hello_mpif08
    use mpi_f08
    implicit none
    integer rank, size
    call MPI_INIT()
    call MPI_COMM_RANK(MPI_COMM_WORLD, rank)
    call MPI_COMM_SIZE(MPI_COMM_WORLD, size)
    print *, 'Hello, Fortran mpi_f08 world, I am ', rank, ' of ', size
    call MPI_FINALIZE()
end program hello_mpif08\n");
    if (! $x->{success}) {
        $ret->{result_message} = $x->{result_message};
        return $ret;
    }

    $x = MTT::Files::SafeWrite($force, "ring_usempif08.f90", "!
! This program is automatically generated via the \"Trivial\" Test::Get
! module of the MPI Testing Tool (MTT).  Any changes you make here may
! get lost!
!
! Copyrights and licenses of this file are the same as for the MTT.
!

program ring_mpif08
    use mpi_f08
    implicit none
    integer rank, size, tag, next, from
    integer done
    integer length, pos
    integer num(20)
    integer initial_value
  
    tag = 201
    length = 20
    pos = length - 10
    initial_value = 10

    call mpi_init()
    call mpi_comm_rank(MPI_COMM_WORLD, rank)
    call mpi_comm_size(MPI_COMM_WORLD, size)

    next = mod((rank + 1), size)
    from = mod((rank + size - 1), size)
    if (rank .eq. 0) then
       num(pos) = 30
       call mpi_send(num, length, MPI_INTEGER, next, tag, MPI_COMM_WORLD)
    endif
  
10  call mpi_recv(num, length, MPI_INTEGER, from, tag, MPI_COMM_WORLD, MPI_STATUS_IGNORE)
    if (rank .eq. 0) then
        num(pos) = num(pos) - 1
    endif
    call mpi_send(num, length, MPI_INTEGER, next, tag, MPI_COMM_WORLD)
  
    if (num(pos) .eq. 0) then
        goto 20
    endif
    goto 10
  
20  if (rank .eq. 0) then
        call mpi_recv(num, length, MPI_INTEGER, from, tag, MPI_COMM_WORLD, MPI_STATUS_IGNORE)
    endif
  
    call mpi_barrier(MPI_COMM_WORLD)
    call mpi_finalize()
end program ring_mpif08\n");
    if (! $x->{success}) {
        $ret->{result_message} = $x->{result_message};
        return $ret;
    }

    # All done
    $ret->{test_result} = MTT::Values::PASS;
    $ret->{have_new} = $x->{success};
    $ret->{prepare_for_install} = "MTT::Common::Copytree::PrepareForInstall";
    $ret->{module_data}->{directory} = MTT::DoCommand::cwd();
    $ret->{result_message} = "Success";
    return $ret;
} 

1;
