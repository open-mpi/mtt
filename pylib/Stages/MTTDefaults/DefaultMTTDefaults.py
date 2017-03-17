# -*- coding: utf-8; tab-width: 4; indent-tabs-mode: f; python-indent: 4 -*-
#
# Copyright (c) 2015-2017 Intel, Inc.  All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

from __future__ import print_function
import os
from MTTDefaultsMTTStage import *

##
# @addtogroup Stages
# @{
# @addtogroup MTTDefaults
# @section DefaultMTTDefaults
# @param description             Provide a brief title/description to be included in the log for this test
# @param platform                Name of the system under test
# @param scratch                 Specify the DIRECTORY under which scratch files are to be stored
# @param trial                   Use when testing your MTT client setup; results that are generated and submitted to the database are marked as "trials" and are not included in normal reporting.
# @param organization            Name of the organization running the test
# @param logfile                 Log all output to FILE (defaults to stdout)
# @param submit_group_results    Report results from each test section as it is completed
# @}
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
        self.options['merge_stdout_stderr'] = (False, "Merge stdout and stderr into one output stream")
        self.options['stdout_save_lines'] = (-1, "Number of lines of stdout to save (-1 for unlimited)")
        self.options['stderr_save_lines'] = (-1, "Number of lines of stderr to save (-1 for unlimited)")
        self.options['executor'] = ('sequential', "Strategy to use: combinatorial or sequential executor")
        self.options['time'] = (True, "Record how long it takes to run each individual test")
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
            print(prefix + line)
        return

    def priority(self):
        return 5

    def execute(self, log, keyvals, testDef):
        testDef.logger.verbose_print("Set MTT Defaults")
        cmds = {}
        # the parseOptions function will record status for us
        testDef.parseOptions(log, self.options, keyvals, cmds)
        # we need to record the results into our options so
        # subsequent sections can capture them
        keys = cmds.keys()
        for key in keys:
            self.options[key] = (cmds[key], self.options[key][1])
        return
