#!/usr/bin/env python
#
# Copyright (c) 2015-2017 Intel, Inc.  All rights reserved.
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
import hostlist # python-hostlist package

## @addtogroup Tools
# @{
# @addtogroup Build
# @section Hostfile
# @param parent      Section that precedes this one in the dependency tree
# @param nodelist    list of nodes to create hostfile from
# @param hostfile    name of hostfile to generate
# @}
class Hostfile(BuildMTTTool):
    def __init__(self):
        BuildMTTTool.__init__(self)
        self.activated = False
        self.options = {}
        self.options['parent'] = (None, "Section that precedes this one in the dependency tree")
        self.options['nodelist'] = (None, "List of nodes to create hostfile from")
        self.options['hostfile'] = (None, "Name of hostfile to generate")
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
        return "Hostfile"

    def print_options(self, testDef, prefix):
        lines = testDef.printOptions(self.options)
        for line in lines:
            print(prefix + line)
        return

    def execute(self, log, keyvals, testDef):
        testDef.logger.verbose_print("Hostfile Execute")
        # parse any provided options - these will override the defaults
        cmds = {}
        testDef.parseOptions(log, self.options, keyvals, cmds)

        # If they didn't give us a hostfile and nodelist, then error out
        try:
            wrong_input_stderr = ""
            if cmds['hostfile'] is None:
                wrong_input_stderr += "No hostfile specified. "
            if cmds['nodelist'] is None:
                wrong_input_stderr += "No nodelist specified. "
            if wrong_input_stderr:
                log['status'] = 1
                log['stderr'] = wrong_input_stderr
                return
        except KeyError:
            log['status'] = 1
            log['stderr'] = "Required input not in cmds"
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
            parentloc = os.path.join(os.getcwd(),log['options']['scratch'])
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
                if os.path.exists(os.path.join(location,cmds['hostfile'])):
                    testDef.logger.verbose_print("hostfile " + os.path.join(location,cmds['hostfile']) + " exists. Skipping...")
                    log['location'] = location
                    log['status'] = 0
                    return
                else:
                    testDef.logger.verbose_print("hostfile " + os.path.join(location,cmds['hostfile']) + " does not exist. Continuing...")
        except KeyError:
            pass

        # save the current directory so we can return to it
        cwd = os.getcwd()
        # now move to the package location
        if not os.path.exists(location):
            os.makedirs(location)
        os.chdir(location)

        ################################
        # Execute Plugin
        ################################
        
        # Create hostlist from nodelist
        try:
            hosts = hostlist.expand_hostlist(cmds['nodelist'])
        except hostlist.BadHostlist:
            log['status'] = 1
            log['stderr'] = "Bad nodelist format: %s" % cmds['nodelist']

        # Create hostfile from hostlist
        try:
            with open(cmds['hostfile'], "w") as f:
                f.write("\n".join(hosts))
                f.close()
        except IOError:
            log['status'] = 1
            log['stderr'] = "File exception when writing hostfile %s" % cmds['hostfile']

        log['status'] = 0
        log['stdout'] = "Creation of hostfile %s from nodelist %s success" % (cmds['hostfile'],cmds['nodelist'])
        log['location'] = location

        # return to original location
        os.chdir(cwd)
        return
