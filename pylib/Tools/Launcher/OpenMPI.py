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
from LauncherMTTTool import *
import shlex

## @addtogroup Tools
# @{
# @addtogroup Launcher
# @section OpenMPI
# Plugin for using the Open MPI mpirun launch tool
# @param hostfile                  The hostfile for OpenMPI to use
# @param command                   Command for executing the application
# @param np                        Number of processes to run
# @param ppn                       Number of processes per node to run
# @param timeout                   Maximum execution time - terminate a test if it exceeds this time
# @param options                   Comma-delimited sets of command line options that shall be used on each test
# @param skipped                   Exit status of a test that declares it was skipped
# @param merge_stdout_stderr       Merge stdout and stderr into one output stream
# @param stdout_save_lines         Number of lines of stdout to save
# @param stderr_save_lines         Number of lines of stderr to save
# @param test_dir                  Names of directories to be scanned for tests
# @param fail_tests                Names of tests that are expected to fail. Can use space or comma between entries. Include the expected return code using the following format: test_name:#
# @param fail_timeout              Maximum execution time for tests expected to fail
# @param skip_tests                Names of tests to be skipped
# @param max_num_tests             Maximum number of tests to run
# @param test_list                 List of tests to run, default is all
# @param allocate_cmd              Command to use for allocating nodes from the resource manager
# @param deallocate_cmd            Command to use for deallocating nodes from the resource manager
# @param modules_unload  Modules to unload
# @param modules         Modules to load
# @param modules_swap    Modules to swap
# @param dependencies              List of dependencies specified as the build stage name
# @}
class OpenMPI(LauncherMTTTool):

    def __init__(self):
        # initialise parent class
        LauncherMTTTool.__init__(self)
        self.options = {}
        self.options['hostfile'] = (None, "The hostfile for OpenMPI to use")
        self.options['command'] = ("mpirun", "Command for executing the application")
        self.options['np'] = (None, "Number of processes to run")
        self.options['ppn'] = (None, "Number of processes per node to run")
        self.options['timeout'] = (None, "Maximum execution time - terminate a test if it exceeds this time")
        self.options['options'] = (None, "Comma-delimited sets of command line options that shall be used on each test")
        self.options['skipped'] = ("77", "Exit status of a test that declares it was skipped")
        self.options['merge_stdout_stderr'] = (False, "Merge stdout and stderr into one output stream")
        self.options['stdout_save_lines'] = (-1, "Number of lines of stdout to save")
        self.options['stderr_save_lines'] = (-1, "Number of lines of stderr to save")
        self.options['test_dir'] = (None, "Names of directories to be scanned for tests")
        self.options['fail_tests'] = (None, "Names of tests that are expected to fail. Can use space or comma between entries. Include the expected return code using the following format: test_name:#")
        self.options['fail_timeout'] = (None, "Maximum execution time for tests expected to fail")
        self.options['skip_tests'] = (None, "Names of tests to be skipped")
        self.options['max_num_tests'] = (None, "Maximum number of tests to run")
        self.options['test_list'] = (None, "List of tests to run, default is all")
        self.options['allocate_cmd'] = (None, "Command to use for allocating nodes from the resource manager")
        self.options['deallocate_cmd'] = (None, "Command to use for deallocating nodes from the resource manager")
        self.options['modules'] = (None, "Modules to load")
        self.options['modules_unload'] = (None, "Modules to unload")
        self.options['modules_swap'] = (None, "Modules to swap")
        self.options['dependencies'] = (None, "List of dependencies specified as the build stage name - e.g., MiddlwareBuild_package to be added to configure using --with-package=location")

        self.allocated = False
        self.testDef = None
        self.cmds = None
        return


    def activate(self):
        # use the automatic procedure from IPlugin
        IPlugin.activate(self)
        return


    def deactivate(self):
        IPlugin.deactivate(self)
        if self.testDef and self.cmds and self.cmds['deallocate_cmd'] is not None:
            deallocate_cmdargs = shlex.split(self.cmds['deallocate_cmd'])
            self.deallocateCluster(None, self.cmds, self.testDef)

    def print_name(self):
        return "OpenMPI"

    def print_options(self, testDef, prefix):
        lines = testDef.printOptions(self.options)
        for line in lines:
            print(prefix + line)
        return

    def execute(self, log, keyvals, testDef):
        self.testDef = testDef
        testDef.logger.verbose_print("OpenMPI Launcher")

        # parse any provided options - these will override the defaults
        cmds = {}
        testDef.parseOptions(log, self.options, keyvals, cmds)
        self.cmds = cmds

        # update our defaults, if requested
        status = self.updateDefaults(log, self.options, keyvals, testDef)
        if status != 0:
            # indicates there is nothing more for us to do - status
            # et al is already in the log
            return

        # now let's setup the PATH and LD_LIBRARY_PATH as reqd
        status = self.setupPaths(log, keyvals, cmds, testDef)
        if status != 0:
            # something went wrong - error is in the log
            return

        # collect the tests to be considered
        status = self.collectTests(log, cmds)
        # check that we found something
        if status != 0:
            # something went wrong - error is in the log
            self.resetPaths(log, testDef)
            return

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
        if cmds['options'] is not None:
            optArgs = cmds['options'].split(',')
            for arg in optArgs:
                cmdargs.append(arg.strip())

        # Allocate cluster
        status = self.allocateCluster(log, cmds, testDef)
        if 0 != status:
            self.resetPaths(log, testDef)
            return

        # execute the tests
        self.runTests(log, cmdargs, cmds, testDef)

        # Deallocate cluster
        self.deallocateCluster(log, cmds, testDef)

        # reset our paths and return us to our cwd
        self.resetPaths(log, testDef)

        return
