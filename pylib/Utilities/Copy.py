from __future__ import print_function
from builtins import str
#!/usr/bin/env python
#
# Copyright (c) 2015-2019 Intel, Inc. All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

import shutil
import distutils.dir_util
import distutils.file_util
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
# @section Copy
# Copy a comma separated list of files, directories, and links
# @param  src                 The name of the file, directory, or link to be copied
# @param  preserve_symlinks   Preserve symlinks found inside directories
# @}
class Copy(BaseMTTUtility):
    def __init__(self):
        BaseMTTUtility.__init__(self)
        self.options = {}
        self.options['src'] = (None, "Copy a comma separated list of files, directories, and links")
        self.options['preserve_symlinks'] = ("0", "Preserve symlinks found inside directories")

    def print_name(self):
        return "Copy"

    def print_options(self, testDef, prefix):
        lines = testDef.printOptions(self.options)
        for line in lines:
            print(prefix + line)
        return

    def execute(self, log, keyvals, testDef):
        testDef.logger.verbose_print("Copy Execute")
        # parse any provided options - these will override the defaults
        cmds = {}
        testDef.parseOptions(log, self.options, keyvals, cmds)
        # if they didn't provide a src, then we can't do anything

        try:
            if cmds['src'] is None:
                log['status'] = 1
                log['stderr'] = "src not specified"
                return
        except KeyError:
            log['status'] = 1
            log['stderr'] = "src directory not specified"
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
            for src in cmds['src'].split(','):
                src = src.strip()
                # Clear the cache so that distutils.dir_util doesn't assume the same directory structure from last time things were copied
                reload(distutils.dir_util)
                if os.path.isdir(src):
                    # Distutils copy tree copies the contents of the directory into the target dir
                    # Modify that to copy the directory
                    dst_dir = os.path.join(dst,os.path.basename(src))
                    os.mkdir(dst_dir)
                    distutils.dir_util.copy_tree(src, dst_dir, preserve_symlinks=int(cmds['preserve_symlinks']))
                else:
                    distutils.file_util.copy_file(src, dst)
            log['status'] = 0
        except (os.error, shutil.Error, \
                distutils.errors.DistutilsFileError) as e:
            log['status'] = 1
            log['stderr'] = str(e)
        return
