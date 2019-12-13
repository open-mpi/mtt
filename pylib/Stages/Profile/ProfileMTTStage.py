#!/usr/bin/env python3
#
# Copyright (c) 2016-2018 Intel, Inc. All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#


from yapsy.IPlugin import IPlugin

## @addtogroup Stages
# @{
# @addtogroup Profile
# [Ordering 210] Stage for profiling the system upon which the tests will be conducted
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
