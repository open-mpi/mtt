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
from LauncherMTTTool import *

class OpenMPI(LauncherMTTTool):

    def __init__(self):
        # initialise parent class
        LauncherMTTTool.__init__(self)
        self.options = {}
        self.options['hostfile'] = (None, "The hostfile for OpenMPI to use")
        self.options['command'] = ("mpirun", "Command for executing the application")
        self.options['np'] = (None, "Number of processes to run")
        self.options['save_output_on_pass'] = (False, "Whether or not to save stdout/stderr on passed tests")
        self.options['num_lines_to_save'] = (None, "Number of lines of output to save")
        self.options['report_after_n_results'] = (None, "Number of tests to run before updating the reporter")
        self.options['timeout'] = (None, "Maximum execution time - terminate a test if it exceeds this time")
        self.options['options'] = (None, "Comma-delimited sets of command line options that shall be used on each test")

    def activate(self):
        # use the automatic procedure from IPlugin
        IPlugin.activate(self)
        return


    def deactivate(self):
        IPlugin.deactivate(self)


    def print_name(self):
        return "OpenMPI"

    def print_options(self, testDef, prefix):
        lines = testDef.printOptions(self.options)
        for line in lines:
            print prefix + line
        return

    def execute(self, log, keyvals, testDef):
        # check the log for the title so we can
        # see if this is setting our default behavior
        try:
            if log['stage'] is not None:
                if "Default" in log['stage']:
                    # this stage contains default settings
                    # for this launcher
                    testDef.parseOptions(log, self.options, keyvals, self.options)
                    try:
                        if log['status'] is not None:
                            return
                    except KeyError:
                        pass
                # we captured the default settings, so we can
                # now return with success
                log['status'] = 0
                return
        except KeyError:
            # error - the stage should have been there
            log['status'] = 1
            log['stderr'] - "Stage not specified"
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
                try:
                    if bldlog['parameters'] is not None:
                        for md in bldlog['parameters']:
                            if "modules" == md[0]:
                                try:
                                    if keyvals['modules'] is not None:
                                        # append these modules to those
                                        mods = md[1].split(',')
                                        newmods = modules.split(',')
                                        for md in newmods:
                                            mods.append(md)
                                        keyvals['modules'] = ','.join(mods)
                                except KeyError:
                                    keyvals['modules'] = md[1]
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
                            log['status'] = 1
                            log['stderr'] = "Location of middleware used for test build stage was not provided"
                            return
                        # check for modules required by the middleware
                        try:
                            if midlog['parameters'] is not None:
                                for md in midlog['parameters']:
                                    if "modules" == md[0]:
                                        try:
                                            if keyvals['modules'] is not None:
                                                # append these modules to those
                                                mods = md[1].split(',')
                                                newmods = modules.split(',')
                                                for md in newmods:
                                                    mods.append(md)
                                                keyvals['modules'] = ','.join(mods)
                                        except KeyError:
                                            keyvals['modules'] = md[1]
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
        try:
            if log['status'] is not None:
                # we hit an error parsing the options
                print "STATUS FOUND"
                return
        except KeyError:
            pass
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
            if keyvals['test_dir'] is not None:
                # pick up the executables from the specified directories
                dirs = keyvals['test_dir'].split()
                for dr in dirs:
                    for dirName, subdirList, fileList in os.walk(dr):
                        for fname in fileList:
                            # see if this is an executable
                            if os.access(fname, os.X_OK):
                                # add this file to our list of tests to execute
                                tests.append(os.path.abspath(fname))
        except KeyError:
            # get the list of executables from this directory and any
            # subdirectories beneath it
            for dirName, subdirList, fileList in os.walk("."):
                for fname in fileList:
                    # see if this is an executable
                    if os.access(fname, os.X_OK):
                        # add this file to our list of tests to execute
                        tests.append(os.path.abspath(fname))
        # check that we found something
        if not tests:
            log['status'] = 1
            log['stderr'] = "No tests found"
            return
        # cycle thru the list of tests and execute each of them
        print "TESTS"
        print tests
        log['status'] = 1
        return
