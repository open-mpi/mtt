
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
import os
import datetime
from BaseMTTUtility import *

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

    def reset(self):
        self.results = []
        self.stage_start = {}

    def print_name(self):
        return "Logger"

    def print_options(self, testDef, prefix):
        lines = testDef.printOptions(self.options)
        for line in lines:
            print(prefix + line)
            sys.stdout.flush()
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
        return

    def get_dict_contents(self, dic):
        return self.get_tuplelist_contents(list(dic.items()))

    def get_tuplelist_contents(self, tuplelist):
        if not tuplelist:
            return []
        max_keylen = max([len(key) for key,_ in tuplelist])
        return ["%s = %s" % (k.rjust(max_keylen), o) for k,o in tuplelist]

    def print_cmdline_args(self, testDef):
        if not (testDef and testDef.options):
            print("Error: print_cmdline_args was called too soon. Continuing...")
            sys.stdout.flush()
            return
        header_to_print = "CMDLINE_ARGS"
        strs_to_print = self.get_dict_contents(testDef.options)
        self.verbose_print("="*max([len(header_to_print),len(strs_to_print[0])]))
        self.verbose_print(header_to_print)
        self.verbose_print("="*max([len(header_to_print),len(strs_to_print[0])]))
        for s in strs_to_print:
            self.verbose_print(s)
        self.verbose_print("")
        # Log to elog file for injesting into ELK
        if testDef.elkLogger is not None and testDef.options['elk_id'] is not None:
            testDef.elkLogger.log_to_elk({'environment': dict(os.environ), 'options': testDef.options}, 'environment', testDef)

    def stage_start_print(self, stagename):
        self.stage_start[stagename] = datetime.datetime.now()
        if self.printout:
            to_print="START EXECUTING [%s] start_time=%s" % (stagename, self.stage_start[stagename])
            self.verbose_print("")
            self.verbose_print("="*len(to_print))
            self.verbose_print(to_print)
            self.verbose_print("="*len(to_print))

    def stage_end_print(self, stagename, log):
        stage_end = datetime.datetime.now()
        if self.printout:
            to_print="DONE EXECUTING [%s] end_time=%s, elapsed=%s" % (stagename, stage_end, stage_end-self.stage_start[stagename])
            self.verbose_print(to_print)
            self.verbose_print("STATUS OF [%s] IS %d" % (stagename, log['status']))
            self.verbose_print("")
        log['elapsed'] = (stage_end-self.stage_start[stagename]).total_seconds()
        log['starttime'] = self.stage_start[stagename]
        log['endtime'] = stage_end

    def verbose_print(self, string, timestamp=None):
        if self.printout:
            try:
                print(("%s%s" % ("%s "%(datetime.datetime.now() if timestamp is None else timestamp) \
                            if (self.timestampeverything or timestamp) else "", string)), file=self.fh)
                sys.stdout.flush()
            except UnicodeEncodeError as e:
                print("Error: Could not verbose print due to a UnicodeEncodeError")
                print(e)
                sys.stdout.flush()
            return

    def timestamp(self):
        if self.timestamp:
            return datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')

    def close(self):
        if self.fh is not sys.stdout:
            self.fh.close()
        return

    def logResults(self, title, result, testDef):
        self.verbose_print("LOGGING results for " + title)
        self.results.append(result)
        # Log to elog file for injesting into ELK
        if testDef.elkLogger is not None and testDef.options['elk_id'] is not None:
            testDef.elkLogger.log_to_elk(result, 'section', testDef)
        return

    def outputLog(self):
        # cycle across the logged results and output
        # them to the logging file
        for result in self.results:
            try:
                if result['status'] is not None:
                    print("Section " + result['section'] + ": Status " + str(result['status']), file=self.fh)
                    sys.stdout.flush()
                    if 0 != result['status']:
                        try:
                            print("    " + result['stderr'], file=self.fh)
                            sys.stdout.flush()
                        except KeyError:
                            pass
            except KeyError:
                print("Section " + result['section'] + " did not return a status", file=self.fh)
                sys.stdout.flush()
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
