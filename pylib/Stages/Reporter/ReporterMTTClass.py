#!/usr/bin/env python

from yapsy.IPlugin import IPlugin

class ReporterMTTClass(IPlugin):
    def __init__(self):
        # initialise parent class
        IPlugin.__init__(self)
    def print_name(self):
        print "Report test results plugin"

