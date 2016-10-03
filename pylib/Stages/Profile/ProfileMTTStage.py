#!/usr/bin/env python
#
# Copyright (c) 2016      Intel, Inc. All rights reserved.
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
# @addtogroup Profile
# ordering 210
# @}
class ProfileMTTStage(IPlugin):
    def __init__(self):
        # initialise parent class
        IPlugin.__init__(self)
    def print_name(self):
        print("Stage for profiling the system upon which the tests will be conducted")

    def ordering(self):
        # set this stage so it follows BIOS, firmware, and provisioning
        # so we profile the final system
        return 210
