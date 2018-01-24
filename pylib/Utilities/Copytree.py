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
# @param  src                 The top directory of the tree to be copied
# @param  preserve_symlinks   Preserve symlinks instead of copying the contents
# @param  preserve_directory  Copies directory instead of contents
# @}
class Copytree(BaseMTTUtility):
    def __init__(self):
        BaseMTTUtility.__init__(self)
        self.options = {}
        self.options['src'] = (None, "The top directory of the tree to be copied")
        self.options['preserve_symlinks'] = ("0", "Preserve symlinks instead of copying the contents")
        self.options['preserve_directory'] = ("0", "Copies directory instead of contents")

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
        dst = os.path.join(testDef.options['scratchdir'], log['section'].replace(":","_"))
        # record the location
        log['location'] = dst
        # Check if already exists to skip if ASIS is set
        try:
            if cmds['asis'] and os.path.exists(dst) and os.path.isdir(dst):
                testDef.logger.verbose_print("As-Is location " + dst + " exists and is a directory")
                log['status'] = 0
                return
        except KeyError:
            pass
        # perform the copy
        try:
            # Cleanup the target directory if it exists
            if os.path.exists(dst):
                shutil.rmtree(dst)
            os.mkdir(dst)
            for srcpath in cmds['src'].split(','):
                srcpath = srcpath.strip()
                reload(distutils.dir_util)
                if cmds['preserve_directory'] != "0":
                    subdst = os.path.join(dst,os.path.basename(os.path.dirname(srcpath)))
                    if os.path.exists(subdst):
                        shutil.rmtree(subdst)
                    os.mkdir(subdst)
                    distutils.dir_util.copy_tree(srcpath, subdst, preserve_symlinks=int(cmds['preserve_symlinks']))
                else:
                    distutils.dir_util.copy_tree(srcpath, dst, preserve_symlinks=int(cmds['preserve_symlinks']))
            log['status'] = 0
        except (os.error, shutil.Error, \
                distutils.errors.DistutilsFileError) as e:
            log['status'] = 1
            log['stderr'] = str(e)
        return
