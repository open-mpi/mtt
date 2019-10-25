# -*- coding: utf-8; tab-width: 4; indent-tabs-mode: f; python-indent: 4 -*-
#
# Copyright (c) 2015-2019 Intel, Inc.  All rights reserved.
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

## @addtogroup Stages
# @{
# @addtogroup Reporter
# @section TextFile
# File reporter plugin
# @param filename          Name of the file into which the report is to be written
# @param summary_footer    Footer to be placed at bottom of summary
# @param detail_header     Header to be put at top of detail report
# @param detail_footer     Footer to be placed at bottome of detail report
# @param textwrap          Max line length before wrapping
# @}
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
            testDef.logger.print(prefix + line)
        return

    def _print_stderr_block(self, name, lines, tabs=1):
        if lines:
            self.testDef.logger.print("\t"*tabs + " ERROR ({name})".format(name=name), file=self.fh)
            for l in lines:
                self.testDef.logger.print("\t"*(tabs) + "     " + l, file=self.fh)

    def execute(self, log, keyvals, testDef):
        self.testDef = testDef
        self.fh = sys.stdout
        testDef.logger.verbose_print("TextFile Reporter")
        num_secs_pass = 0
        # pickup the options
        cmds = {}
        testDef.parseOptions(log, self.options, keyvals, cmds)
        if cmds['filename'] is not None:
            self.fh = open(cmds['filename'] if os.path.isabs(cmds['filename']) \
                           else os.path.join(testDef.options['scratchdir'],cmds['filename']), 'w')
        if testDef.options['description'] is not None:
            testDef.logger.print(testDef.options['description'], file=self.fh)
            testDef.logger.print('', file=self.fh)
        # get the entire log of results
        fullLog = testDef.logger.getLog(None)
        for lg in fullLog:
            try:
                testDef.logger.print("Section: %s Status: %s" % (lg['section'], lg['status']), file=self.fh)
                try:
                    if lg['parameters'] is not None:
                        testDef.logger.print("\tInput parameters:", file=self.fh)
                        for p in lg['parameters']:
                            testDef.logger.print("\t\t %s = %s" % (p[0],p[1]), file=self.fh)
                except KeyError:
                    pass
                try:
                    if lg['options'] is not None:
                        testDef.logger.print("\tFinal options:", file=self.fh)
                        opts = lg['options']
                        keys = list(opts.keys())
                        for p in keys:
                            testDef.logger.print("\t\t %s = %s" % (p,opts[p]), file=self.fh)
                except KeyError:
                    pass
                try:
                    if lg['mpi_info'] is not None:
                        testDef.logger.print("\tInfo:", file=self.fh)
                        try:
                            testDef.logger.print("\t\tName: %s" % lg['mpi_info']['name'], file=self.fh)
                        except KeyError:
                            pass
                        try:
                            testDef.logger.print("\t\tVersion: %s" % lg['mpi_info']['version'], file=self.fh)
                        except KeyError:
                            pass
                except KeyError:
                    pass

                if 0 != lg['status']:
                    if "stderr" in lg:
                        self._print_stderr_block("stderr", lg['stderr'], tabs=1)
                    if "stdout" in lg:
                        self._print_stderr_block("stdout", lg['stdout'], tabs=1)
                else:
                    num_secs_pass += 1
                try:
                    if lg['location'] is not None:
                        testDef.logger.print("\tLocation: %s" % lg['location'], file=self.fh)
                except KeyError:
                    pass
            except KeyError:
                pass
            try:
                if lg['compiler'] is not None:
                    testDef.logger.print("\tCompiler:", file=self.fh)
                    comp = lg['compiler']
                    testDef.logger.print("\t\t %s" % comp['family'], file=self.fh)
                    testDef.logger.print("\t\t %s" % comp['version'], file=self.fh)
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
                    testDef.logger.print("\tProfile:", file=self.fh)
                    sp = " "
                    for key in keys:
                        line = key + (max1-len(key))*sp + '\n'.join(prf[key])
                        testDef.logger.print("\t\t %s" % line, file=self.fh)
            except KeyError:
                pass
            try:
                if lg['numTests'] is not None:
                    try:
                        npass = str(lg['numPass'])
                    except:
                        npass = "N/A"
                    try:
                        nskip = str(lg['numSkip'])
                    except:
                        nskip = "N/A"
                    try:
                        nfail = str(lg['numFail'])
                    except:
                        nfail = "N/A"
                    try:
                        ntime = str(lg['numTimed'])
                    except:
                        ntime = "N/A"

                    testDef.logger.print("\n\tTests: %s Pass: %s Skip: %s Fail: %s TimedOut: %s\n" % (lg['numTests'],npass,nskip,nfail,ntime), file=self.fh)
            except KeyError:
                pass
            try:
                if lg['testresults'] is not None:
                    for test in lg['testresults']:
                        tname = os.path.basename(test['test'])
                        try:
                            if test['result'] == testDef.MTT_TEST_PASSED:
                                st = "PASSED"
                            elif test['result'] == testDef.MTT_TEST_FAILED:
                                st = "FAILED"
                            elif test['result'] == testDef.MTT_TEST_TIMED_OUT:
                                st = "TIMED OUT"
                            elif test['result'] == testDef.MTT_TEST_SKIPPED:
                                st = "SKIPPED"
                            else:
                                st = "UNKNOWN"
                        except:
                            st = "NOT GIVEN"
                            testDef.logger.print("\t\t %s  Status: %s Category: %s" % (tname, test['status'], st), file=self.fh)
                        if 0 != test['status']:
                            if "stderr" in test:
                                self._print_stderr_block("stderr", test['stderr'], tabs=3)
                            if "stdout" in test:
                                self._print_stderr_block("stdout", test['stdout'], tabs=3)
            except KeyError:
                pass
            testDef.logger.print('', file=self.fh)
        testDef.logger.print("Num sections pass: %s / %s sections" % (num_secs_pass,len(fullLog)), file=self.fh)
        testDef.logger.print("Percentage sections pass: %s" % (100*float(num_secs_pass)/float(len(fullLog))), file=self.fh)
        if cmds['filename'] is not None:
            self.fh.close()
        log['status'] = 0
        return
