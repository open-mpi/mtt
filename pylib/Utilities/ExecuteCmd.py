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
import random


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

    def check_for_slurm_jobids(self, unique_identifier, prev_stdout, prev_stderr):
        '''Checks stdout, stderr, and also squeue for any hints of a slurm job
        that was run during the command that was executed
        '''
        slurm_jobids = []

        for l in prev_stdout:
            if l.startswith('Submitted batch job '):
                jobid = l.split(' ')[-1]
                if jobid.isdigit():
                    slurm_jobids.append(int(jobid))

        for l in prev_stderr:
            if l.startswith('salloc: Granted job allocation '):
                jobid = l.split(' ')[-1]
                if jobid.isdigit():
                    slurm_jobids.append(int(jobid))

        try:
            stdout = []
            p = subprocess.Popen(['squeue', '-o', '%i', '-h', '-t', 'all', '-n', unique_identifier],
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            with processTimeout(100000000, p.pid):
                while True:
                    reads = [p.stdout.fileno()]
                    ret = select.select(reads, [], [])
                    stdout_done = True
                    for fd in ret[0]:
                        if fd == p.stdout.fileno():
                            read = p.stdout.readline()
                            if read:
                                read = read.decode('utf-8').rstrip()
                                stdout.append(read)
                                stdout_done = False
                    if stdout_done:
                        break
            for l in stdout:
                if l.isdigit:
                    slurm_jobids.append(int(l))
        except:
            pass

        return slurm_jobids


    def execute(self, options, cmdargs, testDef, quiet=False):
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

        # unique identifier for capturing slurm jobids.
        # This identifier is used in check_for_slurm_jobids() function
        # along with squeue to capture any slurm job ids that contain the identifier
        unique_identifier = str(random.randint(0,999999999999))
        os.environ['SLURM_JOB_NAME'] = unique_identifier

        # setup the command arguments
        mycmdargs = []
        # if any cmd arg has quotes around it, remove
        # them here
        skip_i = set()
        for i,arg in enumerate(cmdargs):
            if i in skip_i:
                continue
            arg = arg.replace('\"','')
            # Look for any job names in cmdargs, and attach unique identifier
            if arg.startswith('--job-name='):
                unique_identifier = arg[len('--job-name='):] + unique_identifier
                arg = '--job-name=' + unique_identifier
                mycmdargs.append(arg)
            elif cmdargs[0] == 'srun' and (arg == '-J' or arg == '--job-name'):
                skip_i.add(i + 1)
                unique_identifier = cmdargs[i + 1] + unique_identifier
                mycmdargs.append(arg)
                mycmdargs.append(unique_identifier)
            else:
                mycmdargs.append(arg)
        testDef.logger.verbose_print("ExecuteCmd start: " + ' '.join(mycmdargs), timestamp=datetime.datetime.now() if time_exec else None)

        if not mycmdargs:
            testDef.logger.verbose_print("ExecuteCmd error: no cmdargs")
            if not quiet:
                testDef.logger.log_execmd_elk(cmdargs,
                                              1, None,
                                              'ExecuteCmd error: no cmdargs',
                                              None,
                                              datetime.datetime.now(),
                                              datetime.datetime.now(),
                                              0, None)
            return (1, [], ["MTT ExecuteCmd error: no cmdargs"], 0)

        # define storage to catch the output
        stdout = []
        stderr = []

        # start the process so that we can catch an exception
        # if it times out, assuming timeout was set
        results = {}
        p = None

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
                    ret = select.select([p.stdout.fileno(), p.stderr.fileno()], [], [])

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
            p.wait()

            endtime = datetime.datetime.now()

            if p.returncode == -15 or p.returncode == -9:
                # check if slurm was run, and record job ids
                slurm_jobids = self.check_for_slurm_jobids(unique_identifier, stdout, stderr)
                # print execmd timed out info, including any slurm job ids
                testDef.logger.verbose_print("ExecuteCmd Timed Out%s%s" % (" : elapsed=%s"%elapsed_datetime if time_exec else "", \
                                                                           " : slurm_jobids=%s" % ','.join([str(j) for j in slurm_jobids]) if slurm_jobids else ""), \
                                             timestamp=endtime if time_exec else None)
                stderr.append("**** TIMED OUT ****")
                results['timedout'] = True
                results['status'] = p.returncode
                results['stdout'] = stdout[-1 * stdoutlines:]
                results['stderr'] = stderr[-1 * stderrlines:]
                results['slurm_job_ids'] = slurm_jobids
                if time_exec:
                    endtime = datetime.datetime.now()
                    elapsed_datetime = endtime - starttime
                    results['elapsed_secs'] = elapsed_datetime.total_seconds()

                if not quiet:
                    testDef.logger.log_execmd_elk(cmdargs,
                                                  results['status'] if 'status' in results else None,
                                                  results['stdout'] if 'stdout' in results else None,
                                                  results['stderr'] if 'stderr' in results else None,
                                                  results['timedout'] if 'timedout' in results else None,
                                                  starttime,
                                                  endtime,
                                                  (endtime - starttime).total_seconds,
                                                  results['slurm_job_ids'] if 'slurm_job_ids' in results else None)
                return results

            if time_exec:
                elapsed_datetime = endtime - starttime
                results['elapsed_secs'] = elapsed_datetime.total_seconds()

            # check if slurm was run, and record job ids
            slurm_jobids = self.check_for_slurm_jobids(unique_identifier, stdout, stderr)
            # print execmd info, including any slurm job ids
            testDef.logger.verbose_print("ExecuteCmd done%s%s" % (" : elapsed=%s" % elapsed_datetime if time_exec else "", \
                                                                  " : slurm_jobids=%s" % ','.join([str(j) for j in slurm_jobids]) if slurm_jobids else ""), \
                                         timestamp=endtime if time_exec else None)

            results['status'] = p.returncode
            results['stdout'] = stdout[-1 * stdoutlines:]
            results['stderr'] = stderr[-1 * stderrlines:]
            results['slurm_job_ids'] = slurm_jobids
        except OSError as e:
            if p:
                p.wait()
            endtime = datetime.datetime.now()
            results['status'] = 1
            results['stdout'] = []
            results['stderr'] = [str(e)]
            results['slurm_job_ids'] = []

        if not quiet:
            testDef.logger.log_execmd_elk(cmdargs,
                                          results['status'] if 'status' in results else None,
                                          results['stdout'] if 'stdout' in results else None,
                                          results['stderr'] if 'stderr' in results else None,
                                          results['timedout'] if 'timedout' in results else None,
                                          starttime,
                                          endtime,
                                          (endtime - starttime).total_seconds(),
                                          results['slurm_job_ids'] if 'slurm_job_ids' in results else None)

        return results
