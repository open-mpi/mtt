# -*- coding: utf-8; tab-width: 4; indent-tabs-mode: f; python-indent: 4 -*-
#
# Copyright (c) 2015      Intel, Inc. All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

import os
import sys
import ConfigParser
import importlib
import logging
import imp
import datetime
from optparse import OptionParser, OptionGroup

from ExecutorMTTTool import *

class SequentialEx(ExecutorMTTTool):

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
		return

    def print_name(self):
        return "Sequential executor"

    def execute(self, options, sections={}, tools={}):
		return
