/* Copyright (c) 2015-2016 Intel, Inc. All rights reserved.
 * $COPYRIGHTS
 *
 * Additional copyrights may follow
 *
 * $HEADER$
 */

#include <mpi.h>
#include <stdio.h>

int main(int argc, char **argv) {
    MPI_Init(NULL, NULL);
    char version[1000];
    int resultlen;
    MPI_Get_library_version(version, &resultlen);
    printf("%s\n", version);

    return 0;
}
