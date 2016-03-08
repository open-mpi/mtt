# -*- coding: utf-8; tab-width: 4; indent-tabs-mode: f; python-indent: 4 -*-
#
# Copyright (c) 2015-2016 Intel, Inc. All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

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
            print prefix + line
        return

    def execute(self, log, keyvals, testDef):
        testDef.logger.verbose_print(testDef.options, "TextFile Reporter")
        # pickup the options
        cmds = {}
        testDef.parseOptions(log, self.options, keyvals, cmds)
        if cmds['filename'] is not None:
            self.fh = open(cmds['filename'][0], 'w')
        if testDef.options.description is not None:
            print >> self.fh,testDef.options.description
            print >> self.fh
        # get the entire log of results
        fullLog = testDef.logger.getLog(None)
        for lg in fullLog:
            try:
                print >> self.fh,"Section:",lg['section'],"Status:",lg['status']
                try:
                    if lg['parameters'] is not None:
                        for p in lg['parameters']:
                            print >> self.fh,"\t",p[0],"=",p[1]
                except KeyError:
                    pass
            except KeyError:
                pass
            try:
                if lg['numTests'] is not None:
                    print >> self.fh,"Tests:",lg['numTests'],"Pass:",lg['numPass'],"Skip:",lg['numSkip'],"Fail:",lg['numFail']
            except KeyError:
                pass
            print >> self.fh
        log['status'] = 0
        return
