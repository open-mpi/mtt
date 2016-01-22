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
        self.command = None
        self.options = {}
        return

    def print_name(self):
        return "Module"

    def print_options(self, testDef, prefix):
        lines = testDef.printOptions(self.options)
        for line in lines:
            print prefix + line
        return

    def setCommand(self, options):
        try:
            self.command = options['module_cmd']
        except KeyError:
            print "Module command was not provided"
        return

    def loadModules(self, log, modules, testDef):
        if self.command is None:
            # cannot perform this operation
            log['status'] = 1
            log['stderr'] = "Module (lmod) capability was not found"
            return
        modules = modules.split()
        for mod in modules:
            mod = mod.strip()
            status,stdout,stderr = testDef.execmd.execute([self.command, "load", mod], testDef)
            if 0 != status:
                break
        log['status'] = status
        log['stdout'] = stdout
        log['stderr'] = stderr
        return

    def unloadModules(self, log, modules, testDef):
        if self.command is None:
            # cannot perform this operation
            log['status'] = 1
            log['stderr'] = "Module (lmod) capability was not found"
            return
        modules = modules.split()
        for mod in modules:
            mod = mod.strip()
            status,stdout,stderr = testDef.execmd.execute([self.command, "unload", mod], testDef)
            if 0 != status:
                break
        log['status'] = status
        log['stdout'] = stdout
        log['stderr'] = stderr
        return
