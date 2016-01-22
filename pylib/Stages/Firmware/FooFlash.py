# -*- coding: utf-8; tab-width: 4; indent-tabs-mode: f; python-indent: 4 -*-
#
# Copyright (c) 2015-2016 Intel, Inc. All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#


from FirmwareMTTStage import *

class FooFlash(FirmwareMTTStage):

    def __init__(self):
        # initialise parent class
        FirmwareMTTStage.__init__(self)


    def activate(self):
        # get the automatic procedure from IPlugin
        IPlugin.activate(self)
        return


    def deactivate(self):
        IPlugin.deactivate(self)
        return

    def print_name(self):
        return "FooFlash"

    def print_options(self, testDef, prefix):
        print prefix + "None"
