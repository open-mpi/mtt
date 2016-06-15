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
import string
import sys
from BuildMTTTool import *

class Autotools(BuildMTTTool):
    def __init__(self):
        BuildMTTTool.__init__(self)
        self.activated = False
        self.options = {}
        self.options['parent'] = (None, "Section that precedes this one in the dependency tree")
        self.options['autogen_cmd'] = (None, "Command to be executed to setup the configure script, usually called autogen.sh or autogen.pl")
        self.options['configure_options'] = (None, "Options to be passed to configure. Note that the prefix will be automatically set and need not be provided here")
        self.options['make_options'] = (None, "Options to be passed to the make command")
        self.options['build_in_place'] = (False, "Build tests in current location (no prefix or install)")
        self.options['merge_stdout_stderr'] = (False, "Merge stdout and stderr into one output stream")
        self.options['stdout_save_lines'] = (None, "Number of lines of stdout to save")
        self.options['stderr_save_lines'] = (None, "Number of lines of stderr to save")
        self.options['save_stdout_on_success'] = (False, "Save stdout even if build succeeds")
        self.options['modules'] = (None, "Modules to load")
        self.exclude = set(string.punctuation)
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
        return "Autotools"

    def print_options(self, testDef, prefix):
        lines = testDef.printOptions(self.options)
        for line in lines:
            print prefix + line
        return

    def execute(self, log, keyvals, testDef):
        testDef.logger.verbose_print("Autotools Execute")
        # parse any provided options - these will override the defaults
        cmds = {}
        testDef.parseOptions(log, self.options, keyvals, cmds)
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
        inPlace = False
        try:
            if cmds['build_in_place']:
                prefix = None
                log['location'] = location
                inPlace = True
            else:
                # create the prefix path where this build result will be placed
                section = ''.join(ch for ch in keyvals['section'] if ch not in self.exclude)
                pfx = os.path.join(testDef.options['scratchdir'], "build", section)
                # convert it to an absolute path
                pfx = os.path.abspath(pfx)
                # record this location for any follow-on steps
                log['location'] = pfx
                prefix = "--prefix={0}".format(pfx)
        except KeyError:
            # create the prefix path where this build result will be placed
            section = ''.join(ch for ch in keyvals['section'] if ch not in self.exclude)
            pfx = os.path.join(testDef.options['scratchdir'], "build", section)
            # convert it to an absolute path
            pfx = os.path.abspath(pfx)
            # record this location for any follow-on steps
            log['location'] = pfx
            prefix = "--prefix={0}".format(pfx)
        # check to see if we are to leave things "as-is"
        try:
            if cmds['asis']:
                if not inPlace:
                    # see if the build already exists - if
                    # it does, then we are done
                    if os.path.exists(pfx) and os.path.isdir(pfx):
                        testDef.logger.verbose_print("As-Is location " + pfx + " exists and is a directory")
                        # nothing further to do
                        log['status'] = 0
                        return
                else:
                    # check if configure exists
                    cfg = os.path.join(location, "configure")
                    if os.path.exists(cfg):
                        # good enough
                        testDef.logger.verbose_print("As-Is location " + location + " has configure present")
                        log['status'] = 0
                        return
        except KeyError:
            pass
        # check to see if this is a dryrun
        if testDef.options['dryrun']:
            # just log success and return
            log['status'] = 0
            return
        # check to see if they specified a module to use
        # where the autotools can be found
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
        print log['compiler']

        # save the current directory so we can return to it
        cwd = os.getcwd()
        # now move to the package location
        os.chdir(location)
        # see if they want us to execute autogen
        try:
            if cmds['autogen_cmd'] is not None:
                agargs = []
                args = cmds['autogen_cmd'].split()
                for arg in args:
                    agargs.append(arg.strip())
                status, stdout, stderr = testDef.execmd.execute(agargs, testDef)
                if 0 != status:
                    log['status'] = status
                    log['stdout'] = stdout
                    log['stderr'] = stderr
                    if usedModule:
                        # unload the modules before returning
                        status,stdout,stderr = testDef.modcmd.unloadModules(cmds['modules'], testDef)
                        if 0 != status:
                            log['status'] = status
                            log['stderr'] = stderr
                    # return to original location
                    os.chdir(cwd)
                    return
                else:
                    # this is a multistep operation, and so we need to
                    # retain the output from each step in the log
                    log['autogen'] = (stdout, stderr)
        except KeyError:
            # autogen phase is not required
            pass
        # we always have to run configure, but we first
        # need to build a target prefix directory option based
        # on the scratch directory and section name
        cfgargs = ["./configure"]
        if prefix is not None:
            cfgargs.append(prefix)
        # if they gave us any configure args, add them
        try:
            if cmds['configure_options'] is not None:
                args = cmds['configure_options'].split()
                for arg in args:
                    cfgargs.append(arg.strip())
        except KeyError:
            pass
        status, stdout, stderr = testDef.execmd.execute(cfgargs, testDef)
        if 0 != status:
            log['status'] = status
            log['stdout'] = stdout
            log['stderr'] = stderr
            if usedModule:
                # unload the modules before returning
                status,stdout,stderr = testDef.modcmd.unloadModules(cmds['modules'], testDef)
                if 0 != status:
                    log['status'] = status
                    log['stderr'] = stderr
            # return to original location
            os.chdir(cwd)
            return
        else:
            # this is a multistep operation, and so we need to
            # retain the output from each step in the log
            log['configure'] = (stdout, stderr)
        # next we do the build stage, using the custom build cmd
        # if one is provided, or else defaulting to the testDef
        # default
        bldargs = ["make"]
        try:
            if cmds['make_options'] is not None:
                args = cmds['make_options'].split()
                for arg in args:
                    bldargs.append(arg.strip())
        except KeyError:
            # if they didn't provide it, then use the value in testDef
            args = testDef.options.default_make_options.split()
            for arg in args:
                bldargs.append(arg.strip())
        # step thru the process, starting with "clean"
        bldargs.append("clean")
        status, stdout, stderr = testDef.execmd.execute(bldargs, testDef)
        if 0 != status:
            log['status'] = status
            log['stdout'] = stdout
            log['stderr'] = stderr
            if usedModule:
                # unload the modules before returning
                status,stdout,stderr = testDef.modcmd.unloadModules(cmds['modules'], testDef)
                if 0 != status:
                    log['status'] = status
                    log['stderr'] = stderr
            # return to original location
            os.chdir(cwd)
            return
        else:
            # this is a multistep operation, and so we need to
            # retain the output from each step in the log
            log['make_clean'] = (stdout, stderr)
        # now execute "make all"
        bldargs = bldargs[0:-1]
        bldargs.append("all")
        status, stdout, stderr = testDef.execmd.execute(bldargs, testDef)
        if 0 != status:
            log['status'] = status
            log['stdout'] = stdout
            log['stderr'] = stderr
            if usedModule:
                # unload the modules before returning
                status,stdout,stderr = testDef.modcmd.unloadModules(cmds['modules'], testDef)
                if 0 != status:
                    log['status'] = status
                    log['stderr'] = stderr
            # return to original location
            os.chdir(cwd)
            return
        else:
            # this is a multistep operation, and so we need to
            # retain the output from each step in the log
            log['make_all'] = (stdout, stderr)
        # and finally, execute "make install" if we have a prefix
        if prefix is not None:
            bldargs = bldargs[0:-1]
            bldargs.append("install")
            status, stdout, stderr = testDef.execmd.execute(bldargs, testDef)
        # this is the end of the operation, so the status is our
        # overall status
        log['status'] = status
        log['stdout'] = stdout
        log['stderr'] = stderr
        if usedModule:
            # unload the modules before returning
            status,stdout,stderr = testDef.modcmd.unloadModules(cmds['modules'], testDef)
            if 0 != status:
                log['status'] = status
                log['stderr'] = stderr
        # return home
        os.chdir(cwd)
        return
