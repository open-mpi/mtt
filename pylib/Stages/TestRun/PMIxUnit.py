# -*- coding: utf-8; tab-width: 4; indent-tabs-mode: f; python-indent: 4 -*-
#
# Copyright (c) 2015-2019 Intel, Inc.  All rights reserved.
# Copyright (c) 2017      Los Alamos National Security, LLC. All rights
#                         reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

from __future__ import print_function
import os
from TestRunMTTStage import *
import shlex

## @addtogroup Stages
# @{
# @addtogroup TestRun
# @section PMIxUnit
# Plugin for running PMIx Unit tests
# @param command         Command to run the test
# @param middleware      Location of middleware installation
# @param gds             Set GDS module
# @param modules_unload  Modules to unload
# @param modules         Modules to load
# @param modules_swap    Modules to swap
# @}
class PMIxUnit(TestRunMTTStage):

    def __init__(self):
        # initialise parent class
        TestRunMTTStage.__init__(self)
        self.options = {}
        self.options['command'] = (None, "Command to run the test")
        self.options['middleware'] = (None, "Location of middleware installation")
        self.options['gds'] = (None, "Set GDS module")
        self.options['modules'] = (None, "Modules to load")
        self.options['modules_unload'] = (None, "Modules to unload")
        self.options['modules_swap'] = (None, "Modules to swap")

        self.testDef = None
        self.cmds = None
        return


    def activate(self):
        # use the automatic procedure from IPlugin
        IPlugin.activate(self)
        return


    def deactivate(self):
        IPlugin.deactivate(self)

    def print_name(self):
        return "PMIxUnit"

    def print_options(self, testDef, prefix):
        lines = testDef.printOptions(self.options)
        for line in lines:
            print(prefix + line)
        return

    def execute(self, log, keyvals, testDef):

        self.testDef = testDef

        midpath = False
        pypath = False

        testDef.logger.verbose_print("PMIxUnit Test Runner")

        # look for all keyvals starting with "test" as these
        # delineate the tests we are to run
        keys = keyvals.keys()
        tests = []
        mykeyvals = {}
        for k in keys:
            if k.startswith("test"):
                tests.append(keyvals[k])
            else:
                mykeyvals[k] = keyvals[k]

        # parse any provided options - these will override the defaults
        cmds = {}
        testDef.parseOptions(log, self.options, mykeyvals, cmds)
        self.cmds = cmds

        # check the log for the title so we can
        # see if this is setting our default behavior
        try:
            if log['section'] is not None:
                if "Default" in log['section']:
                    # this section contains default settings
                    # for this launcher
                    myopts = {}
                    testDef.parseOptions(log, self.options, keyvals, myopts)
                    # transfer the findings into our local storage
                    keys = list(self.options.keys())
                    optkeys = list(myopts.keys())
                    for optkey in optkeys:
                        for key in keys:
                            if key == optkey:
                                self.options[key] = (myopts[optkey],self.options[key][1])
                    # we captured the default settings, so we can
                    # now return with success
                    log['status'] = 0
                    return
        except KeyError:
            # error - the section should have been there
            log['status'] = 1
            log['stderr'] = "Section not specified"
            return

        # must be executing a test of some kind - the install stage
        # must be specified so we can find the tests to be run
        try:
            parent = keyvals['parent']
        except KeyError:
            log['status'] = 1
            log['stderr'] = "Parent test install stage was not provided"
            return

        # get the log entry as it contains the location
        # of the built tests
        bldlog = testDef.logger.getLog(parent)
        if bldlog is None:
            log['status'] = 1
            log['stderr'] = "Log for parent stage " + parent + " was not found"
            return
        try:
            location = bldlog['location']
        except KeyError:
            # if it wasn't recorded, then there is nothing
            # we can do
            log['status'] = 1
            log['stderr'] = "Location of built tests was not provided"
            return
        # check for modules used during the build of these tests
        status,stdout,stderr = testDef.modcmd.checkForModules(log['section'], bldlog, cmds, testDef)
        if 0 != status:
            log['status'] = status
            log['stdout'] = stdout
            log['stderr'] = stderr
            return

        # if they explicitly told us the middleware to use, use it
        if cmds['middleware'] is not None:
            midlog = testDef.logger.getLog(cmds['middleware'])
            if midlog is None:
                log['status'] = 1
                log['stderr'] = "Log for middleware " + cmds['middleware'] + " not found"
                return
        else:
            # get the log of any middleware so we can get its location
            try:
                midlog = testDef.logger.getLog(bldlog['middleware'])
                if midlog is None:
                    log['status'] = 1
                    log['stderr'] = "Log for middleware " + bldlog['middleware'] + " not found"
                    return
            except KeyError:
                pass

        # get the location of the middleware
        try:
            if midlog['location'] is not None:
                # prepend that location to our paths
                try:
                    oldbinpath = os.environ['PATH']
                    pieces = oldbinpath.split(':')
                except KeyError:
                    oldbinpath = ""
                    pieces = []
                bindir = os.path.join(midlog['location'], "bin")
                pieces.insert(0, bindir)
                newpath = ":".join(pieces)
                os.environ['PATH'] = newpath
                # prepend the loadable lib path
                try:
                    oldldlibpath = os.environ['LD_LIBRARY_PATH']
                    pieces = oldldlibpath.split(':')
                except KeyError:
                    oldldlibpath = ""
                    pieces = []
                bindir = os.path.join(midlog['location'], "lib")
                pieces.insert(0, bindir)
                newpath = ":".join(pieces)
                os.environ['LD_LIBRARY_PATH'] = newpath
                # see if there is a Python subdirectory
                listing = os.listdir(bindir)
                for d in listing:
                    entry = os.path.join(bindir, d)
                    if os.path.isdir(entry) and "python" in d:
                        oldpypath = os.environ['PYTHONPATH']
                        newpath = ":".join([oldpypath, os.path.join(entry, "site-packages")])
                        os.environ['PYTHONPATH'] = newpath
                        pypath = True
                        break
                # mark that this was done
                midpath = True
        except KeyError:
            # if it was already installed, then no location would be provided
            pass
        # check for modules required by the middleware
        status,stdout,stderr = testDef.modcmd.checkForModules(log['section'], midlog, cmds, testDef)
        if 0 != status:
            log['status'] = status
            log['stdout'] = stdout
            log['stderr'] = stderr
            return

        # Apply any requested environment module settings
        status,stdout,stderr = testDef.modcmd.applyModules(log['section'], cmds, testDef)
        if 0 != status:
            log['status'] = status
            log['stdout'] = stdout
            log['stderr'] = stderr
            return

        # now ready to execute the test - we are pointed at the middleware
        # and have obtained the list of any modules associated with it. We need
        # to change to the test location and begin executing, first saving
        # our current location so we can return when done
        cwd = os.getcwd()
        os.chdir(location)

        # cycle thru the list of tests and execute each of them
        log['testresults'] = []
        finalStatus = 0
        finalError = ""
        numTests = 0
        numPass = 0
        numFail = 0

        for test in tests:
            testLog = {'test':test}
            if cmds['command'] is not None:
                cmdargs = [cmds['command']]
            else:
                cmdargs = []
            # we cannot just split the test cmd line by spaces as there are spaces
            # in some of the options. So we have to do this the hard way by hand
            ln = len(test)
            s = ""
            n = 0
            while n < ln:
                if test[n] == ' ':
                    cmdargs.append(s)
                    s = ""
                    n += 1
                    continue
                elif test[n] == '"':
                    n += 1
                    # entering a quoted block that must be
                    # treated as a single option
                    while n < ln and test[n] != '"':
                        s += test[n]
                        n += 1
                    cmdargs.append(s)
                    s = ""
                    n += 1
                else:
                    s += test[n]
                    n += 1
            if len(s) > 0:
                cmdargs.append(s)
            testLog['cmd'] = " ".join(cmdargs)

            results = testDef.execmd.execute(cmds, cmdargs, testDef)

            if 0 == results['status']:
                numPass = numPass + 1
            else:
                numFail = numFail + 1
                if 0 == finalStatus:
                    finalStatus = status
                    finalError = stderr
            testLog['status'] = results['status']
            testLog['stdout'] = results['stdout']
            testLog['stderr'] = results['stderr']
            try:
                testLog['time'] = results['elapsed_secs']
            except:
                pass
            log['testresults'].append(testLog)
            numTests = numTests + 1

        log['status'] = finalStatus
        log['stderr'] = finalError
        log['numTests'] = numTests
        log['numPass'] = numPass
        log['numFail'] = numFail

        # Revert any requested environment module settings
        status,stdout,stderr = testDef.modcmd.revertModules(log['section'], testDef)
        if 0 != status:
            log['status'] = status
            log['stdout'] = stdout
            log['stderr'] = stderr
            return

        # if we added middleware to the paths, remove it
        if midpath:
            os.environ['PATH'] = oldbinpath
            os.environ['LD_LIBRARY_PATH'] = oldldlibpath

        if pypath:
            os.environ['PYTHONPATH'] = oldpypath

        os.chdir(cwd)
        return
