# -*- coding: utf-8; tab-width: 4; indent-tabs-mode: f; python-indent: 4 -*-
#
# Copyright (c) 2015-2018 Intel, Inc.  All rights reserved.
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
from LauncherMTTTool import *
import shlex

## @addtogroup Tools
# @{
# @addtogroup Launcher
# @section PMIxUnit
# Plugin for using the Open MPI mpirun launch tool
# @param np                        Number of processes to run
# @param servers                   Number of servers to emulate
# @param timeout                   Maximum execution time - terminate a test if it exceeds this time
# @param early_fail                Force client process with rank 0 to fail before PMIX_Init
# @param gds                       Set GDS module
# @param test_dir                  Names of directories to be scanned for tests
# @param fail_tests                Names of tests that are expected to fail
# @param fail_returncodes          Expected return codes of tests expected to fail
# @param fail_timeout              Maximum execution time for tests expected to fail
# @param skip_tests                Names of tests to be skipped
# @param max_num_tests             Maximum number of tests to run
# @param test_list                 List of tests to run, default is all
# @param modules_unload  Modules to unload
# @param modules         Modules to load
# @param modules_swap    Modules to swap
# @}
class PMIxUnit(LauncherMTTTool):

    def __init__(self):
        # initialise parent class
        LauncherMTTTool.__init__(self)
        self.options = {}
        self.options['np'] = (None, "Number of processes to run")
        self.options['servers'] = (None, "Number of servers to emulate")
        self.options['timeout'] = (None, "Maximum execution time - terminate a test if it exceeds this time")
        self.options['early_fail'] = (False, "Force client process with rank 0 to fail before PMIX_Init")
        self.options['gds'] = (None, "Set GDS module")
        self.options['test_dir'] = (None, "Names of directories to be scanned for tests")
        self.options['fail_tests'] = (None, "Names of tests that are expected to fail")
        self.options['fail_returncodes'] = (None, "Expected returncodes of tests expected to fail")
        self.options['fail_timeout'] = (None, "Maximum execution time for tests expected to fail")
        self.options['skip_tests'] = (None, "Names of tests to be skipped")
        self.options['max_num_tests'] = (None, "Maximum number of tests to run")
        self.options['test_list'] = (None, "List of tests to run, default is all")
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

        testDef.logger.verbose_print("PMIxUnit Launcher")

        # parse any provided options - these will override the defaults
        cmds = {}
        testDef.parseOptions(log, self.options, keyvals, cmds)
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
            if parent is not None:
                # get the log entry as it contains the location
                # of the built tests
                bldlog = testDef.logger.getLog(parent)
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

                # get the log of any middleware so we can get its location
                try:
                    midlog = testDef.logger.getLog(bldlog['middleware'])
                    if midlog is not None:
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
                except KeyError:
                    pass
        except KeyError:
            log['status'] = 1
            log['stderr'] = "Parent test build stage was not provided"
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
        # did they give us a list of specific directories where the desired
        # tests to be executed reside?
        tests = []
        if cmds['test_list'] is None:
            try:
                if cmds['test_dir'] is not None:
                    # pick up the executables from the specified directories
                    dirs = cmds['test_dir'].split()
                    for dr in dirs:
                        dr = dr.strip()
                        # remove any commas and quotes
                        dr = dr.replace('\"','')
                        dr = dr.replace(',','')
                        for dirName, subdirList, fileList in os.walk(dr):
                            for fname in fileList:
                                # see if this is an executable
                                filename = os.path.abspath(os.path.join(dirName,fname))
                                if os.path.isfile(filename) and os.access(filename, os.X_OK):
                                    # add this file to our list of tests to execute
                                    tests.append(filename)
                else:
                    # get the list of executables from this directory and any
                    # subdirectories beneath it
                    for dirName, subdirList, fileList in os.walk("."):
                        for fname in fileList:
                            # see if this is an executable
                            filename = os.path.abspath(os.path.join(dirName,fname))
                            if os.path.isfile(filename) and os.access(filename, os.X_OK):
                                # add this file to our list of tests to execute
                                tests.append(filename)
            except KeyError:
                # get the list of executables from this directory and any
                # subdirectories beneath it
                for dirName, subdirList, fileList in os.walk("."):
                    for fname in fileList:
                        # see if this is an executable
                        filename = os.path.abspath(os.path.join(dirName,fname))
                        if os.path.isfile(filename) and os.access(filename, os.X_OK):
                            # add this file to our list of tests to execute
                            tests.append(filename)
        # If list of tests is provided, use list rather than grabbing all tests
        else:
            if cmds['test_dir'] is not None:
                dirs = cmds['test_dir'].split()
            else:
                dirs = ['.']
            for dr in dirs:
                dr = dr.strip()
                dr = dr.replace('\"','')
                dr = dr.replace(',','')
                for dirName, subdirList, fileList in os.walk(dr):
                    for fname in cmds['test_list'].split(","):
                        fname = fname.strip()
                        if fname not in fileList:
                            continue
                        filename = os.path.abspath(os.path.join(dirName,fname))
                        if os.path.isfile(filename) and os.access(filename, os.X_OK):
                            tests.append(filename)

        # check that we found something
        if not tests:
            log['status'] = 1
            log['stderr'] = "No tests found"
            os.chdir(cwd)
            return
        # get the "skip" exit status
        skipStatus = int(cmds['skipped'])
        # assemble the command
        cmdargs = cmds['command'].split()
        if cmds['np'] is not None:
            cmdargs.append("-np")
            cmdargs.append(cmds['np'])
        if cmds['ppn'] is not None:
            cmdargs.append("-N")
            cmdargs.append(cmds['ppn'])
        if cmds['hostfile'] is not None:
            cmdargs.append("-hostfile")
            cmdargs.append(cmds['hostfile'])
        if cmds['timeout'] is not None:
            cmdargs.append("--timeout")
            cmdargs.append(cmds['timeout'])
        if cmds['options'] is not None:
            optArgs = cmds['options'].split(',')
            for arg in optArgs:
                cmdargs.append(arg.strip())
        # cycle thru the list of tests and execute each of them
        log['testresults'] = []
        finalStatus = 0
        finalError = ""
        numTests = 0
        numPass = 0
        numSkip = 0
        numFail = 0
        if cmds['max_num_tests'] is not None:
            maxTests = int(cmds['max_num_tests'])
        else:
            maxTests = 10000000

        fail_tests = cmds['fail_tests']
        if fail_tests is not None:
            fail_tests = [t.strip() for t in fail_tests.split(",")]
        else:
            fail_tests = []
        for i,t in enumerate(fail_tests):
            for t2 in tests:
                if t2.split("/")[-1] == t:
                    fail_tests[i] = t2
        fail_returncodes = cmds['fail_returncodes']
        if fail_returncodes is not None:
            fail_returncodes = [int(t.strip()) for t in fail_returncodes.split(",")]

        if fail_tests is None:
            expected_returncodes = {test:0 for test in tests}
        else:
            if fail_returncodes is None:
                expected_returncodes = {test:(None if test in fail_tests else 0) for test in tests}
            else:
                fail_returncodes = {test:rtncode for test,rtncode in zip(fail_tests,fail_returncodes)}
                expected_returncodes = {test:(fail_returncodes[test] if test in fail_returncodes else 0) for test in tests}

        # Allocate cluster
        self.allocated = False
        if cmds['allocate_cmd'] is not None and cmds['deallocate_cmd'] is not None:
            self.allocated = True
            allocate_cmdargs = shlex.split(cmds['allocate_cmd'])
            _status,_stdout,_stderr,_time = testDef.execmd.execute(cmds, allocate_cmdargs, testDef)
            if 0 != _status:
                log['status'] = _status
                log['stderr'] = _stderr
                os.chdir(cwd)
                return

        for test in tests:
            # Skip tests that are in "skip_tests" ini input
            if cmds['skip_tests'] is not None and test.split('/')[-1] in [st.strip() for st in cmds['skip_tests'].split()]:
                numTests += 1
                numSkip += 1
                if numTests == maxTests:
                    break
                continue
            testLog = {'test':test}
            cmdargs.append(test)
            testLog['cmd'] = " ".join(cmdargs)

            harass_exec_ids = testDef.harasser.start(testDef)

            harass_check = testDef.harasser.check(harass_exec_ids, testDef)
            if harass_check is not None:
                testLog['stderr'] = 'Not all harasser scripts started. These failed to start: ' \
                                + ','.join([h_info[1]['start_script'] for h_info in harass_check[0]])
                testLog['time'] = sum([r_info[3] for r_info in harass_check[1]])
                testLog['status'] = 1
                finalStatus = 1
                finalError = testLog['stderr']
                numFail = numFail + 1
                testDef.harasser.stop(harass_exec_ids, testDef)
                continue

            status,stdout,stderr,time = testDef.execmd.execute(cmds, cmdargs, testDef)

            testDef.harasser.stop(harass_exec_ids, testDef)

            if ((expected_returncodes[test] is None and 0 == status) or (expected_returncodes[test] is not None and expected_returncodes[test] != status)) and skipStatus != status and 0 == finalStatus:
                if expected_returncodes[test] == 0:
                    finalStatus = status
                else:
                    finalStatus = 1
                finalError = stderr
            if (expected_returncodes[test] is None and 0 != status) or (expected_returncodes[test] == status):
                numPass = numPass + 1
            elif skipStatus == status:
                numSkip = numSkip + 1
            else:
                numFail = numFail + 1
            if expected_returncodes[test] == 0:
                testLog['status'] = status
            else:
                if status == expected_returncodes[test]:
                    testLog['status'] = 0
                else:
                    testLog['status'] = 1
            testLog['stdout'] = stdout
            testLog['stderr'] = stderr
            testLog['time'] = time
            log['testresults'].append(testLog)
            cmdargs = cmdargs[:-1]
            numTests = numTests + 1
            if numTests == maxTests:
                break

        # Deallocate cluster
        if cmds['allocate_cmd'] is not None and cmds['deallocate_cmd'] is not None and self.allocated:
            deallocate_cmdargs = shlex.split(cmds['deallocate_cmd'])
            _status,_stdout,_stderr,_time = testDef.execmd.execute(cmds, deallocate_cmdargs, testDef)
            if 0 != _status:
                log['status'] = _status
                log['stderr'] = _stderr
                os.chdir(cwd)
                return
            self.allocated = False

        log['status'] = finalStatus
        log['stderr'] = finalError
        log['numTests'] = numTests
        log['numPass'] = numPass
        log['numSkip'] = numSkip
        log['numFail'] = numFail
        try:
            log['np'] = cmds['np']
        except KeyError:
            log['np'] = None

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

        os.chdir(cwd)
        return
