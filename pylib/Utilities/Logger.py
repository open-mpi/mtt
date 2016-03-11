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
        self.printout = False
        self.timestamp = False

    def print_name(self):
        return "Logger"

    def print_options(self, testDef, prefix):
        lines = testDef.printOptions(self.options)
        for line in lines:
            print prefix + line
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
        except KeyError:
            pass
        try:
            if testDef.options['cmdtime']:
                self.timestamp = True
        except KeyError:
            pass
        try:
            if testDef.options['time']:
                self.timestamp = True
        except KeyError:
            pass
        return

    def verbose_print(self, str):
        if self.printout:
            print >> self.fh, str
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
                    print >> self.fh, "Section " + result['section'] + ": Status " + str(result['status'])
                    if 0 != result['status']:
                        try:
                            print >> self.fh,"    " + result['stderr']
                        except KeyError:
                            pass
            except KeyError:
                print >> self.fh, "Section " + result['section'] + " did not return a status"
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
