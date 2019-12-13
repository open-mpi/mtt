#!/usr/bin/env python3
#
# Copyright (c) 2015-2018  Intel, Inc. All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#


from yapsy.IPlugin import IPlugin

## @addtogroup Stages
# @{
# @addtogroup MiddlewareBuild
# [Ordering 400] Stage for building middleware such as MPI
# @}
class MiddlewareBuildMTTStage(IPlugin):
    def __init__(self):
        # initialise parent class
        IPlugin.__init__(self)
    def print_name(self):
        print("Stage for building middleware such as MPI")

    def ordering(self):
        return 400
