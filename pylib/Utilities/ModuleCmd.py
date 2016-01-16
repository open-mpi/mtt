#!/usr/bin/env python
#
# Copyright (c) 2015-2016 Intel, Inc. All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

import sys
import select
import subprocess
from BaseMTTUtility import *

class ModuleCmd(BaseMTTUtility):
    def __init__(self):
        BaseMTTUtility.__init__(self)
        return

    def print_name(self):
        return "Module"

    def loadModules(self, log, modules, testDef):
        if testDef.modcmd is None:
            # cannot perform this operation
            log['status'] = 1
            log['stderr'] = "Module (lmod) capability was not found"
            return
        modules = modules.split()
        for mod in modules:
            mod = mod.strip()
            status,stdout,stderr = testDef.execmd.execute([testDef.modcmd, "load", mod], testDef)
            if 0 != status:
                break
        log['status'] = status
        log['stdout'] = stdout
        log['stderr'] = stderr
        return

    def unloadModules(self, log, modules, testDef):
        if testDef.modcmd is None:
            # cannot perform this operation
            log['status'] = 1
            log['stderr'] = "Module (lmod) capability was not found"
            return
        modules = modules.split()
        for mod in modules:
            mod = mod.strip()
            status,stdout,stderr = testDef.execmd.execute([testDef.modcmd, "unload", mod], testDef)
            if 0 != status:
                break
        log['status'] = status
        log['stdout'] = stdout
        log['stderr'] = stderr
        return
