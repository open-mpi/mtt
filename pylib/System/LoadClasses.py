from __future__ import print_function
from builtins import object
#!/usr/bin/env python
#
# Copyright (c) 2015-2018 Intel, Inc. All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

import os
import imp
import sys
import datetime
from bisect import *
from pathlib import Path

class LoadClasses(object):
    def __init__(self):
        self.stages = {};
        self.stageOrder = []
        self.stageOrderIndices = []
        self.tools = {};
        self.utilities = {};

    def print_name(self):
        return "LoadClasses"

    def load(self, directory):
        # Loop over every python file which has MTT in the
        # filename in this directory tree
        for filename in Path(directory).glob("**/*MTT*.py"):
            # Strip file extension
            modname = filename.stem

            # Do this on the stem because it is a string
            if "Stage" not in modname and "Tool" not in modname and "Utility" not in modname:
                continue

            try:
                # Python 2 requires string cast
                m = imp.load_source(modname, str(filename))
            except ImportError:
                print("ERROR: unable to load " + modname + " from file " + str(filename))
                exit(1)
            # add the class to the corresponding category
            try:
                cls = getattr(m, modname)
                a = cls()
                if "Stage" in modname:
                    # trim the MTTStage from the name - it was included
                    # solely to avoid confusion with global namespaces
                    modname = modname[:-8]
                    self.stages[modname] = a.__class__
                    # get the ordering index of this stage
                    order = a.__class__().ordering()
                    # find the point where it should be inserted
                    i = bisect_left(self.stageOrderIndices, order)
                    # now update both the indices and order
                    self.stageOrder.insert(i, modname)
                    self.stageOrderIndices.insert(i, order)
                elif "Tool" in modname:
                    # trim the MTTTool from the name - it was included
                    # solely to avoid confusion with global namespaces
                    modname = modname[:-7]
                    self.tools[modname] = a.__class__
                elif "Utility" in modname:
                    # trim the MTTUtility from the name - it was included
                    # solely to avoid confusion with global namespaces
                    modname = modname[:-10]
                    self.utilities[modname] = a.__class__
            except AttributeError:
                # just ignore it
                continue
