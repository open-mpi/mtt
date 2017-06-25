#!/usr/bin/env python
#
# Copyright (c) 2016      Intel, Inc. All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

from __future__ import print_function
import os
from multiprocessing import Process
from BaseMTTUtility import *

## @addtogroup Utilities
# @{
# @section Harasser
# @}
class Harasser(BaseMTTUtility):
    def __init__(self):
        BaseMTTUtility.__init__(self)
        self.options = {}
        return

    def print_name(self):
        return "Harasser"

    def print_options(self, testDef, prefix):
        lines = testDef.printOptions(self.options)
        for line in lines:
            print(prefix + line)
        return

    def start(self, fn, params):
        if params is not None:
            if type(params) is list:
                # convert to tuple
                tparams = tuple(params)
            elif type(params) is tuple:
                tparams = params
            else:
                # insert the value into a tuple
                tparams = (params,)
            # define the process
            self.p = Process(target=fn, args=(tparams))
        else:
            # define the process without any args
            self.p = Process(target=fn)
        # spawn the new process
        self.p.start()
        return

    def stop(self):
        self.p.join()
        return self.p.exitcode

    def is_alive(self):
        return self.p.is_alive()

    def pid(self):
        return self.p.pid()

# usage
#
# harasser = testDef.harasser(fn, )
