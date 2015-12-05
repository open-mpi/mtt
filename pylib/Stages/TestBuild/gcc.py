# -*- coding: utf-8; tab-width: 4; indent-tabs-mode: f; python-indent: 4 -*-
#
# Copyright (c) 2015      Intel, Inc. All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#


from TestBuildMTTStage import *

class File(TestBuildMTTStage):

    def __init__(self):
        """
        init
        """
        # initialise parent class
        TestBuildMTTStage.__init__(self)


    def activate(self):
        """
        Report success on activation as there is nothing to do
        """
        # get the automatic procedure from IPlugin
        IPlugin.activate(self)
        return


    def deactivate(self):
        """
        Deactivate if activated
        """
        IPlugin.deactivate(self)
        return

    def print_name(self):
        return "GCC"
