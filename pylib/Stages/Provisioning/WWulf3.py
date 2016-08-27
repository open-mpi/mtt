# -*- coding: utf-8; tab-width: 4; indent-tabs-mode: f; python-indent: 4 -*-
#
# Copyright (c) 2015-2016 Intel, Inc. All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

from __future__ import print_function
from ProvisionMTTStage import *

class WWulf3(ProvisionMTTStage):

    def __init__(self):
        # initialise parent class
        ProvisionMTTStage.__init__(self)
        self.options = {}
        self.options['target'] = (None, "Remote host name for LAN interface")

    def activate(self):
        # use the automatic procedure from IPlugin
        IPlugin.activate(self)
        return


    def deactivate(self):
        IPlugin.deactivate(self)


    def print_name(self):
        return "WWulf3"

    def print_options(self, testDef, prefix):
        lines = testDef.printOptions(self.options)
        for line in lines:
            print(prefix + line)
        return

    def execute(self, log, keyvals, testDef):
        testDef.logger.verbose_print("Warewulf 3 Provisioner")
        # check for a modules directive
        mods = None
        try:
            if keyvals['modules'] is not None:
                if testDef.modcmd is None:
                    # cannot execute this request
                    log['stderr'] = "No module support available"
                    log['status'] = 1
                    return
                # create a list of the requested modules
                mods = keyvals['modules'].split(',')
                # have them loaded
                status,stdout,stderr = testDef.modcmd.loadModules(mods, testDef)
                if 0 != status:
                    log['status'] = status
                    log['stdout'] = stdout
                    log['stderr'] = stderr
                    return
        except KeyError:
            pass

        # parse what we were given against our defined options
        cmds = {}
        testDef.parseOptions(log, self.options, keyvals, cmds)
        # they had to at least give us the target node

        # update the provisioning database to the new image

        # power cycle the node


