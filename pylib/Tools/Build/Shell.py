#!/usr/bin/env python
#
# Copyright (c) 2015-2016 Intel, Inc. All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

import os
import re
from BuildMTTTool import *

class Shell(BuildMTTTool):
    def __init__(self):
        BuildMTTTool.__init__(self)
        self.activated = False
        self.options = {}
        self.options['command'] = (None, "Command to execute")
        self.options['parent'] = (None, "Section that precedes this one in the dependency tree")
        self.options['merge_stdout_stderr'] = (False, "Merge stdout and stderr into one output stream")
        self.options['stdout_save_lines'] = (None, "Number of lines of stdout to save")
        self.options['stderr_save_lines'] = (None, "Number of lines of stderr to save")
        self.options['save_stdout_on_success'] = (False, "Save stdout even if build succeeds")
        return

    def activate(self):
        if not self.activated:
            # use the automatic procedure from IPlugin
            IPlugin.activate(self)
            self.activated = True
        return

    def deactivate(self):
        if self.activated:
            IPlugin.deactivate(self)
            self.activated = False
        return

    def print_name(self):
        return "Shell"

    def print_options(self, testDef, prefix):
        lines = testDef.printOptions(self.options)
        for line in lines:
            print prefix + line
        return

    def execute(self, log, keyvals, testDef):
        testDef.logger.verbose_print("Shell Execute")
        # parse any provided options - these will override the defaults
        cmds = {}
        testDef.parseOptions(log, self.options, keyvals, cmds)
        # if they didn't give us a shell command to execute, then error
        try:
            if cmds['command'] is None:
                log['status'] = 1
                log['stderr'] = "No command specified"
                return
        except KeyError:
            log['status'] = 1
            log['stderr'] = "No command specified"
            return

        # get the location of the software we are to build
        try:
            if cmds['parent'] is not None:
                # we have to retrieve the log entry from
                # the parent section so we can get the
                # location of the package. The logger
                # can provide it for us
                parentlog = testDef.logger.getLog(cmds['parent'])
                if parentlog is None:
                    log['status'] = 1
                    log['stderr'] = "Parent",cmds['parent'],"log not found"
                    return
            else:
                log['status'] = 1
                log['stderr'] = "Parent log not recorded"
                return

        except KeyError:
            log['status'] = 1
            log['stderr'] = "Parent not specified"
            return
        try:
            location = parentlog['location']
        except KeyError:
            log['status'] = 1
            log['stderr'] = "Location of package to build was not specified in parent stage"
            return
        # check to see if this is a dryrun
        if testDef.options['dryrun']:
            # just log success and return
            log['status'] = 0
            return
        # check to see if they specified a module to use
        # where the compiler can be found
        usedModule = False
        try:
            if cmds['modules'] is not None:
                status,stdout,stderr = testDef.modcmd.loadModules(log, cmds['modules'], testDef)
                if 0 != status:
                    log['status'] = status
                    log['stderr'] = stderr
                    return
                usedModule = True
        except KeyError:
            # not required to provide a module
            pass
        usedModuleUnload = False
        try:
            if cmds['modules_unload'] is not None:
                status,stdout,stderr = testDef.modcmd.unloadModules(log, cmds['modules_unload'], testDef)
                if 0 != status:
                    log['status'] = status
                    log['stderr'] = stderr
                    return
                usedModuleUnload = True
        except KeyError:
            # not required to provide a module to unload
            pass

        # sense and record the compiler being used
        plugin = None
        availUtil = testDef.loader.utilities.keys()
        for util in availUtil:
            for pluginInfo in testDef.utilities.getPluginsOfCategory(util):
                if "Compilers" == pluginInfo.plugin_object.print_name():
                    plugin = pluginInfo.plugin_object
                    break
        if plugin is None:
            log['compiler'] = {'status' : 1, 'family' : "unknown", 'version' : "unknown"}
        else:
            compilerLog = {}
            plugin.execute(compilerLog, testDef)
            log['compiler'] = compilerLog

        # save the current directory so we can return to it
        cwd = os.getcwd()
        # now move to the package location
        os.chdir(location)
        # execute the specified command
        cfgargs = cmds['command'].split()
        status, stdout, stderr = testDef.execmd.execute(cfgargs, testDef)
        log['status'] = status
        log['stdout'] = stdout
        log['stderr'] = stderr
        # record this location for any follow-on steps
        log['location'] = location
        if usedModule:
            # unload the modules before returning
            testDef.modcmd.unloadModules(log, cmds['modules'], testDef)
        if usedModuleUnload:
            testDef.modcmd.loadModules(log, cmds['modules_unload'], testDef)
        
        # return to original location
        os.chdir(cwd)
        return
