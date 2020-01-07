# -*- coding: utf-8; tab-width: 4; indent-tabs-mode: f; python-indent: 4 -*-
#
# Copyright (c) 2020 Intel, Inc.  All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#


import os
import sys
from ReporterMTTStage import *

## @addtogroup Stages
# @{
# @addtogroup Reporter
# @section LogInterpolationDebug
# Debug tool for ${LOG:....} interpolation syntax
# @}
class LogInterpolationDebug(ReporterMTTStage):

    def __init__(self):
        # initialise parent class
        ReporterMTTStage.__init__(self)
        self.options = {}

    def activate(self):
        # get the automatic procedure from IPlugin
        IPlugin.activate(self)
        return


    def deactivate(self):
        IPlugin.deactivate(self)
        return

    def print_name(self):
        return "LogInterpolationDebug"

    def print_options(self, testDef, prefix):
        lines = testDef.printOptions(self.options)
        for line in lines:
            print(prefix + line)
        return

    def execute(self, log, keyvals, testDef):
        self.fh = sys.stdout
        testDef.logger.verbose_print("LOG Interpolation Debugging Tool")

        config = testDef.config

        for k,v in config._sections['LOG'].items():
            if v.startswith('{') and v.endswith('}') and not k.split('.')[-1].isnumeric():
                if len(v) <= 2:
                    print('${LOG:%s} = {}' % k)
                else:
                    print('${LOG:%s} = {' % k, '.' * max(3, v.count(',') + 1), '}')
            elif v.startswith('[') and v.endswith(']') and not k.split('.')[-1].isnumeric():
                if len(v) <= 2:
                    print('${LOG:%s} = []' % k)
                else:
                    print('${LOG:%s} = [' % k, '.' * max(3, v.count(',') + 1), ']')
            else:
                print('${LOG:%s} = %s' % (k, v))

        log['status'] = 0
        return
