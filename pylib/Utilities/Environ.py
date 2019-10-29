#!/usr/bin/env python
#
# Copyright (c) 2015-2018 Intel, Inc. All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

from __future__ import print_function
import shutil
import os
from BaseMTTUtility import *

## @addtogroup Utilities
# @{
# @section Environ
# Set environment variables
# @}
class Environ(BaseMTTUtility):
    def __init__(self):
        BaseMTTUtility.__init__(self)
        self.options = {}

    def print_name(self):
        return "Environ"

    def print_options(self, testDef, prefix):
        lines = testDef.printOptions(self.options)
        for line in lines:
            testDef.logger.print(prefix + line)
        return

    def execute(self, log, keyvals, testDef):
        testDef.logger.verbose_print("Environ Execute")

        # Set any provided key values
        kvkeys = keyvals.keys()
        for kvkey in kvkeys:
            os.environ[kvkey] = keyvals[kvkey]
        log['status'] = 0
        log['environ'] = keyvals
        return
