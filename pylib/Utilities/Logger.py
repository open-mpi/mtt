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
import datetime
from BaseMTTUtility import *

class Logger(BaseMTTUtility):
    def __init__(self):
        BaseMTTUtility.__init__(self)
        self.fh = sys.stdout
        self.results = []
        self.options = {}

    def print_name(self):
        return "Logger"

    def print_options(self, testDef, prefix):
        lines = testDef.printOptions(self.options)
        for line in lines:
            print prefix + line
        return

    def open(self, options):
        # init the logging file handle
        self.fh = open(options.logfile, 'w') if options.logfile else sys.stdout
        return

    def verbose_print(self, options, str):
        if options.verbose or options.debug or options.dryrun:
            print >> self.fh, str
        return

    def timestamp(self, options):
        if options.sectime:
            print >> self.fh, datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        return

    def close(self):
        if self.fh is not sys.stdout:
            self.fh.close()
        return

    def logResults(self, title, result):
        self.results.append(result)
        return

    def outputLog(self):
        # cycle across the logged results and output
        # them to the logging file
        for result in self.results:
            try:
                if result['status'] is not None:
                    print >> self.fh, "Stage " + result['stage'] + ": Status " + str(result['status'])
            except KeyError:
                print >> self.fh, "Stage " + result['stage'] + " did not return a status"
        return

    def getLog(self, key):
        # we have been passed the name of a stage, so
        # see if we have its log in the results
        for result in self.results:
            try:
                if key == result['stage']:
                    return result
            except KeyError:
                pass
        # if we get here, then the key wasn't found
        return None
