from __future__ import print_function
from builtins import str
#!/usr/bin/env python
#
# Copyright (c) 2015-2016 Intel, Inc. All rights reserved.
# Copyright (c) 2018      Los Alamos National Security, LLC. 
#                         All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

import shutil
import os
from threading import Timer
from BaseMTTUtility import *

## @addtogroup Utilities
# @{
# @section Watchdog
# @param  timeout  Time in seconds before generating exception
# @}
class Watchdog(BaseMTTUtility):
    def __init__(self, timeout=360):
        BaseMTTUtility.__init__(self)
        self.timeout = timeout
        self.options = {}
        self.options['time'] = (None, "Time in seconds before generating exception")
        self.timer = Timer(self.timeout, self.defaultHandler)

    def reset(self):
        self.timer.cancel()
        self.timer = Timer(self.timeout, self.defaultHandler)

    def stop(self):
        self.timer.cancel()

    def defaultHandler(self):
        raise self

# Usage if you want to make sure an operation finishes in less than x seconds:

#   watchdog = testDef.watchdog(x)
#   try:
#      do something
#   except Watchdog:
#      handle timeout
#   watchdog.stop()
