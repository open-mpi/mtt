#!/usr/bin/env python
#
# Copyright (c) 2016      Intel, Inc. All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

import os
import sys
from CNCMTTTool import *

class IPMITool(CNCMTTTool):
    def __init__(self):
        CNCMTTTool.__init__(self)
        self.options = {}
        self.options['target'] = (None, "Remote host name or LAN interface")
        self.options['controller'] = (None, "IP address of remote node's controller/BMC")
        self.options['username'] = (None, "Remote session username")
        self.options['password'] = (None, "Remote session password")
        self.options['pwfile'] = (None, "File containing remote session password")
        self.options['command'] = (None, "Command to be sent")
        self.options['maxtries'] = (100, "Max number of times to ping the host before declaring reset to fail")
        return

    def activate(self):
        # use the automatic procedure from IPlugin
        IPlugin.activate(self)
        return

    def deactivate(self):
        IPlugin.deactivate(self)

    def print_name(self):
        return "IPMITool"

    def print_options(self, testDef, prefix):
        lines = testDef.printOptions(self.options)
        for line in lines:
            print(prefix + line)
        return

    def execute(self, log, keyvals, testDef):
        testDef.logger.verbose_print("IPMITool power cycle")
        # check for a modules directive
        mods = None
        try:
            if keyvals['modules'] is not None:
                if testDef.modcmd is None:
                    # cannot execute this request
                    log['stderr'] = "No module support available"
                    log['status'] = 1
                    return
                # create a list of the requested modules
                mods = keyvals['modules'].split(',')
                # have them loaded
                status,stdout,stderr = testDef.modcmd.loadModules(mods, testDef)
                if 0 != status:
                    log['status'] = status
                    log['stdout'] = stdout
                    log['stderr'] = stderr
                    return
                modloaded = True
        except KeyError:
            pass

        # parse what we were given against our defined options
        cmds = {}
        testDef.parseOptions(log, self.options, keyvals, cmds)
        # must at least have a target
        try:
            if cmds['target'] is None:
                log['status'] = 1
                log['stderr'] = "No target node identified"
                return
        except:
            log['status'] = 1
            log['stderr'] = "No target node identified"
            return
        # and a controller address
        try:
            if cmds['controller'] is None:
                log['status'] = 1
                log['stderr'] = "No target controller identified"
                return
        except:
            log['status'] = 1
            log['stderr'] = "No target controller identified"
            return
        # and a command
        try:
            if cmds['command'] is None:
                log['status'] = 1
                log['stderr'] = "No IPMI command given"
                return
        except:
            log['status'] = 1
            log['stderr'] = "No IPMI command given"
            return
        # construct the cmd
        ipmicmd = cmds['command'].split()
        ipmicmd.insert(0, "ipmitool")
        ipmicmd.append("-H")
        ipmicmd.append(cmds['controller'])
        if cmds['username'] is not None:
            ipmicmd.append("-U")
            ipmicmd.append(cmds['username'])
        if cmds['password'] is not None:
            ipmicmd.append("-P")
            ipmicmd.append(cmds['password'])
        # execute it
        testDef.logger.verbose_print("IPMITool: " + ' '.join(ipmicmd))
        status,stdout,stderr = testDef.execmd.execute(ipmicmd, testDef)
        if 0 == status:
            # need to wait for the node to come back
            ntries = 0
            ckcmd = ["ping", "-c", "1", cmds['target']]
            while True:
                ++ntries
                status,stdout,stderr = testDef.execmd.execute(ckcmd, testDef)
                if 0 == status or ntries == cmds['maxtries']:
                    testDef.logger.verbose_print("IPMITool: node " + cmds['target'] + " is back")
                    break
        log['status'] = status
        log['stdout'] = stdout
        log['stderr'] = stderr
        if mods is not None:
            testDef.modcmd.unloadModules(mods, testDef)
        return
