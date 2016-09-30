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

## @addtogroup Stages
# @{
# @addtogroup MiddlewareBuild
# ordering 400
# @}
class MiddlewareBuildMTTStage(IPlugin):
    def __init__(self):
        # initialise parent class
        IPlugin.__init__(self)
    def print_name(self):
        print("Stage for building middleware such as MPI")

    def ordering(self):
        return 400
