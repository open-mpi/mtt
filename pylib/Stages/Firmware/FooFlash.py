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
from FirmwareMTTStage import *

## @addtogroup Stages
# @{
# @addtogroup Firmware
# @section FooFlash
# @}
class FooFlash(FirmwareMTTStage):

    def __init__(self):
        # initialise parent class
        FirmwareMTTStage.__init__(self)
        self.options = {}

    def activate(self):
        # get the automatic procedure from IPlugin
        IPlugin.activate(self)
        return

    def deactivate(self):
        IPlugin.deactivate(self)
        return

    def print_name(self):
        return "FooFlash"

    def print_options(self, testDef, prefix):
        lines = testDef.printOptions(self.options)
        for line in lines:
            print(prefix + line)

    def execute(self, log, keyvals, testDef):
        # execute whatever commands are provided, recording
        # the results in the log
        log['status'] = 1
        log['stderr'] = "Not implemented"
        return
