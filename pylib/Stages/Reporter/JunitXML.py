# -*- coding: utf-8; tab-width: 4; indent-tabs-mode: f; python-indent: 4 -*-
#
# Copyright (c) 2015-2018 Intel, Inc. All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

from __future__ import print_function
import os
import sys
import re
from junit_xml import TestSuite, TestCase
from ReporterMTTStage import *

## @addtogroup Stages
# @{
# @addtogroup Reporter
# @section JunitXML
# @param filename    Name of the file into which the report is to be written
# @param textwrap    Max line length before wrapping
# @}
class JunitXML(ReporterMTTStage):

    def __init__(self):
        # initialise parent class
        ReporterMTTStage.__init__(self)
        self.options = {}
        self.options['filename'] = (None, "Name of the file into which the report is to be written")
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
        return "JunitXML"

    def print_options(self, testDef, prefix):
        lines = testDef.printOptions(self.options)
        for line in lines:
            print(prefix + line)
        return

    def execute(self, log, keyvals, testDef):
        testDef.logger.verbose_print("JunitXML Reporter")
        # pickup the options
        cmds = {}
        testDef.parseOptions(log, self.options, keyvals, cmds)
        if cmds['filename'] is not None:
            self.fh = open(cmds['filename'], 'w')
        if testDef.options['description'] is not None:
            print(testDef.options['description'], file=self.fh)
            print(file=self.fh)
       
        # Use the Junit classname field to store the list of inifiles
        try:
            classname = testDef.log['inifiles']
        except KeyError:
            classname = None
        # get the entire log of results
        fullLog = testDef.logger.getLog(None)
        testCases = []
        # TODO: ain't nobody got time for that.  8-).
        time = 0
        for lg in fullLog:
            if 'stdout' in lg and lg['stdout'] is not None:
                stdout = "\n".join(lg['stdout'])
            else:
                stdout = None
            if 'stderr' in lg and lg['stderr'] is not None:
                stderr = "\n".join(lg['stderr'])
            else:
                stderr = None
            if 'time' in lg and lg['time'] is not None:
                time = lg['time']
            else:
                time = 0
            tc = TestCase(lg['section'], classname, time, stdout, stderr)
            try:
                if 0 != lg['status']:
                    # Find sections prefixed with 'TestRun'
                    if re.match("TestRun", lg['section']):
                        tc.add_failure_info("Test reported failure")
                    else:
                        tc.add_error_info("Test error")
            except KeyError:
                sys.exit(lg['section'] + " is missing status!")
            testCases.append(tc)

        # TODO:  Pull in the resource manager jobid.
        jobid = "job1"
        ts = TestSuite(jobid, testCases)
        print(TestSuite.to_xml_string([ts]), file=self.fh)

        if cmds['filename'] is not None:
            self.fh.close()
        log['status'] = 0
        return
