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
from future import standard_library
standard_library.install_aliases()
import os
import sys
import configparser
import importlib
import logging
import imp
import datetime
import tempfile
import shutil
from yapsy.PluginManager import PluginManager

from ExecutorMTTTool import *

## @addtogroup Tools
# @{
# @addtogroup Executor
# @section CombinatorialEx
# @}
class CombinatorialEx(ExecutorMTTTool):

    def __init__(self):
        # initialise parent class
        ExecutorMTTTool.__init__(self)
        self.options = {}
        self.parser = configparser.ConfigParser()
        self.parser.optionxform = str
        # Create temp directory to hold .ini files
        self.tempDir = tempfile.mkdtemp()
        self.baseIniFile = None
        self.runLog = {}
        self.iniLog = {}

    def activate(self):
        # use the automatic procedure from IPlugin
        IPlugin.activate(self)
        return

    def deactivate(self):
        IPlugin.deactivate(self)
        return

    def print_name(self):
        return "Combinatorial executor"

    def print_options(self, testDef, prefix):
        lines = testDef.printOptions(self.options)
        for line in lines:
            print(prefix + line)
        return


    # Create .ini files for each combination to be run
    # BaseIniFile created by TestDef ConfigTest()
    def createIniLog(self, testDef):
        self.baseIniFile = testDef.config
        tempSpecialSection = {}
        # configParser object to write individual options to files
        writeOption = configparser.ConfigParser()
        writeOption.optionxform = str
        # Sort base .ini sections and write to temp files 
        for section in self.baseIniFile.sections():
            if section == "ENV":
                continue
            if section.startswith("SKIP") or section.startswith("skip"):
                # users often want to temporarily ignore a section
                # of their test definition file, but don't want to
                # remove it lest they forget what it did. So let
                # them just mark the section as "skip" to be ignored
                continue
            self.parser.add_section(section)
            for option in self.baseIniFile.options(section):
                self.parser.set(section, option, self.baseIniFile.get(section, option))
            # TODO: FIX Getting temp file in tmp dir that is not being removed
            fd, fileName = tempfile.mkstemp(suffix=".ini", dir = self.tempDir)
            with open(fileName, 'w') as configfile:
                self.parser.write(configfile)
            # Clear out parser for next section
            self.parser.remove_section(section)
            if "MiddlewareGet" in section:
                self.runLog[section] = fileName
            elif "TestRun" in section:
                tempSpecialSection[section] = fileName
            else:
                self.iniLog[section] = fileName
        # Combine TestRun and MiddlewareGet files
        tempList = {}
        for section in self.runLog:
            self.parser.read(self.runLog[section])
            for id in tempSpecialSection:
                self.parser.read(tempSpecialSection[id])
                fd, fileName = tempfile.mkstemp(suffix = ".ini", dir = self.tempDir)
                with open(fileName, 'w') as configfile:
                    self.parser.write(configfile)
                self.parser.remove_section(id)
                tempList[fd] = fileName
            self.parser.remove_section(section)
        self.runLog.clear()
        self.runLog = tempList
        # Sort sections for comma separated values to be parsed
        optionsCSV = {}
        for section in self.iniLog:
            writeOption.read(self.iniLog[section])
            for option in writeOption.options(section):
                if ',' in writeOption.get(section, option):
                    try:
                        if optionsCSV[section] is not None:
                            pass
                    except KeyError:
                        optionsCSV[section] = []
                    optionsCSV[section].append(option)
                else:
                    # write option to base run files
                    for fd in self.runLog:
                        # set up parser to write to each file
                        self.parser.read(self.runLog[fd])
                        if not self.parser.has_section(section):
                            self.parser.add_section(section)
                        self.parser.set(section, option, writeOption.get(section, option))
                        # Want to overwrite file with new parser contents
                        with open(self.runLog[fd], 'w') as configfile:
                            self.parser.write(configfile)
                        # clear parser for next file
                        for sect in self.parser.sections():
                            self.parser.remove_section(sect)       
            writeOption.remove_section(section)
        # Process CSV options
        for section in optionsCSV:
            self.parser.read(self.iniLog[section])
            for option in optionsCSV[section]:
                # Get clean list of CSV's
                rawList = self.parser.get(section, option)
                splitList = rawList.split(',')
                optionList = []
                for item in splitList:
                    optionList.append(item.strip())
                newList = {}
                for fd in self.runLog:
                    writeOption.read(self.runLog[fd])
                    for nextOpt in optionList:
                        try:
                            if writeOption.has_section(section):
                                pass
                        except KeyError:
                            writeOption.add_section(section)
                        writeOption.set(section, option, nextOpt)
                        fd, fileName = tempfile.mkstemp(suffix=".ini", dir = self.tempDir)
                        with open(fileName, 'w') as configfile:
                            writeOption.write(configfile)
                        newList[fd] = fileName
                    for sect in writeOption.sections():
                        writeOption.remove_section(sect)
                # Update runLog for next pass
                self.runLog.clear()
                self.runLog = newList
            self.parser.remove_section(section)

    def execute(self, testDef):
        testDef.logger.verbose_print("ExecuteCombinatorial")
        self.createIniLog(testDef)
        try:
            if not self.runLog:
                print("Error, empty run log, combinatorial executor failed")
                sys.exit(1)
            for nextFile in self.runLog:
                if not os.path.isfile(self.runLog[nextFile]):
                    print("Test .ini file not found!: " + nextFile)
                    sys.exit(1)
                testDef.configNewTest(self.runLog[nextFile])
                testDef.executeTest()
            # clean up temporary files
        finally:
            shutil.rmtree(self.tempDir)
        
            
