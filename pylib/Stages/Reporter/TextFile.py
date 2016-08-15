# -*- coding: utf-8; tab-width: 4; indent-tabs-mode: f; python-indent: 4 -*-
#
# Copyright (c) 2015-2016 Intel, Inc. All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

from __future__ import print_function
import os
import sys
from ReporterMTTStage import *

class TextFile(ReporterMTTStage):

    def __init__(self):
        # initialise parent class
        ReporterMTTStage.__init__(self)
        self.options = {}
        self.options['filename'] = (None, "Name of the file into which the report is to be written")
        self.options['summary_footer'] = (None, "Footer to be placed at bottom of summary")
        self.options['detail_header'] = (None, "Header to be put at top of detail report")
        self.options['detail_footer'] = (None, "Footer to be placed at bottome of detail report")
        self.options['textwrap'] = ("80", "Max line length before wrapping")
        self.fh = sys.stdout

    def activate(self):
        # get the automatic procedure from IPlugin
        IPlugin.activate(self)
        return


    def deactivate(self):
        IPlugin.deactivate(self)
        return

    def print_name(self):
        return "TextFile"

    def print_options(self, testDef, prefix):
        lines = testDef.printOptions(self.options)
        for line in lines:
            print(prefix + line)
        return

    def execute(self, log, keyvals, testDef):
        testDef.logger.verbose_print("TextFile Reporter")
        # pickup the options
        cmds = {}
        testDef.parseOptions(log, self.options, keyvals, cmds)
        if cmds['filename'] is not None:
            self.fh = open(cmds['filename'], 'w')
        if testDef.options['description'] is not None:
            print(testDef.options['description'], file=self.fh)
            print(file=self.fh)
        # get the entire log of results
        fullLog = testDef.logger.getLog(None)
        for lg in fullLog:
            try:
                print("Section:",lg['section'],"Status:",lg['status'], file=self.fh)
                try:
                    if lg['parameters'] is not None:
                        print("\tInput parameters:", file=self.fh)
                        for p in lg['parameters']:
                            print("\t\t",p[0],"=",p[1], file=self.fh)
                except KeyError:
                    pass
                try:
                    if lg['options'] is not None:
                        print("\tFinal options:", file=self.fh)
                        opts = lg['options']
                        keys = list(opts.keys())
                        for p in keys:
                            print("\t\t",p,"=",opts[p], file=self.fh)
                except KeyError:
                    pass
                if 0 != lg['status']:
                    try:
                        print("\tERROR:",lg['stderr'], file=self.fh)
                    except KeyError:
                        try:
                            print("\tERROR:",lg['stdout'], file=self.fh)
                        except KeyError:
                            pass
            except KeyError:
                pass
            try:
                if lg['compiler'] is not None:
                    print("Compiler:", file=self.fh)
                    comp = lg['compiler']
                    print("\t",comp['family'], file=self.fh)
                    print("\t",comp['version'], file=self.fh)
            except KeyError:
                pass
            try:
                if lg['profile'] is not None:
                    prf = lg['profile']
                    keys = list(prf.keys())
                    # find the max length of the keys
                    max1 = 0
                    for key in keys:
                        if len(key) > max1:
                            max1 = len(key)
                    # add some padding
                    max1 = max1 + 4
                    # now provide the output
                    print("\tProfile:", file=self.fh)
                    sp = " "
                    for key in keys:
                        line = key + (max1-len(key))*sp + prf[key]
                        print("\t\t",line, file=self.fh)
            except KeyError:
                pass
            try:
                if lg['numTests'] is not None:
                    print("\tTests:",lg['numTests'],"Pass:",lg['numPass'],"Skip:",lg['numSkip'],"Fail:",lg['numFail'], file=self.fh)
            except KeyError:
                pass
            try:
                if lg['testresults'] is not None:
                    for test in lg['testresults']:
                        tname = os.path.basename(test['test'])
                        print("\t\t",tname,"  Status:",test['status'], file=self.fh)
                        if 0 != test['status']:
                            print("\t\t\t","Stderr:",test['stderr'], file=self.fh)
            except KeyError:
                pass
            print(file=self.fh)
        if cmds['filename'] is not None:
            self.fh.close()
        log['status'] = 0
        return
