#!/usr/bin/env python3
#
# Copyright (c) 2015-2018 Intel, Inc. All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#


from yapsy.IPlugin import IPlugin

## @addtogroup Tools
# @{
# @addtogroup CNC
# Comand and control tools for system managment
# @}
class CNCMTTTool(IPlugin):
    def __init__(self):
        # initialise parent class
        IPlugin.__init__(self)

    def print_name(self):
        print("CNC")

