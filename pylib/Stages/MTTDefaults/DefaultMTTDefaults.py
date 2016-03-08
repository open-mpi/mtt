# -*- coding: utf-8; tab-width: 4; indent-tabs-mode: f; python-indent: 4 -*-
#
# Copyright (c) 2015-2016 Intel, Inc. All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

import os
from MTTDefaultsMTTStage import *

class DefaultMTTDefaults(MTTDefaultsMTTStage):

    def __init__(self):
        # initialise parent class
        MTTDefaultsMTTStage.__init__(self)
        self.options = {}
        self.options['force'] = (False, "Honestly don't remember")
        self.options['trial'] = (False, "Use when testing your MTT client setup; results that are generated and submitted to the database are marked as \"trials\" and are not included in normal reporting.")
        self.options['scratch'] = ("./mttscratch", "Specify the DIRECTORY under which scratch files are to be stored")
        self.options['logfile'] = (None, "Log all output to FILE (defaults to stdout)")
        self.options['description'] = (None, "Provide a brief title/description to be included in the log for this test")
        self.options['submit_group_results'] = (True, "Report results from each test section as it is completed")
        self.options['platform'] = (None, "Name of the system under test")
        self.options['organization'] = (None, "Name of the organization running the test")
        return

    def activate(self):
        # get the automatic procedure from IPlugin
        IPlugin.activate(self)
        return


    def deactivate(self):
        IPlugin.deactivate(self)
        return

    def print_name(self):
        return "DefaultMTTDefaults"

    def print_options(self, testDef, prefix):
        lines = testDef.printOptions(self.options)
        for line in lines:
            print prefix + line
        return

    def execute(self, log, keyvals, testDef):
        testDef.logger.verbose_print(testDef.options, "Set MTT Defaults")
