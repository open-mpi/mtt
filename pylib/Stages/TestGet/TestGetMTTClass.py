#!/usr/bin/env python

from yapsy.IPlugin import IPlugin

class TestGetMTTClass(IPlugin):
    def __init__(self):
        # initialise parent class
        IPlugin.__init__(self)
    def print_name(self):
        print "Plugin for getting test source code"

