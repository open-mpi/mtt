# -*- coding: utf-8; tab-width: 4; indent-tabs-mode: f; python-indent: 4 -*-
#
# Copyright (c) 2015-2016 Intel, Inc. All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#


from VersionMTTTool import *

# Major and minor version number of the MTT

MTTMajor = "4";
MTTMinor = "0";
MTTRelease = "0";
MTTGreek = "a1";

# Major and minor version number of the Python MTT Client
MTTPyClientMajor = "1"
MTTPyClientMinor = "0"
MTTPyClientRelease = "0"
MTTPyClientGreek = "a1"


class MTTVersionPlugin(VersionMTTTool):

    def __init__(self):
        # initialise parent class
        VersionMTTTool.__init__(self)


    def activate(self):
        # get the automatic procedure from IPlugin
        IPlugin.activate(self)
        return


    def deactivate(self):
        IPlugin.deactivate(self)
        return

    def print_name(self):
        return "MTTVersion"

    def print_options(self, testDef, prefix):
        print prefix + "None"
        return

    def getVersion(self):
        return '{}.{}.{}{}'.format(MTTMajor, MTTMinor, MTTRelease, MTTGreek)

    def getClientVersion(self):
        return '{}.{}.{}{}'.format(MTTPyClientMajor, MTTPyClientMinor, MTTPyClientRelease, MTTPyClientGreek)
