# -*- coding: utf-8; tab-width: 4; indent-tabs-mode: f; python-indent: 4 -*-
#
# Copyright (c) 2015-2018 Intel, Inc.  All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

from __future__ import print_function
from ProvisionMTTStage import *
import shlex

## @addtogroup Stages
# @{
# @addtogroup Provision
# @section WWulf3
# Plugin for provisioning nodes using the Warewulf v3 image manager
# @param target           List of remote host names or LAN interfaces to be provisioned
# @param image            Name of image to be instantiated
# @param bootstrap        Name of bootstrap to be used
# @param controller       List of IP addresses of remote node controllers/BMCs
# @param username         Remote controller username
# @param password         Remote controller password
# @param pwfile           File containing remote controller password
# @param sudo             Use sudo to execute privileged commands
# @param allocate_cmd     Command to use for allocating nodes from the resource manager
# @param deallocate_cmd   Command to use for deallocating nodes from the resource manager
# @}
class WWulf3(ProvisionMTTStage):

    def __init__(self):
        # initialise parent class
        ProvisionMTTStage.__init__(self)
        self.options = {}
        self.options['target'] = (None, "List of remote host names or LAN interfaces to be provisioned")
        self.options['image'] = (None, "Name of image to be instantiated")
        self.options['bootstrap'] = (None, "Name of bootstrap to be used")
        self.options['controller'] = (None, "List of IP addresses of remote node controllers/BMCs")
        self.options['username'] = (None, "Remote controller username")
        self.options['password'] = (None, "Remote controller password")
        self.options['pwfile'] = (None, "File containing remote controller password")
        self.options['sudo'] = (False, "Use sudo to execute privileged commands")
        self.options['allocate_cmd'] = (None, "Command to use for allocating nodes from the resource manager")
        self.options['deallocate_cmd'] = (None, "Command to use for deallocating nodes from the resource manager")

        self.allocated = False
        self.testDef = None
        self.cmds = None
        return


    def activate(self):
        # use the automatic procedure from IPlugin
        IPlugin.activate(self)
        return


    def deactivate(self):
        IPlugin.deactivate(self)
        if self.allocated and self.testDef and self.cmds:
            self.deallocate({}, self.cmds, self.testDef)

    def print_name(self):
        return "WWulf3"


    def print_options(self, testDef, prefix):
        lines = testDef.printOptions(self.options)
        for line in lines:
            print(prefix + line)
        return

    def allocate(self, log, cmds, testDef):
        self.allocated = False
        if cmds['allocate_cmd'] is not None and cmds['deallocate_cmd'] is not None:
            allocate_cmdargs = shlex.split(cmds['allocate_cmd'])
            status,stdout,stderr,time = testDef.execmd.execute(cmds, allocate_cmdargs, testDef)
            if 0 != status:
                log['status'] = status
                if log['stderr']:
                    log['stderr'].extend(stderr)
                else:
                    log['stderr'] = stderr
                return False
            self.allocated = True
        return True

    def deallocate(self, log, cmds, testDef):
        if cmds['allocate_cmd'] is not None and cmds['deallocate_cmd'] is not None and self.allocated == True:
            deallocate_cmdargs = shlex.split(cmds['deallocate_cmd'])
            status,stdout,stderr,time = testDef.execmd.execute(cmds, deallocate_cmdargs, testDef)
            if 0 != status:
                log['status'] = status
                if log['stderr']:
                    log['stderr'].extend(stderr)
                else:
                    log['stderr'] = stderr
                return False
            self.allocated = False
        return True

    def execute(self, log, keyvals, testDef):
        testDef.logger.verbose_print("Warewulf 3 Provisioner")
        # parse what we were given against our defined options
        cmds = {}
        testDef.parseOptions(log, self.options, keyvals, cmds)

        mylog = {}
        if cmds['target']:
            mylog['target'] = cmds['target']
        if cmds['image']:
            mylog['image'] = cmds['image']
        if cmds['controller']:
            mylog['controller'] = cmds['controller']
        if cmds['bootstrap']:
            mylog['bootstrap'] = cmds['bootstrap']
        log['provisioning'] = mylog

        # they had to at least give us one target node and controller
        try:
            if cmds['target'] is None:
                log['status'] = 1
                log['stderr'] = "No target hosts identified"
                return
            else:
                # convert to a list
                targets = cmds['target'].split(',')
        except:
            log['status'] = 1
            log['stderr'] = "No target hosts identified"
            return
        try:
            if cmds['controller'] is None:
                log['status'] = 1
                log['stderr'] = "No target controllers identified"
                return
            else:
                # convert to a list
                controllers = cmds['controller'].split(',')
        except:
            log['status'] = 1
            log['stderr'] = "No target controllers identified"
            return
        # must give us an image
        try:
            if cmds['image'] is None:
                log['status'] = 1
                log['stderr'] = "No image specified"
                return
        except:
            log['status'] = 1
            log['stderr'] = "No image specified"
            return

        # sanity check the provided nodes to ensure they are in the
        # database - output goes to stdout
        wwcmd = ["wwsh", "node", "list"]
        if cmds['sudo']:
            wwcmd.insert(0, "sudo")
        status,stdout,stderr,_ = testDef.execmd.execute(cmds, wwcmd, testDef)
        if 0 != status or stdout is None:
            log['status'] = status
            log['stderr'] = "Node list was not obtained"
            return
        # skip first two lines as they are headers
        del stdout[0:2]
        # parse each line to collect out the individual nodes
        nodes = []
        for line in stdout:
            # node name is at the front, ended by a space
            nodes.append(line[0:line.find(' ')])
        # now check that each target is in the list of nodes - no
        # way around just a big double-loop, i fear
        for tgt in targets:
            found = False
            for node in nodes:
                if tgt == node:
                    found = True
                    break
            if not found:
                log['status'] = 1
                log['stderr'] = "Target " + tgt + " is not included in Warewulf node table"
                return

        # Allocate cluster
        if False == self.allocate(log, cmds, testDef):
            return

        # if we get here, then all the targets are known!
        # so cycle thru the targets and update the provisioning
        # database for each of them
        for tgt in targets:
            wwcmd = ["wwsh", "provision", "set"]
            if cmds['sudo']:
                wwcmd.insert(0, "sudo")
            wwcmd.append(tgt)
            wwcmd.append("--vnfs=" + cmds['image'])
            if cmds['bootstrap']:
               wwcmd.append("--bootstrap=" + cmds['bootstrap'])
            # update the provisioning database to the new image
            status,stdout,stderr,_ = testDef.execmd.execute(cmds, wwcmd, testDef)
            if 0 != status:
                log['status'] = status
                log['stderr'] = stderr
                self.deallocate(log, cmds, testDef)
                return
        # assemble command to power cycle each node. Note that
        # we will be passing a set of keyvals down, so we can
        # include directives such as 'sudo' there
        ipmicmd = {}
        ipmicmd['command'] = ["power", "cycle"]
        ipmicmd['target'] = cmds['target']
        ipmicmd['controller'] = cmds['controller']
        ipmicmd['username'] = cmds['username']
        ipmicmd['password'] = cmds['password']
        ipmicmd['pwfile'] = cmds['pwfile']
        ipmicmd['sudo'] = cmds['sudo']
        # find the IPMITool plugin
        # order the nodes to power cycle
        ipmitool = testDef.selectPlugin("IPMITool", "tool")
        if ipmitool is None:
            log['status'] = 1
            log['stderr'] = "IPMITool was not found"
            self.deallocate(log, cmds, testDef)
            return
        # execute the request
        ipmilog = {}
        ipmitool.execute(ipmilog, ipmicmd, testDef)

        # update our results to reflect the overall status
        log['status'] = ipmilog['status']
        if ipmilog['stdout'] is not None:
            log['stdout'] = ipmilog['stdout']
        if ipmilog['stderr'] is not None:
            log['stderr'] = ipmilog['stderr']

        # Deallocate cluster
        self.deallocate(log, cmds, testDef)

        return
