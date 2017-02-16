#!/usr/bin/env python
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
import re
from BuildMTTTool import *

## @addtogroup Tools
# @{
# @addtogroup Build
# @section Shell
# @param merge_stdout_stderr       Merge stdout and stderr into one output stream
# @param parent                    Section that precedes this one in the dependency tree
# @param modules_unload            Modules to unload
# @param stdout_save_lines         Number of lines of stdout to save
# @param modules                   Modules to load
# @param stderr_save_lines         Number of lines of stderr to save
# @param save_stdout_on_success    Save stdout even if build succeeds
# @param command                   Command to execute
# @param middleware                Middleware stage that these tests are to be built against
# @param fail_test                 Specifies whether this test is expected to fail (value=None means test is expected to succeed)
# @param fail_returncode           Specifies the expected failure returncode of this test
# @}
class Shell(BuildMTTTool):
    def __init__(self):
        BuildMTTTool.__init__(self)
        self.activated = False
        self.options = {}
        self.options['middleware'] = (None, "Middleware stage that these tests are to be built against")
        self.options['command'] = (None, "Command to execute")
        self.options['parent'] = (None, "Section that precedes this one in the dependency tree")
        self.options['merge_stdout_stderr'] = (False, "Merge stdout and stderr into one output stream")
        self.options['stdout_save_lines'] = (-1, "Number of lines of stdout to save")
        self.options['stderr_save_lines'] = (-1, "Number of lines of stderr to save")
        self.options['save_stdout_on_success'] = (False, "Save stdout even if build succeeds")
        self.options['modules'] = (None, "Modules to load")
        self.options['modules_unload'] = (None, "Modules to unload")
        self.options['fail_test'] = (None, "Specifies whether this test is expected to fail (value=None means test is expected to succeed)")
        self.options['fail_returncode'] = (None, "Specifies the expected failure returncode of this test")
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
            print(prefix + line)
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

        # check if we need to point to middleware
        midpath = False
        try:
            if cmds['middleware'] is not None:
                # pass it down
                log['middleware'] = cmds['middleware']
                # get the log entry of its location
                midlog = testDef.logger.getLog(cmds['middleware'])
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
                            # prepend the libdir path as well
                            try:
                                oldlibpath = os.environ['LD_LIBRARY_PATH']
                                pieces = oldlibpath.split(':')
                            except KeyError:
                                oldlibpath = ""
                                pieces = []
                            bindir = os.path.join(midlog['location'], "lib")
                            pieces.insert(0, bindir)
                            newpath = ":".join(pieces)
                            os.environ['LD_LIBRARY_PATH'] = newpath
                            # mark that this was done
                            midpath = True
                    except KeyError:
                        pass
                    # check for modules required by the middleware
                    try:
                        if midlog['parameters'] is not None:
                            for md in midlog['parameters']:
                                if "modules" == md[0]:
                                    try:
                                        if cmds['modules'] is not None:
                                            # append these modules to those
                                            mods = md[1].split(',')
                                            newmods = modules.split(',')
                                            for md in newmods:
                                                mods.append(md)
                                            cmds['modules'] = ','.join(mods)
                                    except KeyError:
                                        cmds['modules'] = md[1]
                                    break
                    except KeyError:
                        pass
        except KeyError:
            pass

        # check to see if they specified a module to use
        # where the compiler can be found
        usedModule = False
        try:
            if cmds['modules'] is not None:
                status,stdout,stderr = testDef.modcmd.loadModules(cmds['modules'], testDef)
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
                status,stdout,stderr = testDef.modcmd.unloadModules(cmds['modules_unload'], testDef)
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
        availUtil = list(testDef.loader.utilities.keys())
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

        # Find MPI information for IUDatabase plugin
        plugin = None
        availUtil = list(testDef.loader.utilities.keys())
        for util in availUtil:
            for pluginInfo in testDef.utilities.getPluginsOfCategory(util):
                if "MPIVersion" == pluginInfo.plugin_object.print_name():
                    plugin = pluginInfo.plugin_object
                    break
        if plugin is None:
            log['mpi_info'] = {'name' : 'unknown', 'version' : 'unknown'}
        else:
            mpi_info = {}
            plugin.execute(mpi_info, testDef)
            log['mpi_info'] = mpi_info

        # save the current directory so we can return to it
        cwd = os.getcwd()
        # now move to the package location
        os.chdir(location)
        # execute the specified command
        cfgargs = cmds['command'].split()
        status, stdout, stderr = testDef.execmd.execute(cmds, cfgargs, testDef)
        if (cmds['fail_test'] is None and 0 != status) \
                or (cmds['fail_test'] is not None and cmds['fail_returncode'] is None and 0 == status) \
                or (cmds['fail_test'] is not None and cmds['fail_returncode'] is not None and int(cmds['fail_returncode']) != status):
            # return to original location
            os.chdir(cwd)
            if log['status'] == 0:
                log['status'] = 1
            else:
                log['status'] = status
            log['stdout'] = stdout
            log['stderr'] = stderr
            return
        log['status'] = 0
        log['stdout'] = stdout
        if cmds['fail_test'] == True:
            log['stderr'] = stderr
        # record this location for any follow-on steps
        log['location'] = location
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
        # if we added middleware to the paths, remove it
        if midpath:
            os.environ['PATH'] = oldbinpath
            os.environ['LD_LIBRARY_PATH'] = oldlibpath

        # return to original location
        os.chdir(cwd)
        return
