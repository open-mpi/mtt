# -*- coding: utf-8; tab-width: 4; indent-tabs-mode: f; python-indent: 4 -*-
#
# Copyright (c) 2015-2016 Intel, Inc. All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

from LauncherMTTTool import *

class OpenMPI(LauncherMTTTool):

    def __init__(self):
        # initialise parent class
        LauncherMTTTool.__init__(self)
        self.options = {}
        self.options['hostfile'] = (None, "The hostfile for OpenMPI to use")
        self.options['cmd'] = ("mpirun", "Command for executing the application")
        self.options['np'] = (None, "Number of processes to run")
        self.options['saveOnPass'] = (False, "Whether or not to save stdout/stderr on passed tests")
        self.options['numLines'] = (None, "Number of lines of output to save")
        self.options['reportRate'] = (None, "Number of tests to run before updating the reporter")
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
                    try:
                        if keyvals['save_output_on_pass'] is not None:
                            if keyvals['save_output_on_pass'] in ['true', '1', 't', 'y', 'yes', 'yeah', 'yup', 'certainly', 'uh-huh']:
                                self.options['saveOnPass'][0] = True
                            else:
                                self.options['saveOnPass'][0] = False
                    except KeyError:
                        pass
                    try:
                        if keyvals['num_lines_to_save'] is not None:
                            self.options['numLines'][0] = keyvals['num_lines_to_save']
                    except KeyError:
                        pass
                    try:
                        if keyvals['command'] is not None:
                            self.options['cmd'][0] = keyvals['command']
                    except KeyError:
                        pass
                    try:
                        if keyvals['timeout'] is not None:
                            self.options['timeout'][0] = keyvals['timeout']
                    except KeyError:
                        pass
                    try:
                        if keyvals['report_after_n_results'] is not None:
                            self.options['reportRate'][0] = keyvals['report_after_n_results']
                    except KeyError:
                        pass
                    try:
                        if keyvals['options'] is not None:
                            # remove any brackets the user may have included
                            options = keyvals['options'].replace('[','')
                            options = options.replace(']','')
                            # split the input to pickup sets of options
                            self.options['options'][0] = options.split(',')
                            print self.options['options']
                    except KeyError:
                        pass
                # we captured the default settings, so we can
                # now return with success
                log['status'] = 0
                return
        except KeyError:
            pass
        # must be executing a test of some kind - the install stage
        # must be specified so we can see what needs to be run
        try:
            parent = keyvals['parent']
            if parent is not None:
                print "PARENT"
        except KeyError:
            print "NO PARENT"
        log['status'] = 1
        return
