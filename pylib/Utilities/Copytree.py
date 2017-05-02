from __future__ import print_function
from builtins import str
#!/usr/bin/env python
#
# Copyright (c) 2015-2016 Intel, Inc. All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

import shutil
import distutils.dir_util
import os
from BaseMTTUtility import *

## @addtogroup Utilities
# @{
# @section Copytree
# @param  src    The top directory of the tree to be copied
# @}
class Copytree(BaseMTTUtility):
    def __init__(self):
        BaseMTTUtility.__init__(self)
        self.options = {}
        self.options['src'] = (None, "The top directory of the tree to be copied")

    def print_name(self):
        return "Copytree"

    def print_options(self, testDef, prefix):
        lines = testDef.printOptions(self.options)
        for line in lines:
            print(prefix + line)
        return

    def execute(self, log, keyvals, testDef):
        testDef.logger.verbose_print("Copytree Execute")
        # parse any provided options - these will override the defaults
        cmds = {}
        testDef.parseOptions(log, self.options, keyvals, cmds)
        # if they didn't provide a src, then we can't do anything

        try:
            if cmds['src'] is None:
                log['status'] = 1
                log['stderr'] = "Src directory not specified"
                return
        except KeyError:
            log['status'] = 1
            log['stderr'] = "Src directory not specified"
            return
        # define the dst directory
        dst = os.path.join(testDef.options['scratchdir'], log['section'])
        # record the location
        log['location'] = dst
        # perform the copy
        try:
            # Cleanup the target directory if it exists
            if os.path.exists(dst):
                shutil.rmtree(dst)
            os.mkdir(dst)
            for srcpath in cmds['src'].split(','):
                srcpath = srcpath.strip()
                distutils.dir_util.copy_tree(srcpath, dst)
            log['status'] = 0
        except (os.error, shutil.Error) as e:
            log['status'] = 1
            log['stderr'] = str(e)
        return
