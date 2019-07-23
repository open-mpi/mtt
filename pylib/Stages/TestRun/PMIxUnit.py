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
# @param timeout         Time limit for application execution
# @param dependencies    Middleware dependencies
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
        self.options['timeout'] = (None, "Time limit for application execution")
        self.options['dependencies'] = (None, "Middleware dependencies")
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
                libdir = os.path.join(midlog['location'], "lib")
                if not os.path.exists(libdir) or not os.path.isdir(libdir):
                    libdir = os.path.join(midlog['location'], "lib64")
                pieces.insert(0, libdir)
                newpath = ":".join(pieces)
                os.environ['LD_LIBRARY_PATH'] = newpath
                # see if there is a Python subdirectory
                listing = os.listdir(libdir)
                for d in listing:
                    entry = os.path.join(libdir, d)
                    if os.path.isdir(entry) and "python" in d:
                        try:
                            oldpypath = os.environ['PYTHONPATH']
                            newpath = ":".join([oldpypath, os.path.join(entry, "site-packages")])
                        except:
                            oldpypath = None
                            newpath = os.path.join(entry, "site-packages")
                        os.environ['PYTHONPATH'] = newpath
                        pypath = True
                        break
                if not pypath and "lib64" not in libdir:
                    # try the lib64 location if we aren't already there
                    libdir = os.path.join(midlog['location'], "lib64")
                    if os.path.exists(libdir) and os.path.isdir(libdir):
                        listing = os.listdir(libdir)
                        for d in listing:
                            entry = os.path.join(libdir, d)
                            if os.path.isdir(entry) and "python" in d:
                                try:
                                    oldpypath = os.environ['PYTHONPATH']
                                    newpath = ":".join([oldpypath, os.path.join(entry, "site-packages")])
                                except:
                                    oldpypath = None
                                    newpath = os.path.join(entry, "site-packages")
                                os.environ['PYTHONPATH'] = newpath
                                pypath = True
                                break
                # mark that this was done
                midpath = True
        except KeyError:
            # if it was already installed, then no location would be provided
            pass

        # search our dependencies to set the 'mpi_info' name field
        ext = "prrte-unknown"
        version = None
        if cmds['dependencies'] is not None:
            # split out the dependencies
            deps = cmds['dependencies'].split()
            # one should be PRRTE and the other is the middleware
            # we are using for the tests
            for d in deps:
                if d.lower().endswith("prrte"):
                    # get the log of this stage
                    lg = testDef.logger.getLog(d)
                    # the parent is the Get operation
                    lg2 = testDef.logger.getLog(lg['parent'])
                    try:
                        ext = "prrte-master-PR" + lg2['pr']
                    except:
                        try:
                            ext = "prrte-" + lg2['branch']
                        except:
                            ext = "prrte-master"
                    try:
                        ext = ext + "-" + lg2['hash']
                    except:
                        pass
                elif version is None:
                    # get the log of this stage
                    lg = testDef.logger.getLog(d)
                    # the parent is the Get operation
                    lg2 = testDef.logger.getLog(lg['parent'])
                    # take the name of the section as our middleware name
                    mdname = lg2['section'].split(':')[-1]
                    try:
                        version = mdname + "-master-PR" + lg2['pr']
                    except:
                        try:
                            version = mdname + "-" + lg2['branch']
                        except:
                            version = mdname + "-master"
                    try:
                        version = version + "-" + lg2['hash']
                    except:
                        pass

        log['mpi_info'] = {'name' : ext, 'version' : version}

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

        testDef.logger.verbose_print("PMIxUnit: looking for tests in " + location)

        # cycle thru the list of tests and execute each of them
        log['testresults'] = []
        finalStatus = 0
        finalError = ""
        numTests = 0
        numPass = 0
        numFail = 0
        numTimed = 0

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
            takenext = False
            while n < ln:
                if test[n] == ' ':
                    cmdargs.append(s)
                    if takenext:
                        testLog['np'] = int(s)
                        takenext = False
                    elif s.startswith("-n"):
                        takenext = True
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

            try:
                if results['timedout']:
                    numTimed += 1
                    testLog['result'] = testDef.MTT_TEST_TIMED_OUT
            except:
                if 0 == results['status']:
                    numPass = numPass + 1
                    testLog['result'] = testDef.MTT_TEST_PASSED
                else:
                    numFail = numFail + 1
                    testLog['result'] = testDef.MTT_TEST_FAILED
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
        log['numTimed'] = numTimed

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
            if oldpypath is not None:
                os.environ['PYTHONPATH'] = oldpypath
            else:
                del os.environ['PYTHONPATH']

        os.chdir(cwd)
        return
