#!/usr/bin/env python
#
# Copyright (c) 2015      Intel, Inc. All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

from __future__ import print_function
from yapsy.IPlugin import IPlugin

class ReporterMTTStage(IPlugin):
    def __init__(self):
        # initialise parent class
        IPlugin.__init__(self)
    def print_name(self):
        print("Report test results stage")

    def ordering(self):
        return 600
