#!/usr/bin/env python
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
# @addtogroup Version
# Tools that collect version information
# @}
class VersionMTTTool(IPlugin):
    def __init__(self):
        # initialise parent class
        IPlugin.__init__(self)

