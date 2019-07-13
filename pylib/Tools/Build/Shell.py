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
import os
import re
import shlex
from BuildMTTTool import *

## @addtogroup Tools
# @{
# @addtogroup Build
# @section Shell
# Run shell commands to configure and build a software package
# @param middleware                Middleware stage that these tests are to be built against
# @param command                   Command to execute
# @param parent                    Section that precedes this one in the dependency tree
# @param merge_stdout_stderr       Merge stdout and stderr into one output stream
# @param stdout_save_lines         Number of lines of stdout to save
# @param stderr_save_lines         Number of lines of stderr to save
# @param modules_unload            Modules to unload
# @param modules                   Modules to load
# @param modules_swap              Modules to swap
# @param fail_test                 Specifies whether this test is expected to fail (value=None means test is expected to succeed)
# @param fail_returncode           Specifies the expected failure returncode of this test
# @param allocate_cmd              Command to use for allocating nodes from the resource manager
# @param deallocate_cmd            Command to use for deallocating nodes from the resource manager
# @param asis_target                    Specifies name of asis_target being built. This is used with \"ASIS\" keyword to determine whether to do anything.
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
        self.options['modules_unload'] = (None, "Modules to unload")
        self.options['modules'] = (None, "Modules to load")
        self.options['modules_swap'] = (None, "Modules to swap")
        self.options['fail_test'] = (None, "Specifies whether this test is expected to fail (value=None means test is expected to succeed)")
        self.options['fail_returncode'] = (None, "Specifies the expected failure returncode of this test")
        self.options['allocate_cmd'] = (None, "Command to use for allocating nodes from the resource manager")
        self.options['deallocate_cmd'] = (None, "Command to use for deallocating nodes from the resource manager")
        self.options['asis_target'] = (None, "Specifies name of asis_target being built. This is used with \"ASIS\" keyword to determine whether to do anything.")
        self.options['shell_mode'] = (False, "Use shlex or shell-mode for parsing?")

        self.allocated = False
        self.testDef = None
        self.cmds = None
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
            if self.allocated and self.cmds and self.testDef:
                self.deallocate({}, self.cmds, self.testDef)
        return

    def print_name(self):
        return "Shell"

    def print_options(self, testDef, prefix):
        lines = testDef.printOptions(self.options)
        for line in lines:
            print(prefix + line)
        return

    def allocate(self, log, cmds, testDef):
        self.allocated = False
        if cmds['allocate_cmd'] is not None and cmds['deallocate_cmd'] is not None:
            self.allocated = True
            allocate_cmdargs = shlex.split(cmds['allocate_cmd'])
            results = testDef.execmd.execute(cmds, allocate_cmdargs, testDef)
            if 0 != results['status']:
                self.allocated = False
                log['status'] = results['status']
                if log['stderr']:
                    log['stderr'].extend(results['stderr'])
                else:
                    log['stderr'] = results['stderr']
                return False
        return True

    def deallocate(self, log, cmds, testDef):
        if cmds['allocate_cmd'] is not None and cmds['deallocate_cmd'] is not None and self.allocated == True:
            deallocate_cmdargs = shlex.split(cmds['deallocate_cmd'])
            results = testDef.execmd.execute(cmds, deallocate_cmdargs, testDef)
            if 0 != results['status']:
                log['status'] = results['status']
                if log['stderr']:
                    log['stderr'].extend(results['stderr'])
                else:
                    log['stderr'] = results['stderr']
                return False
            self.allocated = False
        return True

    def execute(self, log, keyvals, testDef):

        self.testDef = testDef

        testDef.logger.verbose_print("Shell Execute")
        # parse any provided options - these will override the defaults
        cmds = {}
        testDef.parseOptions(log, self.options, keyvals, cmds)
        self.cmds = cmds
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
        parentlog = None
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
        except KeyError:
            log['status'] = 1
            log['stderr'] = "Parent not specified"
            return
        try:
            parentloc = os.path.join(os.getcwd(), testDef.options['scratchdir'])
            location = parentloc
        except KeyError:
            log['status'] = 1
            log['stderr'] = "No scratch directory in log"
            return
        if parentlog is not None:
            try:
                parentloc = parentlog['location']
                location = parentloc
            except KeyError:
                log['status'] = 1
                log['stderr'] = "Location of package to build was not specified in parent stage"
                return
        else:
            try:
                if log['section'].startswith("TestGet:") or log['section'].startswith("MiddlewareGet:"):
                    location = os.path.join(parentloc,log['section'].replace(":","_"))
            except KeyError:
                log['status'] = 1
                log['stderr'] = "No section in log"
                return
        # check to see if this is a dryrun
        if testDef.options['dryrun']:
            # just log success and return
            log['status'] = 0
            return

        # Check to see if this needs to be ran if ASIS is specified
        try:
            if cmds['asis']:
                if cmds['asis_target'] is not None:
                    if os.path.exists(os.path.join(parentloc,cmds['asis_target'])):
                        testDef.logger.verbose_print("asis_target " + os.path.join(parentloc,cmds['asis_target']) + " exists. Skipping...")
                        log['location'] = location
                        log['status'] = 0
                        return
                    else:
                        testDef.logger.verbose_print("asis_target " + os.path.join(parentloc,cmds['asis_target']) + " does not exist. Continuing...")
                else: # no asis target, default to check for directory
                    if os.path.exists(location):
                        testDef.logger.verbose_print("directory " + location + " exists. Skipping...")
                        log['location'] = location
                        log['status'] = 0
                        return
                    else:
                        testDef.logger.verbose_print("directory " + location + " does not exist. Continuing...")
        except KeyError:
            pass

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
                            # prepend the include path
                            try:
                                oldcpath = os.environ['CPATH']
                                pieces = oldcpath.split(':')
                            except KeyError:
                                oldcpath = ""
                                pieces = []
                            bindir = os.path.join(midlog['location'], "include")
                            pieces.insert(0, bindir)
                            newpath = ":".join(pieces)
                            os.environ['CPATH'] = newpath
                            # prepend the lib path
                            try:
                                oldlibpath = os.environ['LIBRARY_PATH']
                                pieces = oldlibpath.split(':')
                            except KeyError:
                                oldlibpath = ""
                                pieces = []
                            bindir = os.path.join(midlog['location'], "lib")
                            pieces.insert(0, bindir)
                            newpath = ":".join(pieces)
                            os.environ['LIBRARY_PATH'] = newpath

                            # mark that this was done
                            midpath = True
                    except KeyError:
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

        # Apply any requested environment module settings
        status,stdout,stderr = testDef.modcmd.applyModules(log['section'], cmds, testDef)
        if 0 != status:
            log['status'] = status
            log['stdout'] = stdout
            log['stderr'] = stderr
            return

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
        if log['section'].startswith("TestBuild:") or log['section'].startswith("MiddlewareBuild:"):
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
        if not os.path.exists(location):
            os.makedirs(location)
        os.chdir(location)
        # execute the specified command
        # Use shlex.split() for correct tokenization for args

        # Allocate cluster
        if False == self.allocate(log, cmds, testDef):
            return

        if cmds['shell_mode'] is False:
            cfgargs = shlex.split(cmds['command'])
        else:
            cfgargs = ["sh", "-c", cmds['command']]

        if 'TestRun' in log['section'].split(":")[0]:
            harass_exec_ids = testDef.harasser.start(testDef)

            harass_check = testDef.harasser.check(harass_exec_ids, testDef)
            if harass_check is not None:
                log['stderr'] = 'Not all harasser scripts started. These failed to start: ' \
                                + ','.join([h_info[1]['start_script'] for h_info in harass_check[0]])
                log['time'] = sum([r_info[3] for r_info in harass_check[1]])
                log['status'] = 1
                self.deallocate(log, cmds, testDef)
                return

        results = testDef.execmd.execute(cmds, cfgargs, testDef)

        if 'TestRun' in log['section'].split(":")[0]:
            testDef.harasser.stop(harass_exec_ids, testDef)

        # Deallocate cluster
        if False == self.deallocate(log, cmds, testDef):
            return

        if (cmds['fail_test'] is None and 0 != results['status']) \
                or (cmds['fail_test'] is not None and cmds['fail_returncode'] is None and 0 == results['status']) \
                or (cmds['fail_test'] is not None and cmds['fail_returncode'] is not None and int(cmds['fail_returncode']) != results['status']):
            # return to original location
            os.chdir(cwd)
            if log['status'] == 0:
                log['status'] = 1
            else:
                log['status'] = results['status']
            log['stdout'] = results['stdout']
            log['stderr'] = results['stderr']
            try:
                log['time'] = results['elapsed_secs']
            except:
                pass
            return
        log['status'] = 0
        log['stdout'] = results['stdout']
        try:
            log['time'] = results['elapsed_secs']
        except:
            pass
        if cmds['fail_test'] == True:
            log['stderr'] = results['stderr']
        # record this location for any follow-on steps
        log['location'] = location

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
            os.environ['CPATH'] = oldcpath
            os.environ['LIBRARY_PATH'] = oldlibpath

        # return to original location
        os.chdir(cwd)
        return
