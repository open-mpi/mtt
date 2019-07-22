#!/usr/bin/env python
#
# Copyright (c) 2015-2019 Intel, Inc.  All rights reserved.
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
import signal
import os, threading, errno
from contextlib import contextmanager
from BaseMTTUtility import *


class TimeoutThread(object):
    def __init__(self, seconds):
        self.seconds = seconds
        self.cond = threading.Condition()
        self.cancelled = False
        self.thread = threading.Thread(target=self._wait)

    def run(self):
        # start the timer
        self.thread.start()

    def _wait(self):
        with self.cond:
            self.cond.wait(self.seconds)

            if not self.cancelled:
                self.timed_out()

    def cancel(self):
        # cancel the timeout, if it hasn't already fired
        with self.cond:
            self.cancelled = True
            self.cond.notify()
        self.thread.join()

    def timed_out(self):
        # raise exception to signal timeout
        raise NotImplementedError

class KillProcessThread(TimeoutThread):
    def __init__(self, seconds, pid):
        super(KillProcessThread, self).__init__(seconds)
        self.pid = pid

    def timed_out(self):
        # be polite and provide a SIGTERM to let them
        # exit cleanly
        try:
            os.kill(self.pid, signal.SIGTERM)
        except OSError as e:
            # if it is already gone, then ignore the
            # error - just a race condition
            if e.errno not in (errno.EPERM, errno. ESRCH):
                raise e
        # wait a little bit
        time.sleep(1)
        # hammer it with a cannonball
        try:
            os.kill(self.pid, signal.SIGKILL)
        except OSError as e:
            # If the process is already gone, ignore the error.
            if e.errno not in (errno.EPERM, errno. ESRCH):
                raise e

@contextmanager
def processTimeout(seconds, pid):
    timeout = KillProcessThread(seconds, pid)
    timeout.run()
    try:
        yield
    finally:
        timeout.cancel()


## @addtogroup Utilities
# @{
# @section ExecuteCmd
# Execute a command and capture its stdout and stderr
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
            return (0, [], [], 0)

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
            return (1, [], ["MTT ExecuteCmd error: no cmdargs"], 0)

        # define storage to catch the output
        stdout = []
        stderr = []

        # start the process so that we can catch an exception
        # if it times out, assuming timeout was set
        results = {}
        p = None
        if time_exec:
            starttime = datetime.datetime.now()

        # it is possible that the command doesn't exist or
        # isn't in our path, so protect us
        try:
            # open a subprocess with stdout and stderr
            # as distinct pipes so we can capture their
            # output as the process runs
            p = subprocess.Popen(mycmdargs,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            if options is not None and 'timeout' in options and options['timeout'] is not None:
                t = int(options['timeout'])
            else:
                t = 100000000
            with processTimeout(t, p.pid):
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
            if p.returncode == -15 or p.returncode == -9:
                testDef.logger.verbose_print("ExecuteCmd Timed Out%s" % (": elapsed=%s"%elapsed_datetime if time_exec else ""), \
                                             timestamp=endtime if time_exec else None)
                stderr.append("**** TIMED OUT ****")
                results['timedout'] = True
                results['status'] = p.returncode
                results['stdout'] = stdout[-1 * stdoutlines:]
                results['stderr'] = stderr[-1 * stderrlines:]
                if time_exec:
                    endtime = datetime.datetime.now()
                    elapsed_datetime = endtime - starttime
                    results['elapsed_secs'] = elapsed_datetime.total_seconds()
                return results

            if time_exec:
                endtime = datetime.datetime.now()
                elapsed_datetime = endtime - starttime
                results['elapsed_secs'] = elapsed_datetime.total_seconds()

            testDef.logger.verbose_print("ExecuteCmd done%s" % (": elapsed=%s"%elapsed_datetime if time_exec else ""), \
                                         timestamp=endtime if time_exec else None)

            p.wait()
            results['status'] = p.returncode
            results['stdout'] = stdout[-1 * stdoutlines:]
            results['stderr'] = stderr[-1 * stderrlines:]
        except OSError as e:
            if p:
                p.wait()
            results['status'] = 1
            results['stdout'] = []
            results['stderr'] = [str(e)]
            return results

        return results
