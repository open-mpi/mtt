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

## @addtogroup Utilities
# @{
# @section Logger
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
        self.sectimestamp = False
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
                self.sectimestamp = True
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
            if testDef.options['sectime']:
                self.timestamp = True
                self.sectimestamp = True
        except KeyError:
            pass
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
                self.sectimestamp = True
        except KeyError:
            pass
        return

    def stage_start_print(self, stagename, pluginname):
        self.stage_start[stagename] = datetime.datetime.now()
        if self.printout:
            print(("%sStart executing [%s] plugin=%s" % ("%s "%self.stage_start[stagename] if self.sectimestamp else "",
                                                            stagename, pluginname)), file=self.fh)

    def stage_end_print(self, stagename, pluginname, log):
        stage_end = datetime.datetime.now()
        if self.printout:
            print(("%sDone executing [%s] plugin=%s elapsed=%s" % ("%s "%stage_end if self.sectimestamp else "",
                                                           stagename, pluginname, stage_end-self.stage_start[stagename])), file=self.fh)
        log['time'] = (stage_end-self.stage_start[stagename]).total_seconds()
        log['time_start'] = self.stage_start[stagename]
        log['time_end'] = stage_end

    def verbose_print(self, string, timestamp=None):
        if self.printout:
            print(("%s%s" % ("%s "%(datetime.datetime.now() if timestamp is None else timestamp) \
                            if (self.timestampeverything or timestamp) else "", string)), file=self.fh)
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
                    print("Section " + result['section'] + ": Status " + str(result['status']), file=self.fh)
                    if 0 != result['status']:
                        try:
                            print("    " + result['stderr'], file=self.fh)
                        except KeyError:
                            pass
            except KeyError:
                print("Section " + result['section'] + " did not return a status", file=self.fh)
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
