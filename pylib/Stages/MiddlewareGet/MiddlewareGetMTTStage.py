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
# @addtogroup MiddlewareGet
# [Ordering 300] Stage for getting middleware source code
# @}
class MiddlewareGetMTTStage(IPlugin):
    def __init__(self):
        # initialise parent class
        IPlugin.__init__(self)
    def print_name(self):
        print("Stage for getting middleware source code")

    def ordering(self):
        return 300
