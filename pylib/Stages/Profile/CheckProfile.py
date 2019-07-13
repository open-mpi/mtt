# -*- coding: utf-8; tab-width: 4; indent-tabs-mode: f; python-indent: 4 -*-
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
from ProfileMTTStage import *
from ast import literal_eval
import operator

## @addtogroup Stages
# @{
# @addtogroup Profile
# @section CheckProfile
# Check hardware and software profile value of the system against a threshold
# @param diskSpace check a disks % avail (/opt >= 10%)
# @param memory    check free, used or total memory value in G (free >= 5G)
# @}
class CheckProfile(ProfileMTTStage):

    diskSpaceCmd   = ["sh", "-c", "df -BM --output=pcent DISK | grep -v Use"]
    memoryFreeCmd  = ["sh", "-c", "free -h -o | grep Mem: | awk '{print $4}'"]
    memoryTotalCmd = ["sh", "-c", "free -h -o | grep Mem: | awk '{print $2}'"]
    memoryUsedCmd  = ["sh", "-c", "free -h -o | grep Mem: | awk '{print $3}'"]

    ops = { '>': operator.gt,
            '<': operator.lt,
            '>=': operator.ge,
            '<=': operator.le,
            '=': operator.eq
    }

    def __init__(self):
        # initialise parent class
        ProfileMTTStage.__init__(self)
        self.options = {}

        # diskSpace = /var/hit >= 5%, /opt/hit >= 5%
        self.options['diskSpace'] = (None, "check", "/ >= 5%")
        # memory = free >= 10G
        self.options['memory'] = (None, "check", "free >= 1G")
        return

    def activate(self):
        # get the automatic procedure from IPlugin
        IPlugin.activate(self)
        return


    def deactivate(self):
        IPlugin.deactivate(self)
        return

    def print_name(self):
        return "CheckProfile"

    def print_options(self, testDef, prefix):
        lines = testDef.printOptions(self.options)
        for line in lines:
            print(prefix + line)
        return

    def execute(self, log, keyvals, testDef):
        testDef.logger.verbose_print("Checking diskspace")
        # collect general information on the system
        myLog = {}

        # see what they want us to collect
        cmds = {}

        testDef.parseOptions(log, self.options, keyvals, cmds)

        keys = list(cmds.keys())
        opts = self.options.keys()

        for key in keys:
            # diskSpace
            if key == 'diskSpace' and cmds[key] and key in opts:
                for check in keyvals[key].split(","):
                    testDef.logger.verbose_print("Checking: " + check)
                    disk, op, pcent = check.split()
                    pcentNeeded = int(pcent.split('%')[0])

                    cmd = self.diskSpaceCmd[2].replace("DISK", disk)
                    results = testDef.execmd.execute(cmds,
                        [self.diskSpaceCmd[0], self.diskSpaceCmd[1], cmd], testDef)

                    if 0 != results['status']:
                        log['status'] = results['status']
                        log['stdout'] = results['stdout']
                        log['stderr'] = results['stderr']
                        # ignore the execution time, if collected
                        return

                    pcentAvail = 100 - int(stdout[0].split('%')[0])
                    myLog[key+' '+disk] = [str(pcentAvail) + "% available"]

                    testDef.logger.verbose_print("checking: " + disk \
                        + " %avail: " + str(pcentAvail) + " is " + op \
                        + " %needed: " + str(pcentNeeded))

                    if not self.ops[ op ](pcentAvail, pcentNeeded):
                        log['status'] = 1
                        log['stderr'] = "check failed: " + disk \
                            + " %avail: " + str(pcentAvail) + " is not " \
                            + op + " %needed: " + str(pcentNeeded)
                        return

            # memory
            if key == 'memory' and cmds[key] and key in opts:
                for check in keyvals[key].split(","):
                    testDef.logger.verbose_print("Checking: " + check)
                    kind, op, gigs = check.split()
                    gigsNeeded = float(gigs.split('G')[0])

                    cmd = self.memoryTotalCmd[2]
                    if kind == 'free':
                        cmd = self.memoryFreeCmd[2]
                    if kind == 'used':
                        cmd = self.memoryUsedCmd[2]

                    results = testDef.execmd.execute(cmds,
                        [self.diskSpaceCmd[0], self.diskSpaceCmd[1], cmd], testDef)

                    if 0 != results['status']:
                        log['status'] = results['status']
                        log['stdout'] = results['stdout']
                        log['stderr'] = results['stderr']
                        # ignore the execution time, if collected
                        return

                    gigsAvail = float(results['stdout'][0].split('G')[0])
                    myLog['memory '+kind] = results['stdout']

                    testDef.logger.verbose_print("checking: " + kind \
                        + " memory: " + str(gigsAvail) + "G is " + op \
                        + " requested: " + str(gigsNeeded) + "G")

                    if not self.ops[ op ](gigsAvail, gigsNeeded):
                        log['status'] = 1
                        log['stderr'] = "check failed: " + kind \
                            + " memory: " + str(gigsAvail) + "G is not " \
                            + op + " requested: " + str(gigsNeeded) +"G"
                        return

        # add our log to the system log
        log['profile'] = myLog
        log['status'] = 0

        return
