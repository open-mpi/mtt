from __future__ import print_function
from builtins import str
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
            print(prefix + line)
        return

    def execute(self, cmdargs, testDef):
        testDef.logger.verbose_print("ExecuteCmd")
        # if this is a dryrun, just declare success
        try:
            if testDef.options['dryrun']:
                return (0, None, None)
        except KeyError:
            pass
        mycmdargs = []
        # if any cmd arg has quotes around it, remove
        # them here
        for arg in cmdargs:
            mycmdargs.append(arg.replace('\"',''))
        testDef.logger.verbose_print("ExecuteCmd: " + " " + '.'.join(mycmdargs))
        # it is possible that the command doesn't exist or
        # isn't in our path, so protect us
        try:
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
                        testDef.logger.verbose_print('stdout: ' + read.decode("utf-8"))
                        stdout.append(read.decode("utf-8"))
                    elif fd == p.stderr.fileno():
                        read = p.stderr.readline().rstrip()
                        testDef.logger.verbose_print('stderr: ' + read.decode("utf-8"))
                        stderr.append(read.decode("utf-8"))

                if p.poll() != None:
                    break
        except OSError as e:
            return (1, None, str(e))

        output = "\n".join(stdout)
        errors = "\n".join(stderr)
        return (p.returncode, output, errors)
