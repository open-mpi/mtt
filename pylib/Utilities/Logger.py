from __future__ import print_function
from builtins import str
#!/usr/bin/env python
#
# Copyright (c) 2015-2018 Intel, Inc. All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

import sys
import datetime
from BaseMTTUtility import *
import json
import os

## @addtogroup Utilities
# @{
# @section Logger
# Log results and provide debug output when directed
# @}
class Logger(BaseMTTUtility):
    def __init__(self):
        BaseMTTUtility.__init__(self)
        self.fh = sys.stdout
        self.results = []
        self.options = {}
        self.printout = False
        self.timestamp = False
        self.cmdtimestamp = False
        self.timestampeverything = False
        self.stage_start = {}
        self.elk = None
        self.current_section = None
        self.execmds_stash = []

    def reset(self):
        self.results = []
        self.stage_start = {}

    def print_name(self):
        return "Logger"

    def print_options(self, testDef, prefix):
        lines = testDef.printOptions(self.options)
        for line in lines:
            self.print(prefix + line)
        return

    def open(self, testDef):
        # init the logging file handle
        try:
            if testDef.options['logfile'] is not None:
                self.fh = open(testDef.options['logfile'], 'w')
            else:
                self.fh = sys.stdout
        except KeyError:
            self.fh = sys.stdout
        # define the verbosity/debug flags
        try:
            if testDef.options['verbose']:
                self.printout = True
        except KeyError:
            pass
        try:
            if testDef.options['extraverbose']:
                self.printout = True
                self.timestamp = True
                self.cmdtimestamp = True
                self.timestampeverything = True
        except KeyError:
            pass
        try:
            if testDef.options['debug']:
                self.printout = True
        except KeyError:
            pass
        try:
            if testDef.options['dryrun']:
                self.printout = True
        except KeyError:
            pass
        # define the time flags
        try:
            if testDef.options['cmdtime']:
                self.timestamp = True
                self.cmdtimestamp = True
        except KeyError:
            pass
        try:
            if testDef.options['time']:
                self.timestamp = True
                self.cmdtimestamp = True
        except KeyError:
            pass
        try:
            if testDef.options['elk'] is not None:
                self.elk = testDef.options['elk']
        except KeyError:
            pass
        return

    def get_dict_contents(self, dic):
        return self.get_tuplelist_contents(dic.items())

    def get_tuplelist_contents(self, tuplelist):
        if not tuplelist:
            return []
        max_keylen = max([len(key) for key,_ in tuplelist])
        return ["%s = %s" % (k.rjust(max_keylen), o) for k,o in tuplelist]

    def print_cmdline_args(self, testDef):
        if not (testDef and testDef.options):
            self.verbose_print("Error: print_cmdline_args was called too soon. Continuing...")
            return
        header_to_print = "CMDLINE_ARGS"
        strs_to_print = self.get_dict_contents(testDef.options)
        self.verbose_print("="*max([len(header_to_print),len(strs_to_print[0])]))
        self.verbose_print(header_to_print)
        self.verbose_print("="*max([len(header_to_print),len(strs_to_print[0])]))
        for s in strs_to_print:
            self.verbose_print(s)
        self.verbose_print("")
        if self.elk is not None:
            print('ENV_AND_OPTS', json.dumps({'execid': self.elk,
                                              'environment': dict(os.environ),
                                              'options': testDef.options}))

    def log_execmd_elk(self, cmdargs, status, stdout, stderr, timedout, starttime, endtime, elapsed_secs, slurm_job_ids):
        if self.elk is not None:
            self.execmds_stash.append({'cmdargs': cmdargs,
                                       'status': status,
                                       'stdout': stdout,
                                       'stderr': stderr,
                                       'timedout': timedout,
                                       'starttime': starttime,
                                       'endtime': endtime,
                                       'elapsed': elapsed_secs,
                                       'slurm_job_ids': slurm_job_ids})

    def stage_start_print(self, stagename):
        self.stage_start[stagename] = datetime.datetime.now()
        if self.printout:
            to_print="START EXECUTING [%s] start_time=%s" % (stagename, self.stage_start[stagename])
            self.verbose_print("")
            self.verbose_print("="*len(to_print))
            self.verbose_print(to_print)
            self.verbose_print("="*len(to_print))
        self.current_section = stagename

    def stage_end_print(self, stagename, log):
        stage_end = datetime.datetime.now()
        if self.printout:
            to_print="DONE EXECUTING [%s] end_time=%s, elapsed=%s" % (stagename, stage_end, stage_end-self.stage_start[stagename])
            self.verbose_print(to_print)
            self.verbose_print("STATUS OF [%s] IS %d" % (stagename, log['status']))
            self.verbose_print("")
        log['time'] = (stage_end-self.stage_start[stagename]).total_seconds()
        log['time_start'] = self.stage_start[stagename]
        log['time_end'] = stage_end
        if self.elk is not None:
            elklog = {}
            elklog['execid'] = self.elk
            elklog['location'] = log['location'] if 'location' in log else None
            elklog['section'] = log['section'] if 'section' in log else None
            elklog['status'] = log['status'] if 'status' in log else None
            elklog['stdout'] = log['stdout'] if 'stdout' in log else None
            elklog['elapsed'] = log['time'] if 'time' in log else None
            elklog['starttime'] = str(log['time_start']) if 'time_start' in log else None
            elklog['endtime'] = str(log['time_end']) if 'time_end' in log else None
            elklog['params'] = {k:v for k,v in log['parameters']} if 'parameters' in log else None
            elklog['commands'] = self.execmds_stash
            self.execmds_stash = []
            elklog['other'] = {}
            if 'compiler' in log:
                elklog['other']['compiler'] = log['compiler']['compiler']
                elklog['other']['compiler_status'] = log['compiler']['status']
                elklog['other']['compiler_version'] = log['compiler']['version']
            for k in log:
                if k != 'options' and k != 'parameters' \
                and k != 'time_start' and k != 'time_end' and k != 'time' \
                and k not in elklog and k not in elklog['other']:
                    elklog['other'][k] = str(log[k])
            print('SECTION', json.dumps(elklog))
        self.current_section = None


    def print(self, x, file=None):
        if self.elk is not None:
            return
        if file is None:
            file = self.fh
        print(x, file=file)

    def verbose_print(self, string, timestamp=None):
        if self.elk is not None:
            return
        if self.printout:
            try:
                print(("%s%s" % ("%s "%(datetime.datetime.now() if timestamp is None else timestamp) \
                            if (self.timestampeverything or timestamp) else "", string)), file=self.fh)
            except UnicodeEncodeError as e:
                print("Error: Could not verbose print due to a UnicodeEncodeError")
                print(e)
            return

    def timestamp(self):
        if self.timestamp:
            return datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')

    def close(self):
        if self.fh is not sys.stdout:
            self.fh.close()
        return

    def logResults(self, title, result):
        self.verbose_print("LOGGING results for " + title)
        self.results.append(result)
        return

    def outputLog(self):
        # cycle across the logged results and output
        # them to the logging file
        for result in self.results:
            try:
                if result['status'] is not None:
                    self.print("Section " + result['section'] + ": Status " + str(result['status']), file=self.fh)
                    if 0 != result['status']:
                        try:
                            self.print("    " + result['stderr'], file=self.fh)
                        except KeyError:
                            pass
            except KeyError:
                self.print("Section " + result['section'] + " did not return a status", file=self.fh)
        return

    def getLog(self, key):
        # if the key is None, then they want the entire
        # log list
        if key is None:
            return self.results
        # we have been passed the name of a section, so
        # see if we have its log in the results
        for result in self.results:
            try:
                if key == result['section']:
                    return result
            except KeyError:
                pass
        # if we get here, then the key wasn't found
        return None
