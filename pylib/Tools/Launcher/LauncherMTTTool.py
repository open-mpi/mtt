#!/usr/bin/env python
#
# Copyright (c) 2015-2019 Intel, Inc.  All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

from __future__ import print_function
from yapsy.IPlugin import IPlugin

import os
import shlex

## @addtogroup Tools
# @{
# @addtogroup Launcher
# Tools for launching HPC jobs
# @}
class LauncherMTTTool(IPlugin):
    def __init__(self):
        self.tests = []
        self.skip_tests = []
        self.oldbinpath = None
        self.oldldlibpath = None
        self.skipStatus = 77
        self.expected_returncodes = {}
        self.finalStatus = 0
        self.finalError = ""
        self.numTests = 0
        self.numPass = 0
        self.numSkip = 0
        self.numFail = 0
        self.numTimed = 0
        self.maxTests = 10000000
        self.midpath = False
        # initialise parent class
        IPlugin.__init__(self)

    def print_name(self):
        print("Launcher")

    def updateDefaults(self, log, options, keyvals, testDef):
        # check the log for the title so we can
        # see if this is setting our default behavior
        try:
            if log['section'] is not None:
                if "Default" in log['section']:
                    # this section contains default settings
                    # for this launcher
                    myopts = {}
                    testDef.parseOptions(log, options, keyvals, myopts)
                    # transfer the findings into our local storage
                    keys = list(options.keys())
                    optkeys = list(myopts.keys())
                    for optkey in optkeys:
                        for key in keys:
                            if key == optkey:
                                options[key] = (myopts[optkey], options[key][1])

                    # we captured the default settings, so we can
                    # now return with success
                    log['status'] = 0
                    return 1
        except KeyError:
            # error - the section should have been there
            log['status'] = 1
            log['stderr'] = "Section not specified"
            return 1
        # otherwise, just let them know to continue on
        return 0

    def setupPaths(self, log, keyvals, cmds, testDef):
        # the test install stage must be specified so we can find the tests to be run
        try:
            parent = keyvals['parent']
            if parent is not None:
                # get the log entry as it contains the location
                # of the built tests
                bldlog = testDef.logger.getLog(parent)
                try:
                    self.location = bldlog['location']
                except KeyError:
                    # if it wasn't recorded, then there is nothing
                    # we can do
                    log['status'] = 1
                    log['stderr'] = "Location of built tests was not provided"
                    return 1
                # Check for modules used during the build
                status,stdout,stderr = testDef.modcmd.checkForModules(log['section'], bldlog, cmds, testDef)
                if 0 != status:
                    log['status'] = status
                    log['stdout'] = stdout
                    log['stderr'] = stderr
                    return 1

                # get the log of any middleware so we can get its location
                try:
                    midlog = testDef.logger.getLog(bldlog['middleware'])
                    if midlog is not None:
                        # get the location of the middleware
                        try:
                            if midlog['location'] is not None:
                                # prepend that location to our paths
                                try:
                                    self.oldbinpath = os.environ['PATH']
                                    pieces = self.oldbinpath.split(':')
                                except KeyError:
                                    self.oldbinpath = ""
                                    pieces = []
                                bindir = os.path.join(midlog['location'], "bin")
                                pieces.insert(0, bindir)
                                newpath = ":".join(pieces)
                                os.environ['PATH'] = newpath
                                # prepend the loadable lib path
                                try:
                                    self.oldldlibpath = os.environ['LD_LIBRARY_PATH']
                                    pieces = self.oldldlibpath.split(':')
                                except KeyError:
                                    self.oldldlibpath = ""
                                    pieces = []
                                bindir = os.path.join(midlog['location'], "lib")
                                pieces.insert(0, bindir)
                                newpath = ":".join(pieces)
                                os.environ['LD_LIBRARY_PATH'] = newpath

                                # mark that this was done
                                self.midpath = True
                        except KeyError:
                            # if it was already installed, then no location would be provided
                            pass
                        # check for modules required by the middleware
                        status,stdout,stderr = testDef.modcmd.checkForModules(log['section'], midlog, cmds, testDef)
                        if 0 != status:
                            log['status'] = status
                            log['stdout'] = stdout
                            log['stderr'] = stderr
                            return 1
                except KeyError:
                    pass
        except KeyError:
            log['status'] = 1
            log['stderr'] = "Parent test build stage was not provided"
            return 1

        # see if any dependencies were given
        try:
            deps = cmds['dependencies']
            # might be comma-delimited or space delimited
            dps = deps.split()
            # loop over the entries
            for d in dps:
                # get the location where the output of this stage was stored by
                # first recovering the log for it
                try:
                    lg = testDef.logger.getLog(d)
                    try:
                        loc = lg['location']
                    except:
                        # we cannot do what the user requested
                        log['status'] = 1
                        log['stderr'] = "Location of dependency " + d + " could not be found"
                        return
                except:
                    # we don't have a record of this dependency
                    log['status'] = 1
                    log['stderr'] = "Log for dependency " + d + " could not be found"
                    return
                # update the PATH
                if self.oldbinpath is None:
                    self.oldbinpath = os.environ['PATH']
                bindir = os.path.join(loc, "bin")
                os.environ['PATH'] = bindir + ':' + os.environ['PATH']
                # update LD_LIBRARY_PATH
                libdir = os.path.join(loc, "lib")
                os.environ['LD_LIBRARY_PATH'] = libdir + ':' + os.environ['LD_LIBRARY_PATH']
                libdir = os.path.join(loc, "lib64")
                os.environ['LD_LIBRARY_PATH'] = libdir + ':' + os.environ['LD_LIBRARY_PATH']
        except:
            pass

        # Apply any requested environment module settings
        status,stdout,stderr = testDef.modcmd.applyModules(log['section'], cmds, testDef)
        if 0 != status:
            log['status'] = status
            log['stdout'] = stdout
            log['stderr'] = stderr
            return 1

        # save our current location and position us to where the tests are located
        self.cwd = os.getcwd()
        os.chdir(self.location)

        # all is good
        return 0

    def resetPaths(self, log, testDef):
        # Revert any requested environment module settings
        status,stdout,stderr = testDef.modcmd.revertModules(log['section'], testDef)
        if 0 != status:
            log['status'] = status
            log['stdout'] = stdout
            log['stderr'] = stderr
            return

        # if we added middleware to the paths, remove it
        if self.midpath:
            os.environ['PATH'] = self.oldbinpath
            os.environ['LD_LIBRARY_PATH'] = self.oldldlibpath

        os.chdir(self.cwd)
        return

    def collectTests(self, log, cmds):
        # did they give us a list of specific directories where the desired
        # tests to be executed reside?
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
                                    self.tests.append(filename)
                else:
                    # get the list of executables from this directory and any
                    # subdirectories beneath it
                    for dirName, subdirList, fileList in os.walk("."):
                        for fname in fileList:
                            # see if this is an executable
                            filename = os.path.abspath(os.path.join(dirName,fname))
                            if os.path.isfile(filename) and os.access(filename, os.X_OK):
                                # add this file to our list of tests to execute
                                self.tests.append(filename)
            except KeyError:
                # get the list of executables from this directory and any
                # subdirectories beneath it
                for dirName, subdirList, fileList in os.walk("."):
                    for fname in fileList:
                        # see if this is an executable
                        filename = os.path.abspath(os.path.join(dirName,fname))
                        if os.path.isfile(filename) and os.access(filename, os.X_OK):
                            # add this file to our list of tests to execute
                            self.tests.append(filename)
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
                    for fname_cmd in cmds['test_list'].split("\n"):
                        fname = fname_cmd.strip().split(" ")[0]
                        fname_args = " ".join(fname_cmd.strip().split(" ")[1:])
                        if fname not in fileList:
                            continue
                        filename = os.path.abspath(os.path.join(dirName,fname))
                        if os.path.isfile(filename) and os.access(filename, os.X_OK):
                            self.tests.append((filename+" "+fname_args).strip())
        # check that we found something
        if not self.tests:
            log['status'] = 1
            log['stderr'] = "No tests found"
            return 1

        # get the "skip" exit status
        self.skipStatus = int(cmds['skipped'])
        # get any specified max number of tests to execute
        if cmds['max_num_tests'] is not None:
            self.maxTests = int(cmds['max_num_tests'])

        # create a list of the tests that are expected to fail - i.e.,
        # these are tests that should fail, and therefore "succeed" if
        # they fail with the designated exit status. Failing with a
        # different exit status than expected represents a true failure
        # and must be reported as such
        fail_tests = cmds['fail_tests']
        if fail_tests is not None:
            # it is supposed to be a comma-delimited list of test names
            # so we split on comma and then strip any remaining whitespace
            fail_tests = [t.strip() for t in fail_tests.split(",")]
        else:
            fail_tests = []
        # the list of tests expected to fail is given by test name, but
        # the list of tests we are to execute has been setup in absolute
        # path form. Thus, scan the two lists and replace the fail_tests
        # entries with their absolute path equivalents. Note that we don't
        # bother removing those we don't match as those won't be executed
        # anyway and thus are irrelevant
        for i,t in enumerate(fail_tests):
            for t2 in self.tests:
                if t2.split("/")[-1] == t:
                    fail_tests[i] = t2

        # find the list of expected return codes for tests that are
        # intended to fail
        fail_returncodes = cmds['fail_returncodes']
        if fail_returncodes is not None:
            # it is supposed to be a comma-delimited list of integers
            # so we split on comma and then strip any remaining whitespace
            fail_returncodes = [int(t.strip()) for t in fail_returncodes.split(",")]
        else:
            fail_returncodes = []

        # there must be a one-to-one correspondence of fail_returncodes
        # and fail_tests
        if len(fail_tests) != len(fail_returncodes):
            log['status'] = 1
            if len(fail_tests) > len(fail_returncodes):
                log['stderr'] = "Not enough return codes were supplied to satisfy the number of tests expected to fail: " + str(len(fail_returncodes)) + ":" + str(len(fail_tests))
            else:
                log['stderr'] = "Too many return codes were supplied to satisfy the number of tests expected to fail: " + str(len(fail_returncodes)) + ":" + str(len(fail_tests))
            return 1

        # construct a dict of usecases for tests expected to fail
        fail_usecases = {}
        n = 0
        for t in fail_tests:
            fail_usecases[t] = fail_returncodes[n]
            n += 1

        # record the expected return code for each test - we store this in a
        # new dictionary that uses the test name as its key. Default to an
        # expected return code of 0 for any test not in the fail_tests list
        # cycle across the list of tests
        for t in self.tests:
            if t in fail_usecases:
                self.expected_returncodes[t] = fail_usecases[t]
            else:
                self.expected_returncodes[t] = 0

        # construct the list of tests to be skipped - we will skip the
        # tests at time of execution and so we leave them in the list
        # of all tests here
        skip_tests = cmds['skip_tests']
        if skip_tests is not None:
            # it is supposed to be a comma-delimited list of test names
            # so we split on comma and then strip any remaining whitespace
            self.skip_tests = [t.strip() for t in skip_tests.split(",")]
        else:
            self.skip_tests = []
        # the list of tests to skip is given by test name, but
        # the list of tests we are to execute has been setup in absolute
        # path form. Thus, scan the two lists and replace the skip_tests
        # entries with their absolute path equivalents. Note that we don't
        # bother removing those we don't match as those won't be executed
        # anyway and thus are irrelevant
        for i,t in enumerate(self.skip_tests):
            for t2 in self.tests:
                if t2.split("/")[-1] == t:
                    self.skip_tests[i] = t2
        # all done
        return 0

    def allocateCluster(self, log, cmds, testDef):
        self.allocated = False
        if cmds['allocate_cmd'] is not None and cmds['deallocate_cmd'] is not None:
            self.allocated = True
            allocate_cmdargs = shlex.split(cmds['allocate_cmd'])
            results = testDef.execmd.execute(cmds, allocate_cmdargs, testDef)
            if 0 != results['status']:
                log['status'] = results['status']
                log['stderr'] = results['stderr']
                os.chdir(cwd)
                return 1
        return 0

    def runTests(self, log, cmdargs, cmds, testDef):
        log['testresults'] = []
        for test in self.tests:
            testLog = {'test':test}
            cmdargs.append(test)
            testLog['cmd'] = " ".join(cmdargs)

            # check if we should skip this test
            if test in self.skip_tests:
                # track number of tests we skipped. We record its
                # status as the one we were told to use for
                # a "skipped" test since we obviously didn't
                # really execute it
                self.numSkip += 1
                testLog['stdout'] = ""
                testLog['stderr'] = ""
                testLog['time'] = 0
                testLog['status'] = self.skipStatus
                # clearly mark this as a skipped test
                testLog['result'] = testDef.MTT_TEST_SKIPPED
                log['testresults'].append(testLog)
                cmdargs = cmdargs[:-1]
                continue

            harass_exec_ids = testDef.harasser.start(testDef)

            harass_check = testDef.harasser.check(harass_exec_ids, testDef)
            if harass_check is not None:
                testLog['stderr'] = 'Not all harasser scripts started. These failed to start: ' \
                                + ','.join([h_info[1]['start_script'] for h_info in harass_check[0]])
                testLog['time'] = sum([r_info[3] for r_info in harass_check[1]])
                testLog['status'] = 1
                testLog['result'] = testDef.MTT_TEST_FAILED
                if 0 == self.finalStatus:
                    self.finalStatus = 1
                    self.finalError = testLog['stderr']
                self.numFail += 1
                self.numTests += 1
                testDef.harasser.stop(harass_exec_ids, testDef)
                log['testresults'].append(testLog)
                cmdargs = cmdargs[:-1]
                if self.numTests == self.maxTests:
                    break
                continue

            results = testDef.execmd.execute(cmds, cmdargs, testDef)

            testDef.harasser.stop(harass_exec_ids, testDef)

            testLog['status'] = results['status']
            testLog['stdout'] = results['stdout']
            testLog['stderr'] = results['stderr']
            try:
                testLog['time'] = results['time']
            except:
                pass

            try:
                if results['timedout']:
                    # the test timed out, so flag it as having exited that way
                    testLog['result'] = testDef.MTT_TEST_TIMED_OUT
                    if 0 == self.finalStatus:
                        self.finalStatus = results['status']
                        self.finalError = results['stderr']
                    self.numTimed += 1
            except:
                # check the return status - if the test checked its conditions
                # and decided to be skipped, then log it as such
                if results['status'] == self.skipStatus:
                    self.numSkip += 1
                    testLog['stdout'] = ""
                    testLog['stderr'] = ""
                    testLog['time'] = 0
                    testLog['status'] = self.skipStatus
                    # clearly mark this as a skipped test
                    testLog['result'] = testDef.MTT_TEST_SKIPPED
                elif results['status'] != self.expected_returncodes[test]:
                    # if the test was expected to fail, then
                    # we should see it return the expected code or else we declare it
                    # as having failed
                    testLog['result'] = testDef.MTT_TEST_FAILED
                    if 0 == self.finalStatus:
                        self.finalStatus = results['status']
                        self.finalError = results['stderr']
                    self.numFail += 1
                else:
                    testLog['result'] = testDef.MTT_TEST_PASSED
                    self.numPass += 1
            try:
                testLog['np'] = cmds['np']
            except KeyError:
                try:
                    testLog['np'] = cmds['ppn']
                except:
                    testLog['np'] = -1
            log['testresults'].append(testLog)
            cmdargs = cmdargs[:-1]
            self.numTests = self.numTests + 1
            if self.numTests == self.maxTests:
                break
        # record the results
        log['status'] = self.finalStatus
        log['stderr'] = self.finalError
        log['numTests'] = self.numTests
        log['numPass'] = self.numPass
        log['numSkip'] = self.numSkip
        log['numFail'] = self.numFail
        log['numTimed'] = self.numTimed
        return

    def deallocateCluster(self, log, cmds, testDef):
        if cmds['deallocate_cmd'] is not None and self.allocated:
            deallocate_cmdargs = shlex.split(cmds['deallocate_cmd'])
            results = testDef.execmd.execute(cmds, deallocate_cmdargs, testDef)
            if 0 != results['status'] and log is not None:
                log['status'] = results['status']
                log['stderr'] = results['stderr']
                return 1
            self.allocated = False
        return 0

