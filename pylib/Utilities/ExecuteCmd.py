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

    def execute(self, options, cmdargs, testDef):
        # if this is a dryrun, just declare success
        if 'dryrun' in testDef.options and testDef.options['dryrun']:
            return (0, None, None, 0)

        #  check the options for a directive to merge
        # stdout into stderr
        try:
            if options['merge_stdout_stderr']:
                merge = True
            else:
                merge = False
        except:
            merge = False
        # check for line limits
        try:
            if options['stdout_save_lines'] is None or options['stdout_save_lines'] < 0:
                stdoutlines = 0
            else:
                stdoutlines = -1 * int(options['stdout_save_lines'])
        except:
            stdoutlines = 0
        try:
            if options['stderr_save_lines'] is None or options['stderr_save_lines'] < 0:
                stderrlines = 0
            else:
                stderrlines = -1 * int(options['stderr_save_lines'])
        except:
            stderrlines = 0
        # check for timing request
        try:
            if options['cmdtime'] or options['time']:
                time_exec = True
            else:
                time_exec = False
        except:
            time_exec = False
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

        except OSError as e:
            return (1, None, str(e), elapsed_secs)

        p.wait()

        return (p.returncode, stdout[stdoutlines:], stderr[stderrlines:], elapsed_secs)
