# -*- coding: utf-8; tab-width: 4; indent-tabs-mode: f; python-indent: 4 -*-
#
# Copyright (c) 2015-2016 Intel, Inc. All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#


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
        print log
        testDef.logger.verbose_print(testDef.options, "TestFile Reporter")
        testDef.logger.outputLog()
        log['status'] = 0
        return
