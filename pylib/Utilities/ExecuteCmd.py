#!/usr/bin/env python
#
# Copyright (c) 2015-2018 Intel, Inc.  All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

from __future__ import print_function
from builtins import str
import sys
import select
import subprocess
import time
import datetime
from BaseMTTUtility import *

## @addtogroup Utilities
# @{
# @section ExecuteCmd
# @}
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

    def _bool_option(self, options, name):
        if options and name in options:
            val = options[name]
            if type(val) is bool:
                return val
            elif type(val) is str:
                val = val.strip().lower()
                return val in ['y', 'yes', 't', 'true', '1']
            else:
                return val > 0

        return False

    def _positive_int_option(self, options, name):
        val = None
        if options and name in options:
            val = options[name]
        if val is None or val < 0:
            return 0
        return int(val)

    def execute(self, options, cmdargs, testDef):
        # if this is a dryrun, just declare success
        if 'dryrun' in testDef.options and testDef.options['dryrun']:
            return (0, None, None, 0)

        #  check the options for a directive to merge
        # stdout into stderr
        merge = self._bool_option(options, 'merge_stdout_stderr')

        # check for line limits
        stdoutlines = self._positive_int_option(options, 'stdout_save_lines')
        stderrlines = self._positive_int_option(options, 'stderr_save_lines')

        # check for timing request
        t1 = self._bool_option(options, 'cmdtime')
        t2 = self._bool_option(options, 'time')
        time_exec = t1 or t2

        elapsed_secs = -1
        elapsed_datetime = None

        # setup the command arguments
        mycmdargs = []
        # if any cmd arg has quotes around it, remove
        # them here
        for arg in cmdargs:
            mycmdargs.append(arg.replace('\"',''))
        testDef.logger.verbose_print("ExecuteCmd start: " + ' '.join(mycmdargs), timestamp=datetime.datetime.now() if time_exec else None)

        if not mycmdargs:
            testDef.logger.verbose_print("ExecuteCmd error: no cmdargs")
            return (1, None, "MTT ExecuteCmd error: no cmdargs", 0)

        # it is possible that the command doesn't exist or
        # isn't in our path, so protect us
        p = None
        try:
            if time_exec:
                starttime = datetime.datetime.now()

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

                stdout_done = True
                stderr_done = True

                for fd in ret[0]:
                    # if the data
                    if fd == p.stdout.fileno():
                        read = p.stdout.readline()
                        if read:
                            read = read.decode('utf-8').rstrip()
                            testDef.logger.verbose_print('stdout: ' + read)
                            if merge:
                                stderr.append(read)
                            else:
                                stdout.append(read)
                            stdout_done = False
                    elif fd == p.stderr.fileno():
                        read = p.stderr.readline()
                        if read:
                            read = read.decode('utf-8').rstrip()
                            testDef.logger.verbose_print('stderr: ' + read)
                            stderr.append(read)
                            stderr_done = False

                if stdout_done and stderr_done:
                    break

            if time_exec:
                endtime = datetime.datetime.now()
                elapsed_datetime = endtime - starttime
                elapsed_secs = elapsed_datetime.total_seconds()

            testDef.logger.verbose_print("ExecuteCmd done%s" % (": elapsed=%s"%elapsed_datetime if time_exec else ""), \
                                         timestamp=endtime if time_exec else None)

            p.wait()

        except OSError as e:
            if p:
                p.wait()
            return (1, None, str(e), elapsed_secs)

        return (p.returncode,
                stdout[-1 * stdoutlines:],
                stderr[-1 * stderrlines:],
                elapsed_secs)
