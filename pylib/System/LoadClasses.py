from __future__ import print_function
from builtins import object
#!/usr/bin/env python
#
# Copyright (c) 2015-2016 Intel, Inc. All rights reserved.
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
        oldcwd = os.getcwd()
        os.chdir(directory)   # change our working dir
        for filename in os.listdir(directory):
            # if this filename is a directory, then recurse into it
            if os.path.isdir(filename):
                filename = os.path.join(directory, filename)
                self.load(filename)
                continue
            # we require an "MTT" to be in the name of all
            # class files to distinguish them from anything else
            if "MTT" not in filename:
                continue
            # class files must end in ".py" - this helps us
            # avoid the compiled version of Python files, which
            # end in ".pyc"
            if not filename.endswith(".py"):
                continue
            # To further distinguish the contents of the files,
            # we separate them by function - therefore, we require
            # that the filename indicate the functional category
            # for the enclosed class
            if "Stage" not in filename and "Tool" not in filename and "Utility" not in filename:
                continue
            # import/load the class from the file
            modname = filename[:-3]
            try:
                m = imp.load_source(modname, filename)
            except ImportError:
                print("ERROR: unable to load " + modname + " from file " + filename)
                exit(1)
            # add the class to the corresponding category
            try:
                cls = getattr(m, modname)
                a = cls()
                if "Stage" in modname:
                    # trim the MTTClass from the name - it was included
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
        os.chdir(oldcwd)
