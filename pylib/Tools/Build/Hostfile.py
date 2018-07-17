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
from BuildMTTTool import *
import hostlist # python-hostlist package
import shlex
import math

## @addtogroup Tools
# @{
# @addtogroup Build
# @section Hostfile
# Builds a hostfile based on a nodelist
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
        self.options['nodeuse_ratio'] = (None, "Fraction of nodes to use")
        self.options['hostfile'] = (None, "Name of hostfile to generate")
        self.options['nodestatus_cmd'] = ("sinfo -N -h", "Command to print status of nodes")
        self.options['nodename_column'] = ("0", "Column index from nodestatus_cmd where nodename resides")
        self.options['nodestatus_column'] = ("3", "Column index from nodestatus_cmd where status of node resides")
        self.options['idle_status_string'] = ("idle", "String to check for when checking node status")
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

        # If they didn't give us a hostfile and nodelist (or nodeuse_ratio), then error out

        try:
            wrong_input_stderr = ""
            if cmds['hostfile'] is None:
                wrong_input_stderr += "No hostfile specified. "
            if cmds['nodelist'] is None and cmds['nodeuse_ratio'] is None:
                wrong_input_stderr += "No nodelist specified, or nodeuse_ratio specified. "
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
        status, stdout, stderr, time = testDef.execmd.execute(cmds, shlex.split(cmds['nodestatus_cmd']), testDef)
        if status != 0:
            log['status'] = 1
            log['stderr'] = "Command %s failed: %s" % (cmds['nodestatus_cmd'], " ".join(stderr))
            os.chdir(cwd)
            return
        stdout_split = [l.split() for l in stdout]
        try:
            nodename_column = int(cmds['nodename_column'])
        except ValueError:
            log['status'] = 1
            log['stderr'] = "Invalid nodename_column %s -- must be an integer" % cmds['nodename_column']
            os.chdir(cwd)
            return
        try:
            nodestatus_column = int(cmds['nodestatus_column'])
        except ValueError:
            log['status'] = 1
            log['stderr'] = "Invalid nodestatus_column %s -- must be an integer" % cmds['nodestatus_column']
        try:
            node_status = {l[nodename_column]: l[nodestatus_column] for l in stdout_split}
        except IndexError:
            log['status'] = 1
            log['stderr'] = "" 
            if nodename_column < 0 or nodename_column >= len(stdout_split[0]):
                log['stderr'] += "nodename_column is out of bounds: %s  " % str(nodename_column)
            if nodestatus_column < 0 or nodestatus_column >= len(stdout_split[0]):
                log['stderr'] += "nodestatus_column is out of bounds: %s  " % str(nodestatus_column)
            os.chdir(cwd)
            return

        if cmds['nodelist'] is not None:
            # Create hostlist from nodelist
            try:
                hosts = hostlist.expand_hostlist(cmds['nodelist'])
            except hostlist.BadHostlist:
                log['status'] = 1
                log['stderr'] = "Bad nodelist format: %s" % cmds['nodelist']
                os.chdir(cwd)
                return
        else:
            # use all hosts
            hosts = [l[nodename_column] for l in stdout_split]

        # Use a ratio of the nodes
        if cmds['nodeuse_ratio'] is not None:
            try:
                ratio = float(cmds['nodeuse_ratio'])
            except:
                try:
                    ratio = float(cmds['nodeuse_ratio'].split("/")[0])/float(cmds['nodeuse_ratio'].split("/")[1])
                except:
                    log['status'] = 1
                    log['stderr'] = "Bad nodeuse_ratio format: %s" % cmds['nodeuse_ratio']
                    os.chdir(cwd)
                    return
            idle_hosts = [h for h in hosts if node_status[h] == cmds['idle_status_string']]
            nonidle_hosts = [h for h in hosts if node_status[h] != cmds['idle_status_string']]
            num_nodes = int(math.ceil(float(len(hosts))*ratio))
            if num_nodes <= len(idle_hosts):
                hosts = idle_hosts[:num_nodes]
            else:
                hosts = idle_hosts + nonidle_hosts[:num_nodes - len(idle_hosts)]

        # Create hostfile from hostlist
        try:
            with open(cmds['hostfile'], "w") as f:
                f.write("\n".join(hosts))
                f.close()
        except IOError:
            log['status'] = 1
            log['stderr'] = "File exception when writing hostfile %s" % cmds['hostfile']
            os.chdir(cwd)
            return

        log['status'] = 0
        log['stdout'] = "Creation of hostfile %s from nodelist %s success" % (cmds['hostfile'],cmds['nodelist'])
        log['location'] = location

        # return to original location
        os.chdir(cwd)
        return
