#!/usr/bin/env python
#
# Copyright (c) 2015-2018 Intel, Inc.  All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

from __future__ import print_function
import os
import re
import string
import sys
import shlex
import shutil
from BuildMTTTool import *

## @addtogroup Tools
# @{
# @addtogroup Build
# @section Autotools
# Run typical autotools commands to configure and build a software package
# @param middleware                Middleware stage that these tests are to be built against
# @param parent                    Section that precedes this one in the dependency tree
# @param autogen_cmd               Command to be executed to setup the configure script, usually called autogen.sh or autogen.pl
# @param configure_options         Options to be passed to configure. Note that the prefix will be automatically set and need not be provided here
# @param make_options              Options to be passed to the make command
# @param build_in_place            Build tests in current location (no prefix or install)
# @param merge_stdout_stderr       Merge stdout and stderr into one output stream
# @param stdout_save_lines         Number of lines of stdout to save
# @param stderr_save_lines         Number of lines of stderr to save
# @param modules_unload            Modules to unload
# @param modules                   Modules to load
# @param modules_swap    Modules to swap

# @}
class Autotools(BuildMTTTool):
    def __init__(self):
        BuildMTTTool.__init__(self)
        self.activated = False
        self.options = {}
        self.options['middleware'] = (None, "Middleware stage that these tests are to be built against")
        self.options['parent'] = (None, "Section that precedes this one in the dependency tree")
        self.options['autogen_cmd'] = (None, "Command to be executed to setup the configure script, usually called autogen.sh or autogen.pl")
        self.options['configure_options'] = (None, "Options to be passed to configure. Note that the prefix will be automatically set and need not be provided here")
        self.options['make_options'] = (None, "Options to be passed to the make command")
        self.options['build_in_place'] = (False, "Build tests in current location (no prefix or install)")
        self.options['merge_stdout_stderr'] = (False, "Merge stdout and stderr into one output stream")
        self.options['stdout_save_lines'] = (-1, "Number of lines of stdout to save")
        self.options['stderr_save_lines'] = (-1, "Number of lines of stderr to save")
        self.options['modules_unload'] = (None, "Modules to unload")
        self.options['modules'] = (None, "Modules to load")
        self.options['modules_swap'] = (None, "Modules to swap")
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
            print(prefix + line)
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

        # check if we need to point to middleware
        # do this before we load environment modules so we can append to the list if needed
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
        testDef.logger.verbose_print(log['compiler'])

        # Find MPI information for IUDatabase plugin if
        # mpi_info is not already set
        fullLog = testDef.logger.getLog(None)
        mpi_info_found = False
        for lg in fullLog:
            if 'mpi_info' in lg:
                mpi_info_found = True
        if mpi_info_found is False:
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
        else:
            testDef.logger.verbose_print("mpi_info already in log so skipping MPIVersion")

        # Add configure options to log for IUDatabase plugin
        try:
            log['configure_options'] = cmds['configure_options']
        except KeyError:
            log['configure_options'] = ''

        try:
            if cmds['build_in_place']:
                prefix = None
                log['location'] = location
                pfx = location
                inPlace = True
            else:
                # create the prefix path where this build result will be placed
                pfx = os.path.join(testDef.options['scratchdir'], log['section'].replace(':','_'))
                # convert it to an absolute path
                pfx = os.path.abspath(pfx)
                # record this location for any follow-on steps
                log['location'] = pfx
                prefix = "--prefix={0}".format(pfx)
        except KeyError:
            # create the prefix path where this build result will be placed
            pfx = os.path.join(testDef.options['scratchdir'], log['section'].replace(':','_'))
            # convert it to an absolute path
            pfx = os.path.abspath(pfx)
            # record this location for any follow-on steps
            log['location'] = pfx
            prefix = "--prefix={0}".format(pfx)
        # check to see if we are to leave things "as-is"
        try:
            if cmds['asis']:
                # see if the build already exists - if
                # it does, then we are done
                if os.path.exists(os.path.join(pfx, 'build_complete')):
                    testDef.logger.verbose_print("As-Is location " + pfx + " exists and has 'build_complete file")
                    # nothing further to do
                    log['status'] = 0
                    return
        except KeyError:
            pass
        # check to see if this is a dryrun
        if testDef.options['dryrun']:
            # just log success and return
            log['status'] = 0
            return

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
                status, stdout, stderr, _ = testDef.execmd.execute(cmds, agargs, testDef)
                if 0 != status:
                    log['status'] = status
                    log['stdout'] = stdout
                    log['stderr'] = stderr

                    # Revert any requested environment module settings
                    status,stdout,stderr = testDef.modcmd.revertModules(log['section'], testDef)
                    if 0 != status:
                        log['status'] = status
                        log['stdout'] = stdout
                        log['stderr'] = stderr
                        # return to original location
                        os.chdir(cwd)
                        return
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
                args = shlex.split(cmds['configure_options'])
                for arg in args:
                    cfgargs.append(arg.strip())
        except KeyError:
            pass

        status, stdout, stderr, _ = testDef.execmd.execute(cmds, cfgargs, testDef)
        if 0 != status:
            log['status'] = status
            log['stdout'] = stdout
            log['stderr'] = stderr

            # Revert any requested environment module settings
            status,stdout,stderr = testDef.modcmd.revertModules(log['section'], testDef)
            if 0 != status:
                log['status'] = status
                log['stdout'] = stdout
                log['stderr'] = stderr
                # return to original location
                os.chdir(cwd)
                return

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
        status, stdout, stderr, _ = testDef.execmd.execute(cmds, bldargs, testDef)
        if 0 != status:
            log['status'] = status
            log['stdout'] = stdout
            log['stderr'] = stderr

            # Revert any requested environment module settings
            status,stdout,stderr = testDef.modcmd.revertModules(log['section'], testDef)
            if 0 != status:
                log['status'] = status
                log['stdout'] = stdout
                log['stderr'] = stderr
                # return to original location
                os.chdir(cwd)
                return

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
        status, stdout, stderr, _ = testDef.execmd.execute(cmds, bldargs, testDef)
        if 0 != status:
            log['status'] = status
            log['stdout'] = stdout
            log['stderr'] = stderr

            # Revert any requested environment module settings
            status,stdout,stderr = testDef.modcmd.revertModules(log['section'], testDef)
            if 0 != status:
                log['status'] = status
                log['stdout'] = stdout
                log['stderr'] = stderr
                # return to original location
                os.chdir(cwd)
                return

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
            status, stdout, stderr, _ = testDef.execmd.execute(cmds, bldargs, testDef)
        # this is the end of the operation, so the status is our
        # overall status
        log['status'] = status
        log['stdout'] = stdout
        log['stderr'] = stderr

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

        # Add confirmation that build is complete
        try:
            confirmation = os.path.join(pfx, 'build_complete')
            fo = open(confirmation, 'w')
            fo.write("Build was successful")
            print("BUILD SUCCESSFUL FILE CREATED AT: " + confirmation)
            fo.close()
        except:
            pass

        # return home
        os.chdir(cwd)

        return
