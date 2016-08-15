#!/usr/bin/env python
#
# Copyright (c) 2016      Intel, Inc. All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

import os
import sys
from BaseMTTUtility import *

class MPIVersion(BaseMTTUtility):
    def __init__(self):
        BaseMTTUtility.__init__(self)
        self.options = {}
        return

    def print_name(self):
        return "MPIVersion"

    def print_options(self, testDef, prefix):
        lines = testDef.printOptions(self.options)
        for line in lines:
            print(prefix + line)
        return

    def execute(self, log, testDef):

        version_str = self.get_version_string(testDef)
        
        name = None
        version = None

        # Open MPI
        # Example Output:
        # Open MPI v1.10.2, package: Open MPI abuild@ip-172-31-24-182.us-west-2.compute.internal Distribution, ident: 1.10.2, repo rev: v1.10.1-145-g799148f, Jan 21, 2016
        if 'Open MPI' in version_str:
            name = 'Open MPI'
            version = version_str.split('Open MPI v')[1].split(', ')[0]

        # MVAPICH2
        # Example Output:
        # MVAPICH2 Version      : 2.1
        # MVAPICH2 Release date : Fri Apr 03 20:00:00 EDT 2015
        # MVAPICH2 Device       : ch3:mrail
        # MVAPICH2 configure    : --prefix=/opt/ohpc/pub/mpi/mvapich2-gnu-ohpc/2.1 --enable-cxx --enable-g=dbg --with-device=ch3:mrail --enable-fast=O3
        # MVAPICH2 CC           : gcc    -g -O3
        # MVAPICH2 CXX          : g++   -g -O3
        # MVAPICH2 F77          : gfortran -L/lib -L/lib   -g -O3
        # MVAPICH2 FC           : gfortran   -g -O3
        elif 'MVAPICH2' in version_str:
            name = 'MVAPICH2'
            version = version_str.split('MVAPICH2 Version')[1].split(':')[1].split('\n')[0].strip()
        # Intel MPI
        # Example Output:        
        # Intel(R) MPI Library 5.1.3 for Linux* OS
        elif 'Intel' in version_str:
            name = 'Intel MPI'
            version = version_str.split('Intel(R) MPI Library ')[1].split(' ')[0]

        # record the result
        log['name'] = str(name)
        log['version'] = str(version)
        return

    def get_version_string(self, testDef):
        cwd = os.getcwd()
        os.chdir(os.path.dirname(os.path.realpath(sys.modules[self.__module__].__file__)))
        status, _, _ = testDef.execmd.execute('mpicc -o mpi_get_version mpi_get_version.c'.split(), testDef)
        if 0 != status:
            os.chdir(cwd)
            return None
        status, stdout, _ = testDef.execmd.execute('./mpi_get_version'.split(), testDef)
        if 0 != status:
            os.chdir(cwd)
            return None
        
        os.chdir(cwd)
        return stdout

