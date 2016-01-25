#!/usr/bin/env python
#
# Copyright (c) 2015-2016 Intel, Inc. All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

import sys
import select
import subprocess
from BaseMTTUtility import *

class ExecuteCmd(BaseMTTUtility):
    def __init__(self):
        BaseMTTUtility.__init__(self)
        self.options = {}
        return

    def print_name(self):
        return "ExecuteCmd"

    def print_options(self, testDef, prefix):
        lines = testDef.printOptions(self.options)
        for line in lines:
            print prefix + line
        return

    def execute(self, cmdargs, testDef):
        testDef.logger.verbose_print(testDef.options, "ExecuteCmd")
        # if this is a dryrun, just declare success
        if testDef.options.dryrun:
            return (0, None, None)
        mycmdargs = []
        # if any cmd arg has quotes around it, remove
        # them here
        for arg in cmdargs:
            mycmdargs.append(arg.replace('\"',''))
        # open a subprocess with stdout and stderr
        # as distinct pipes so we can capture their
        # output as the process runs
        p = subprocess.Popen(mycmdargs,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        # define storage to catch the output
        stdout = []
        stderr = []

        # loop until the pipes close
        while True:
            reads = [p.stdout.fileno(), p.stderr.fileno()]
            ret = select.select(reads, [], [])

            for fd in ret[0]:
                # if the data
                if fd == p.stdout.fileno():
                    read = p.stdout.readline().rstrip()
                    testDef.logger.verbose_print(testDef.options, 'stdout: ' + read)
                    stdout.append(read)
                elif fd == p.stderr.fileno():
                    read = p.stderr.readline().rstrip()
                    testDef.logger.verbose_print(testDef.options, 'stderr: ' + read)
                    stderr.append(read)

            if p.poll() != None:
                break

        output = "\n".join(stdout)
        errors = "\n".join(stderr)
        return (p.returncode, output, errors)
