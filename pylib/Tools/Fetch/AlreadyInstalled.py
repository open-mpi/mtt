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
from FetchMTTTool import *
from distutils.spawn import find_executable

class AlreadyInstalled(FetchMTTTool):

    def __init__(self):
        # initialise parent class
        FetchMTTTool.__init__(self)
        self.options = {}
        self.options['exec'] = (None, "Executable that should be in path")
        self.options['module'] = (None, "Modules (or lmod modules) to be loaded for accessing this package")
        return

    def activate(self):
        # get the automatic procedure from IPlugin
        IPlugin.activate(self)
        return


    def deactivate(self):
        IPlugin.deactivate(self)
        return

    def print_name(self):
        return "AlreadyInstalled"

    def print_options(self, testDef, prefix):
        lines = testDef.printOptions(self.options)
        for line in lines:
            print(prefix + line)
        return

    def execute(self, log, keyvals, testDef):
        # if we were given an executable to check for,
        # see if we can find it
        usedModule = False
        try:
            if keyvals['exec'] is not None:
                # if we were given a module to load, then
                # do so prior to checking for the executable
                try:
                    if keyvals['module'] is not None:
                        status,stdout,stderr = testDef.modcmd.loadModules(keyvals['modules'], testDef)
                        if 0 != status:
                            log['status'] = status
                            log['stderr'] = stderr
                            return
                        usedModule = True
                except KeyError:
                    pass
                # now look for the executable in our path
                if not find_executable(keyvals['exec']):
                    log['status'] = 1
                    log['stderr'] = "Executable {0} not found".format(keyvals['exec'])
                else:
                    log['status'] = 0
                if usedModule:
                    # unload the modules before returning
                    status,stdout,stderr = testDef.modcmd.unloadModules(keyvals['modules'], testDef)
                    if 0 != status:
                        log['status'] = status
                        log['stderr'] = stderr
                        return
                    usedModule = False
                return
        except KeyError:
            pass
        if usedModule:
            # unload the modules before returning
            status,stdout,stderr = testDef.modcmd.unloadModules(keyvals['modules'], testDef)
            if 0 != status:
                log['status'] = status
                log['stderr'] = stderr
                return
        log['status'] = 0
        return
