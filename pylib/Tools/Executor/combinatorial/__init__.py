# -*- coding: utf-8; tab-width: 4; indent-tabs-mode: f; python-indent: 4 -*-
#
# Copyright (c) 2015      Intel, Inc. All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

from ExecutorMTTTool import *

class CombinatorialEx(ExecutorMTTTool):

	def __init__(self):
		"""
		init
		"""
		# initialise parent class
		ExecutorMTTTool.__init__(self)


	def activate(self):
		# use the automatic procedure from IPlugin
		IPlugin.activate(self)
		return


	def deactivate(self):
		"""
		Deactivate if activated
		"""
		IPlugin.deactivate(self)


    def print_name(self):
        return "Combinatorial executor"

