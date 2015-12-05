#!/usr/bin/env python
#
# Copyright (c) 2015      Intel, Inc. All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

import sys
import datetime

class LoggerMTTUtility:
    def __init__(self):
        self.fh = sys.stdout

    def open(self, options):
        # init the logging file handle
        self.fh = open(options.logfile, 'w') if options.logfile else sys.stdout

    def verbose_print(self, options, str):
        if options.verbose or options.debug or options.dryrun:
            print >> self.fh, str

    def timestamp(self, options):
        if options.sectime:
            print >> self.fh, datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')

    def close(self):
        if self.fh is not sys.stdout:
            self.fh.close()
