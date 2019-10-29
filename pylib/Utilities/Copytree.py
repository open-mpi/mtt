from __future__ import print_function
from builtins import str
#!/usr/bin/env python
#
# Copyright (c) 2015-2018 Intel, Inc. All rights reserved.
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

from sys import version_info
if version_info[0] == 3:
  if version_info[1] <= 3:
    from imp import reload
  else :
    from importlib import reload
## @addtogroup Utilities
# @{
# @section Copytree
# Copy a directory tree from source to the same relative loation under the MTT scratch directory
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
            testDef.logger.print(prefix + line)
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
                shutil.rmtree(dst, ignore_errors=True)
            if not os.path.exists(dst):
                os.mkdir(dst)
            for srcpath in cmds['src'].split(','):
                srcpath = srcpath.strip()
                reload(distutils.dir_util)
                if cmds['preserve_directory'] != "0":
                    subdst = os.path.join(dst,os.path.basename(srcpath))
                    while os.path.exists(subdst):
                        shutil.rmtree(subdst, ignore_errors=True)
                    if not os.path.exists(dst):
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
