# -*- coding: utf-8; tab-width: 4; indent-tabs-mode: f; python-indent: 4 -*-
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
from ProfileMTTStage import *

## @addtogroup Stages
# @{
# @addtogroup Profile
# @section DefaultProfile
# @param kernelVersion    Kernel version string
# @param nodeName         Node name
# @param kernelRelease    Kernel release string
# @param machineName      Machine name
# @param processorType    Processor type
# @param kernelName       Kernel name
# @}
class DefaultProfile(ProfileMTTStage):

    def __init__(self):
        # initialise parent class
        ProfileMTTStage.__init__(self)
        self.options = {}
        self.options['kernelName'] = (True, "Kernel name", ["uname", "-s"])
        self.options['kernelRelease'] = (True, "Kernel release string", ["uname", "-r"])
        self.options['kernelVersion'] = (True, "Kernel version string", ["uname", "-v"])
        self.options['machineName'] = (True, "Machine name", ["uname", "-m"])
        self.options['processorType'] = (True, "Processor type", ["uname", "-p"])
        self.options['nodeName'] = (True, "Node name", ["uname", "-n"])
        return

    def activate(self):
        # get the automatic procedure from IPlugin
        IPlugin.activate(self)
        return


    def deactivate(self):
        IPlugin.deactivate(self)
        return

    def print_name(self):
        return "DefaultProfile"

    def print_options(self, testDef, prefix):
        lines = testDef.printOptions(self.options)
        for line in lines:
            print(prefix + line)
        return

    def execute(self, log, keyvals, testDef):
        testDef.logger.verbose_print("Collect system profile")
        # collect general information on the system
        myLog = {}
        # see what they want us to collect
        cmds = {}
        testDef.parseOptions(log, self.options, keyvals, cmds)
        keys = list(cmds.keys())
        opts = self.options.keys()
        for key in keys:
            if cmds[key] and key in opts:
                status, stdout, stderr = testDef.execmd.execute(cmds, self.options[key][2], testDef)
                if 0 != status:
                    log['status'] = status
                    log['stdout'] = stdout
                    log['stderr'] = stderr
                    return
                myLog[key] = stdout
        # add our log to the system log
        log['profile'] = myLog
        log['status'] = 0
        return
