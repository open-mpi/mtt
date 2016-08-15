# -*- coding: utf-8; tab-width: 4; indent-tabs-mode: f; python-indent: 4 -*-
#
# Copyright (c) 2015-2016 Intel, Inc. All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

from __future__ import print_function
import os
from LauncherMTTTool import *

class SLURM(LauncherMTTTool):

    def __init__(self):
        # initialise parent class
        LauncherMTTTool.__init__(self)
        self.options = {}
        self.options['hostfile'] = (None, "The hostfile for OpenMPI to use")
        self.options['command'] = ("srun", "Command for executing the application")
        self.options['np'] = (None, "Number of processes to run")
        self.options['save_stdout_on_pass'] = (False, "Whether or not to save stdout on passed tests")
        self.options['report_after_n_results'] = (None, "Number of tests to run before updating the reporter")
        self.options['timeout'] = (None, "Maximum execution time - terminate a test if it exceeds this time")
        self.options['options'] = (None, "Comma-delimited sets of command line options that shall be used on each test")
        self.options['skipped'] = ("77", "Exit status of a test that declares it was skipped")
        self.options['merge_stdout_stderr'] = (False, "Merge stdout and stderr into one output stream")
        self.options['stdout_save_lines'] = (None, "Number of lines of stdout to save")
        self.options['stderr_save_lines'] = (None, "Number of lines of stderr to save")
        self.options['test_dir'] = (None, "Names of directories to be scanned for tests")
        self.options['fail_tests'] = (None, "Names of tests that are expected to fail")
        self.options['fail_timeout'] = (None, "Maximum execution time for tests expected to fail")
        self.options['skip_tests'] = (None, "Names of tests to be skipped")
        self.options['max_num_tests'] = (None, "Maximum number of tests to run")
        self.options['job_name'] = (None, "User-defined name for job")
        self.options['modules'] = (None, "Modules to load")
        self.options['modules_unload'] = (None, "Modules to unload")
        return


    def activate(self):
        # use the automatic procedure from IPlugin
        IPlugin.activate(self)
        return


    def deactivate(self):
        IPlugin.deactivate(self)


    def print_name(self):
        return "SLURM"

    def print_options(self, testDef, prefix):
        lines = testDef.printOptions(self.options)
        for line in lines:
            print(prefix + line)
        return

    def execute(self, log, keyvals, testDef):

        testDef.logger.verbose_print("SLURM Launcher")
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
                try:
                    if bldlog['parameters'] is not None:
                        # check for modules used during the build of these tests
                        for md in bldlog['parameters']:
                            if "modules" == md[0]:
                                try:
                                    if keyvals['modules'] is not None:
                                        # append these modules to those
                                        mods = md[1].split(',')
                                        newmods = keyvals['modules'].split(',')
                                        for mdx in newmods:
                                            mods.append(mdx)
                                        keyvals['modules'] = ','.join(mods)
                                except KeyError:
                                    keyvals['modules'] = md[1]
                                break
                        # check for modules unloaded during the build of these tests
                        for md in bldlog['parameters']:
                            if "modules_unload" == md[0]:
                                try:
                                    if keyvals['modules_unload'] is not None:
                                        # append these modules to those
                                        mods = md[1].split(',')
                                        newmods = keyvals['modules_unload'].split(',')
                                        for mdx in newmods:
                                            mods.append(mdx)
                                        keyvals['modules_unload'] = ','.join(mods)
                                except KeyError:
                                    keyvals['modules_unload'] = md[1]
                                break
                except KeyError:
                    pass
                # get the log of any middleware so we can get its location
                try:
                    midlog = testDef.logger.getLog(bldlog['middleware'])
                    if midlog is not None:
                        # get the location of the middleware
                        try:
                            if midlog['location'] is not None:
                                # prepend that location to our paths
                                path = os.environ['PATH']
                                pieces = path.split(':')
                                bindir = os.path.join(midlog['location'], "bin")
                                pieces.insert(0, bindir)
                                newpath = ":".join(pieces)
                                os.environ['PATH'] = newpath
                                # prepend the libdir path as well
                                path = os.environ['LD_LIBRARY_PATH']
                                pieces = path.split(':')
                                bindir = os.path.join(midlog['location'], "lib")
                                pieces.insert(0, bindir)
                                newpath = ":".join(pieces)
                                os.environ['LD_LIBRARY_PATH'] = newpath
                        except KeyError:
                            # if it was already installed, then no location would be provided
                            pass
                        try:
                            if midlog['parameters'] is not None:
                                # check for modules required by the middleware
                                for md in midlog['parameters']:
                                    if "modules" == md[0]:
                                        try:
                                            if keyvals['modules'] is not None:
                                                # append these modules to those
                                                mods = md[1].split(',')
                                                newmods = keyvals['modules'].split(',')
                                                for mdx in newmods:
                                                    mods.append(mdx)
                                                keyvals['modules'] = ','.join(mods)
                                        except KeyError:
                                            keyvals['modules'] = md[1]
                                        break
                                # check for modules unloaded by the middleware
                                for md in midlog['parameters']:
                                    if "modules_unload" == md[0]:
                                        try:
                                            if keyvals['modules_unload'] is not None:
                                                # append these modules to those
                                                mods = md[1].split(',')
                                                newmods = keyvals['modules_unload'].split(',')
                                                for mdx in newmods:
                                                    mods.append(mdx)
                                                keyvals['modules_unload'] = ','.join(mods)
                                        except KeyError:
                                            keyvals['modules_unload'] = md[1]
                                        break
                        except KeyError:
                            pass
                except KeyError:
                    pass
        except KeyError:
            log['status'] = 1
            log['stderr'] = "Parent test build stage was not provided"
            return
        # parse any provided options - these will override the defaults
        cmds = {}
        testDef.parseOptions(log, self.options, keyvals, cmds)
        # now ready to execute the test - we are pointed at the middleware
        # and have obtained the list of any modules associated with it. We need
        # to change to the test location and begin executing, first saving
        # our current location so we can return when done
        cwd = os.getcwd()
        os.chdir(location)
        # did they give us a list of specific directories where the desired
        # tests to be executed reside?
        tests = []
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
        # check that we found something
        if not tests:
            log['status'] = 1
            log['stderr'] = "No tests found"
            os.chdir(cwd)
            return
        # get the "skip" exit status
        skipStatus = int(cmds['skipped'])
        # assemble the command
        cmdargs = [cmds['command']]
        if cmds['job_name'] is not None:
            cmdargs.append("--job-name")
            cmdargs.append(cmds['job_name'])
        if cmds['options'] is not None:
            cmdargs.append(cmds['options'])
        if cmds['np'] is not None:
            cmdargs.append("-np")
            cmdargs.append(cmds['np'])
        if cmds['hostfile'] is not None:
            cmdargs.append("-hostfile")
            cmdargs.append(cmds['hostfile'])
        # cycle thru the list of tests and execute each of them
        log['testresults'] = []
        finalStatus = 0
        finalError = None
        numTests = 0
        numPass = 0
        numSkip = 0
        numFail = 0
        if cmds['max_num_tests'] is not None:
            maxTests = int(cmds['max_num_tests'])
        else:
            maxTests = 10000000

        # Load modules that were required during the middleware or test build
        usedModule = False
        try:
            if cmds['modules'] is not None:
                status,stdout,stderr = testDef.modcmd.loadModules(cmds['modules'], testDef)
                if 0 != status:
                    log['status'] = status
                    log['stderr'] = stderr
                    os.chdir(cwd)
                    return
                usedModule = True
        except KeyError:
            # not required to provide a module
            pass
        # unload modules that were removed during the middleware or test build
        usedModuleUnload = False
        try:
            if cmds['modules_unload'] is not None:
                status,stdout,stderr = testDef.modcmd.unloadModules(cmds['modules_unload'], testDef)
                if 0 != status:
                    log['status'] = status
                    log['stderr'] = stderr
                    os.chdir(cwd)
                    return
                usedModuleUnload = True
        except KeyError:
            # not required to provide a module to unload
            pass
  
        for test in tests:
            testLog = {'test':test}
            cmdargs.append(test)
            testLog['cmd'] = " ".join(cmdargs)
            status,stdout,stderr = testDef.execmd.execute(cmdargs, testDef)
            testLog['status'] = status
            if 0 != status and skipStatus != status and 0 == finalStatus:
                finalStatus = status
                finalError = stderr
            if 0 == status:
                numPass = numPass + 1
            elif skipStatus == status:
                numSkip = numSkip + 1
            else:
                numFail = numFail + 1
            testLog['stdout'] = stdout
            testLog['stderr'] = stderr
            log['testresults'].append(testLog)
            cmdargs = cmdargs[:-1]
            numTests = numTests + 1
            if numTests == maxTests:
                break
        log['status'] = finalStatus
        log['stderr'] = finalError
        log['numTests'] = numTests
        log['numPass'] = numPass
        log['numSkip'] = numSkip
        log['numFail'] = numFail

        # handle case where srun is used instead of mpirun for number of processes (np)
        if cmds['command'] == 'srun':
            if '-n ' in cmds['options']:
                log['np'] = str(cmds['options'].split('-n ')[1].split(' ')[0])
            elif '--ntasks=' in cmds['options']:
                log['np'] = str(cmds['options'].split('--ntasks=')[1].split(' ')[0])
            elif '-N ' in cmds['options']:
                log['np'] = str(cmds['options'].split('-N ')[1].split(' ')[0])
            else: #'--nodes=' in cmds['options']
                log['np'] = str(cmds['options'].split('--nodes=')[1].split(' ')[0])
        else:
            try:
                log['np'] = cmds['np']
            except KeyError:
                log['np'] = None

        if usedModule:
            # unload the modules before returning
            status,stdout,stderr = testDef.modcmd.unloadModules(cmds['modules'], testDef)
            if 0 != status:
                log['status'] = status
                log['stderr'] = stderr
                os.chdir(cwd)
                return
        if usedModuleUnload:
            status,stdout,stderr = testDef.modcmd.loadModules(cmds['modules_unload'], testDef)
            if 0 != status:
                log['status'] = status
                log['stderr'] = stderr
                os.chdir(cwd)
                return

        os.chdir(cwd)
        return
