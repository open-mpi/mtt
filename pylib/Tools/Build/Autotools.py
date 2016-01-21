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

class Autotools(BuildMTTTool):
    def __init__(self):
        BuildMTTTool.__init__(self)
        self.activated = False
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

    def execute(self, log, keyvals, testDef):
        # get the location of the software we are to build
        try:
            if keyvals['parent'] is not None:
                # we have to retrieve the log entry from
                # the parent section so we can get the
                # location of the package. The logger
                # can provide it for us
                parentlog = testDef.logger.getLog(keyvals['parent'])
                if parentlog is None:
                    log['status'] = 1
                    log['stderr'] = "Parent log not found"
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
        # check to see if they specified a module to use
        # where the autotools can be found
        usedModule = False
        try:
            if keyvals['modules'] is not None:
                status,stdout,stderr = testDef.modcmd.loadModules(log, keyvals['modules'], testDef)
                if 0 != status:
                    log['status'] = status
                    log['stderr'] = stderr
                    return
                usedModule = True
        except KeyError:
            # not required to provide a module
            pass
        # save the current directory so we can return to it
        cwd = os.getcwd()
        # now move to the package location
        os.chdir(location)
        # see if they want us to execute autogen
        try:
            if keyvals['autogen_cmd'] is not None:
                print "LOCATION",location,"CMD",keyvals['autogen_cmd']
                agargs = []
                args = keyvals['autogen_cmd'].split()
                for arg in args:
                    agargs.append(arg.strip())
                status, stdout, stderr = testDef.execmd.execute(agargs, testDef)
            if 0 != status:
                log['status'] = status
                log['stdout'] = stdout
                log['stderr'] = stderr
                if usedModule:
                    # unload the modules before returning
                    testDef.modcmd.unloadModules(log, keyvals['modules'], testDef)
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
        location = os.path.join(testDef.options.scratchdir, "build", keyvals['section'])
        # need to remove any illegal characters like ':'
        location = re.sub('[^A-Za-z0-9]+:;', '', location)
        # convert it to an absolute path
        location = os.path.abspath(location)
        # record this location for any follow-on steps
        log['location'] = location
        prefix = "--prefix={0}".format(location)
        cfgargs.append(prefix)
        # if they gave us any configure args, add them
        try:
            if keyvals['configure_options'] is not None:
                args = keyvals['configure_options'].split()
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
                testDef.modcmd.unloadModules(log, keyvals['modules'], testDef)
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
            if keyvals['make_options'] is not None:
                args = keyvals['make_options'].split()
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
                testDef.modcmd.unloadModules(log, keyvals['modules'], testDef)
            # return to original location
            os.chdir(cwd)
            return
        else:
            # this is a multistep operation, and so we need to
            # retain the output from each step in the log
            log['clean'] = (stdout, stderr)
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
                testDef.modcmd.unloadModules(log, keyvals['modules'], testDef)
            # return to original location
            os.chdir(cwd)
            return
        else:
            # this is a multistep operation, and so we need to
            # retain the output from each step in the log
            log['all'] = (stdout, stderr)
        # and finally, execute "make install"
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
            testDef.modcmd.unloadModules(log, keyvals['modules'], testDef)
        # return home
        os.chdir(cwd)
        return
