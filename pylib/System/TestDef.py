#!/usr/bin/env python3
#
# Copyright (c) 2015-2019 Intel, Inc.  All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#


from builtins import range
from builtins import object
import os
import shutil
import sys
import configparser
import importlib
import logging
import imp
from yapsy.PluginManager import PluginManager
import datetime
from distutils.spawn import find_executable
from threading import Semaphore
from pathlib import Path
import json

is_py2 = sys.version[0] == '2'


# The Test Definition class is mostly a storage construct
# to make it easier when passing values across stages and
# tools.

def _mkdir_recursive(path):
    sub_path = os.path.dirname(path)
    if sub_path and not os.path.exists(sub_path):
        _mkdir_recursive(sub_path)
    if not os.path.exists(path):
        os.mkdir(path)

## @mainpage
# See @ref Stages for details on the stages of test execution.\n
# See @ref Tools for details on the plugins required by Stages.\n
# See @ref Utilities for details on the plugins used by the MTT framework.\n
# @addtogroup Stages
# Stages of test execution
# @addtogroup Tools
# Plugins required by Stages
# @addtogroup Utilities
# Plugins used by the MTT framework
class TestDef(object):
    def __init__(self):
        # set aside storage for options and cmd line args
        self.options = {}
        self.args = []
        # record if we have loaded the plugins or
        # not - this is just a bozo check to ensure
        # someone doesn't tell us to do it twice
        self.loaded = False
        # set aside a spot for a logger object, and
        # note that it hasn't yet been defined
        self.logger = None
        # set aside a spot for the elkLogger object
        self.elkLogger = None
        self.modcmd = None
        # set aside per stage environment module requests
        self.module_unload = {}
        self.module_load = {}
        self.module_swap = {}
        self.execmd = None
        self.harasser = None
        self.config = None
        self.stages = None
        self.tools = None
        self.utilities = None
        self.defaults = None
        self.log = {}
        self.watchdog = None
        self.plugin_trans_sem = Semaphore()
        # provide a signature to differentiate this MTT execution
        # from any other that might be executed in parallel with it
        self.signature = 0
        # define a few global "constant" names that can be used
        # across plugins - the following categories must match
        # their equivalent values in the server. See
        # https://github.com/open-mpi/mtt-legacy/blob/master/lib/MTT/Values.pm#L43-L57
        # for the list
        self.MTT_TEST_FAILED             =   0
        self.MTT_TEST_PASSED             =   1
        self.MTT_TEST_SKIPPED            =   2
        self.MTT_TEST_TIMED_OUT          =   3
        self.MTT_TEST_TIMED_OUT_OR_FAIL  =   4


    def setOptions(self, args):
        self.options = vars(args)
        self.args = args
        self.signature = os.getpid()

    # private function to convert values
    def __convert_value(self, opt, inval):
        if opt is None or type(opt) is str:
            return 0, inval
        elif type(opt) is bool:
            if type(inval) is bool:
                return 0, inval
            elif type(inval) is str:
                if inval.lower() in ['true', '1', 't', 'y', 'yes']:
                    return 0, True
                else:
                    return 0, False
            elif type(inval) is int:
                if 0 == inval:
                    return 0, False
                else:
                    return 0, True
            elif is_py2 and type(inval) is str:
                if inval.lower() in ['true', '1', 't', 'y', 'yes']:
                    return 0, True
                else:
                    return 0, False
            else:
                # unknown conversion required
                print("Unknown conversion required for " + inval)
                return 1, None
        elif type(opt) is int:
            if type(inval) is int:
                return 0, inval
            elif type(inval) is str:
                return 0, int(inval)
            else:
                # unknown conversion required
                print("Unknown conversion required for " + inval)
                return 1, None
        elif type(opt) is float:
            if type(inval) is float:
                return 0, inval
            elif type(inval) is str or type(inval) is int:
                return 0, float(inval)
            else:
                # unknown conversion required
                print("Unknown conversion required for " + inval)
                return 1, None
        else:
            return 1, None

    # scan the key-value pairs obtained from the configuration
    # parser and compare them with the options defined for a
    # given plugin. Generate an output dictionary that contains
    # the updated set of option values, the default value for
    # any option that wasn't included in the configuration file,
    # and return an error status plus output identifying any
    # keys in the configuration file that are not supported
    # by the list of options
    #
    # @log [INPUT]
    #          - a dictionary that will return the status plus
    #            stderr containing strings identifying any
    #            provided keyvals that don't have a corresponding
    #            supported option
    # @options [INPUT]
    #          - a dictionary of tuples, each consisting of three
    #            entries:
    #               (a) the default value
    #               (b) data type
    #               (c) a help-like description
    # @keyvals [INPUT]
    #          - a dictionary of key-value pairs obtained from
    #            the configuration parser
    # @target [OUTPUT]
    #          - the resulting dictionary of key-value pairs
    def parseOptions(self, log, options, keyvals, target):
        # parse the incoming keyvals dictionary against the source
        # options. If a source option isn't provided, then
        # copy it across to the target.
        opts = list(options.keys())
        kvkeys = list(keyvals.keys())
        for opt in opts:
            found = False
            for kvkey in kvkeys:
                if kvkey == opt:
                    # they provided us with an update, so
                    # pass this value into the target - expand
                    # any provided lists
                    if keyvals[kvkey] is None:
                        continue
                    st, outval = self.__convert_value(options[opt][0], keyvals[kvkey])
                    if 0 == st:
                        target[opt] = outval
                    else:
                        if len(keyvals[kvkey]) == 0:
                            # this indicates they do not want this option
                            found = True
                            break
                        if keyvals[kvkey][0][0] == "[":
                            # they provided a list - remove the brackets
                            val = keyvals[kvkey].replace('[','')
                            val = val.replace(']','')
                            # split the input to pickup sets of options
                            newvals = list(val)
                            # convert the values to specified type
                            i=0
                            for val in newvals:
                                st, newvals[i] = self.__convert_value(opt[0], val)
                                i = i + 1
                            target[opt] = newvals
                        else:
                            st, target[opt] = self.__convert_value(opt[0], keyvals[kvkey])
                    found = True
                    break
            if not found:
                # they didn't provide this one, so
                # transfer only the value across
                target[opt] = options[opt][0]
        # add in any default settings that have not
        # been overridden - anything set by this input
        # stage will override the default
        if self.defaults is not None:
            keys = list(self.defaults.options.keys())
            for key in keys:
                if key not in target:
                    target[key] = self.defaults.options[key][0]

        # now go thru in the reverse direction to see
        # if any keyvals they provided aren't supported
        # as this would be an error
        unsupported_options = []
        for kvkey in kvkeys:
            # ignore some standard keys
            if kvkey in ['section', 'plugin']:
                continue
            try:
                if target[kvkey] is not None:
                    pass
            except KeyError:
                # some always need to be passed
                if kvkey in ['parent', 'asis']:
                    target[kvkey] = keyvals[kvkey]
                else:
                    unsupported_options.append(kvkey)
        if unsupported_options:
            sys.exit("ERROR: Unsupported options for section [%s]: %s" % (log['section'], ",".join(unsupported_options)))

        log['status'] = 0
        log['options'] = target
        return

    def loadPlugins(self, basedir, topdir):
        if self.loaded:
            print("Cannot load plugins multiple times")
            sys.exit(1)
        self.loaded = True

        # find the loader utility so we can bootstrap ourselves
        try:
            m = imp.load_source("LoadClasses", os.path.join(basedir, "LoadClasses.py"));
        except ImportError:
            print("ERROR: unable to load LoadClasses that must contain the class loader object")
            sys.exit(1)
        cls = getattr(m, "LoadClasses")
        a = cls()
        # setup the loader object
        self.loader = a.__class__();

        # Setup the array of directories we will search for plugins
        # Note that we always look at the topdir location by default
        plugindirs = []
        plugindirs.append(topdir)
        if self.options['plugindir']:
            # could be a comma-delimited list, so split on commas
            x = self.options['plugindir'].split(',')
            for y in x:
                # prepend so we always look at the given
                # location first in case the user wants
                # to "overload/replace" a default MTT
                # class definition
                plugindirs.insert(0, y)

        # Load plugins from each of the specified plugin dirs
        for dirPath in plugindirs:
            if not Path(dirPath).exists():
                print("Attempted to load plugins from non-existent path:", dirPath)
                continue
            try:
                self.loader.load(dirPath)
            except Exception as e:
                print("Exception caught while loading plugins:")
                print(e)
                sys.exit(1)

        # Build plugin managers,
        # class yapsy.PluginManager.PluginManager(categories_filter=None,
        #           directories_list=None, plugin_info_ext=None, plugin_locator=None)

        # Build the stages plugin manager
        self.stages = PluginManager(None, plugindirs, None, None)
        # Get a list of all the categories - this corresponds to
        # the MTT stages that have been defined. Note that we
        # don't need to formally define the stages here - anyone
        # can add a new stage, or delete an old one, by simply
        # adding or removing a plugin directory.
        self.stages.setCategoriesFilter(self.loader.stages)
        # Load all plugins we find there
        self.stages.collectPlugins()

        # Build the tools plugin manager - tools differ from sections
        # in that they are plugins we will use to execute the various
        # sections. For example, the TestRun section clearly needs the
        # ability to launch jobs. There are many ways to launch jobs
        # depending on the environment, and sometimes several ways to
        # start jobs even within one environment (e.g., mpirun vs
        # direct launch).
        self.tools = PluginManager(None, plugindirs, None, None)
        # Get the list of tools - not every tool will be capable
        # of executing. For example, a tool that supports direct launch
        # against a specific resource manager cannot be used on a
        # system being managed by a different RM.
        self.tools.setCategoriesFilter(self.loader.tools)
        # Load all the tool plugins
        self.tools.collectPlugins()
        # Tool plugins are required to provide a function we can
        # probe to determine if they are capable of operating - check
        # those now and prune those tools that cannot support this
        # environment

        # Build the utilities plugins
        self.utilities = PluginManager(None, plugindirs, None, None)
        # Get the list of available utilities.
        self.utilities.setCategoriesFilter(self.loader.utilities)
        # Load all the utility plugins
        self.utilities.collectPlugins()

        # since we use these all over the place, find the
        # ExecuteCmd and ModuleCmd plugins and record them
        availUtil = list(self.loader.utilities.keys())
        for util in availUtil:
            for pluginInfo in self.utilities.getPluginsOfCategory(util):
                if "ExecuteCmd" == pluginInfo.plugin_object.print_name():
                    self.execmd = pluginInfo.plugin_object
                elif "ModuleCmd" == pluginInfo.plugin_object.print_name():
                    self.modcmd = pluginInfo.plugin_object
                    # initialize this module
                    self.modcmd.setCommand(self.options)
                elif "Watchdog" == pluginInfo.plugin_object.print_name():
                    self.watchdog = pluginInfo.plugin_object
                if self.execmd is not None and self.modcmd is not None and self.watchdog is not None:
                    break
        if self.execmd is None:
            print("ExecuteCmd plugin was not found")
            print("This is a basic capability required")
            print("for MTT operations - cannot continue")
            sys.exit(1)
        # Configure harasser plugin
        for pluginInfo in self.tools.getPluginsOfCategory("Harasser"):
            if "Harasser" == pluginInfo.plugin_object.print_name():
                self.harasser = pluginInfo.plugin_object
                break
        if self.harasser is None:
            print("Harasser plugin was not found")
            print("This is required for all TestRun plugins")
            print("cannot continue")
            sys.exit(1)
        # similarly, capture the highest priority defaults stage here
        pri = -1
        for pluginInfo in self.stages.getPluginsOfCategory("MTTDefaults"):
            if pri < pluginInfo.plugin_object.priority():
                self.defaults = pluginInfo.plugin_object
                pri = pluginInfo.plugin_object.priority()

        return

    def printInfo(self):
        # Print the available MTT sections out, if requested
        if self.options['listsections']:
            print("Supported MTT stages:")
            # print them in the default order of execution
            for stage in self.loader.stageOrder:
                print("    " + stage)
            sys.exit(0)

        # Print the detected plugins for a given stage
        if self.options['listplugins']:
            # if the list is '*', print the plugins for every stage
            if self.options['listplugins'] == "*":
                sections = self.loader.stageOrder
            else:
                sections = self.options['listplugins'].split(',')
            print()
            for section in sections:
                print(section + ":")
                try:
                    for pluginInfo in self.stages.getPluginsOfCategory(section):
                        print("    " + pluginInfo.plugin_object.print_name())
                except KeyError:
                    print("    Invalid stage name " + section)
                print()
            sys.exit(1)

        # Print the options for a given plugin
        if self.options['liststageoptions']:
            # if the list is '*', print the options for every stage/plugin
            if self.options['liststageoptions'] == "*":
                sections = self.loader.stageOrder
            else:
                sections = self.options['liststageoptions'].split(',')
            print()
            for section in sections:
                print(section + ":")
                try:
                    for pluginInfo in self.stages.getPluginsOfCategory(section):
                        print("    " + pluginInfo.plugin_object.print_name() + ":")
                        pluginInfo.plugin_object.print_options(self, "        ")
                except KeyError:
                    print("    Invalid stage name " + section)
                print()
            sys.exit(1)

        # Print the available MTT tools out, if requested
        if self.options['listtools']:
            print("Available MTT tools:")
            availTools = list(self.loader.tools.keys())
            for tool in availTools:
                print("    " + tool)
            sys.exit(0)

        # Print the detected tool plugins for a given tool type
        if self.options['listtoolmodules']:
            # if the list is '*', print the plugins for every type
            if self.options['listtoolmodules'] == "*":
                print()
                availTools = list(self.loader.tools.keys())
            else:
                availTools = self.options['listtoolmodules'].split(',')
            print()
            for tool in availTools:
                print(tool + ":")
                try:
                    for pluginInfo in self.tools.getPluginsOfCategory(tool):
                        print("    " + pluginInfo.plugin_object.print_name())
                except KeyError:
                    print("    Invalid tool type name",tool)
                print()
            sys.exit(1)

        # Print the options for a given plugin
        if self.options['listtooloptions']:
            # if the list is '*', print the options for every stage/plugin
            if self.options['listtooloptions'] == "*":
                availTools = list(self.loader.tools.keys())
            else:
                availTools = self.options['listtooloptions'].split(',')
            print()
            for tool in availTools:
                print(tool + ":")
                try:
                    for pluginInfo in self.tools.getPluginsOfCategory(tool):
                        print("    " + pluginInfo.plugin_object.print_name() + ":")
                        pluginInfo.plugin_object.print_options(self, "        ")
                except KeyError:
                    print("    Invalid tool type name " + tool)
                print()
            sys.exit(1)

        # Print the available MTT utilities out, if requested
        if self.options['listutils']:
            print("Available MTT utilities:")
            availUtils = list(self.loader.utilities.keys())
            for util in availUtils:
                print("    " + util)
            sys.exit(0)

        # Print the detected utility plugins for a given tool type
        if self.options['listutilmodules']:
            # if the list is '*', print the plugins for every type
            if self.options['listutilmodules'] == "*":
                print()
                availUtils = list(self.loader.utilities.keys())
            else:
                availUtils = self.options['listutilitymodules'].split(',')
            print()
            for util in availUtils:
                print(util + ":")
                try:
                    for pluginInfo in self.utilities.getPluginsOfCategory(util):
                        print("    " + pluginInfo.plugin_object.print_name())
                except KeyError:
                    print("    Invalid utility type name")
                print()
            sys.exit(1)

        # Print the options for a given plugin
        if self.options['listutiloptions']:
            # if the list is '*', print the options for every stage/plugin
            if self.options['listutiloptions'] == "*":
                availUtils = list(self.loader.utilities.keys())
            else:
                availUtils = self.options['listutiloptions'].split(',')
            print()
            for util in availUtils:
                print(util + ":")
                try:
                    for pluginInfo in self.utilities.getPluginsOfCategory(util):
                        print("    " + pluginInfo.plugin_object.print_name() + ":")
                        pluginInfo.plugin_object.print_options(self, "        ")
                except KeyError:
                    print("    Invalid utility type name " + util)
                print()
            sys.exit(1)


        # if they asked for the version info, print it and exit
        if self.options['version']:
            for pluginInfo in self.tools.getPluginsOfCategory("Version"):
                print("MTT Base:   " + pluginInfo.plugin_object.getVersion())
                print("MTT Client: " + pluginInfo.plugin_object.getClientVersion())
            sys.exit(0)

    def openLogger(self):
        # there must be a logger utility or we can't do
        # anything useful
        if not self.utilities.activatePluginByName("Logger", "Base"):
            print("Required Logger plugin not found or could not be activated")
            sys.exit(1)
        # execute the provided test description
        self.logger = self.utilities.getPluginByName("Logger", "Base").plugin_object
        self.logger.open(self)
        return

    def openElkLogger(self):
        if not self.utilities.activatePluginByName("ElkLogger", "Base"):
            self.elkLogger = None
        else:
            self.elkLogger = self.utilities.getPluginByName("ElkLogger", "Base").plugin_object

    def fill_log_interpolation(self, basestr, sublog):
        if isinstance(sublog, str):
            self.config.set("LOG", basestr, sublog.replace("$","$$"))
        elif isinstance(sublog, dict):
            self.fill_log_interpolation(basestr, str(json.dumps(sublog, default=str)))
            self.fill_log_interpolation("%s.keys" % basestr, list(sublog.keys()))
            for k,v in list(sublog.items()):
                self.fill_log_interpolation("%s.%s" % (basestr, k), v)
        elif isinstance(sublog, list):
            if sum([((isinstance(t, list) or isinstance(t, tuple)) and len(t) == 2) for t in sublog]) == len(sublog) and len(sublog) > 0:
                self.fill_log_interpolation(basestr, {k:v for k,v in sublog})
            else:
                self.fill_log_interpolation(basestr, str(json.dumps(sublog, default=str)))
                self.fill_log_interpolation("%s.length" % basestr, str(len(sublog)))
                self.fill_log_interpolation("%s.size" % basestr, str(len(sublog)))
                for i,v in enumerate(sublog):
                    self.fill_log_interpolation("%s.%d" % (basestr, i), v)
        else:
            # sublog is likely a byte array that might included non-ascii
            # characters, so protect us in case of an exception
            try:
                self.fill_log_interpolation(basestr, str(sublog))
            except:
                try:
                    mystring = sublog.encode('utf-8')
                    self.fill_log_interpolation(basestr, str(mystring))
                except:
                    # replace illegal characters with an asterisk
                    for i,b in enumerate(sublog):
                       if not isascii(b):
                          sublog[i] = '*'
                    self.fill_log_interpolation(basestr, str(sublog))

    def expandWildCards(self, sections):
        expsec = []
        cpsections = list(sections)
        for sec in cpsections:
            if '*' in sec:
                modsec = sec.split('*')
                startswith = modsec[0]
                endswith = modsec[-1]
                findsec = modsec[1:-1]
                allsections = self.config.sections()
                for s in allsections:
                    if not s.startswith(startswith):
                        continue
                    if not s.endswith(endswith):
                        continue
                    found = True
                    s_tmp = s
                    for f in findsec:
                        if not f in s_tmp:
                            found = False
                            break
                        s_tmp = f.join(s_tmp.split(f)[1:])
                    if not found:
                        continue
                    expsec.append(s)
                sections.remove(sec)
        return sections + expsec

    def fill_env_hidden_section(self):
        """fill ENV section with environment variables
        """
        try:
            self.config.add_section('ENV')
        except configparser.DuplicateSectionError:
            pass
        for k,v in list(os.environ.items()):
            self.config.set('ENV', k, v.replace("$","$$"))

    def fill_log_hidden_section(self):
        """Add LOG section filled with log results of stages
        """
        try:
            self.config.add_section('LOG')
        except configparser.DuplicateSectionError:
            pass
        thefulllog = self.logger.getLog(None)
        for e in thefulllog:
            self.fill_log_interpolation(e['section'].replace(":","_"), e)

    def check_for_nondefined_env_variables(self):
        # Check for ENV input
        required_env = []
        all_file_contents = []
        for testFile in self.log['inifiles']:
            file_contents = open(testFile, "r").read()
            file_contents = "\n".join(["%s %d: %s" % (testFile.split("/")[-1],i,l) for i,l in enumerate(file_contents.split("\n")) if not l.lstrip().startswith("#")])
            all_file_contents.append(file_contents)
            if "${ENV:" in file_contents:
                required_env.extend([s.split("}")[0] for s in file_contents.split("${ENV:")[1:]])
        env_not_found = set([e for e in required_env if e not in list(os.environ.keys())])
        lines_with_env_not_found = []
        for file_contents in all_file_contents:
            lines_with_env_not_found.extend(["%s: %s"%(",".join([e for e in env_not_found if "${ENV:%s}"%e in l]),l) \
                                             for l in file_contents.split("\n") \
                                             if sum(["${ENV:%s}"%e in l for e in env_not_found])])
        if lines_with_env_not_found:
            print("ERROR: Not all required environment variables are defined.")
            print("ERROR: Still need:")
            for l in lines_with_env_not_found:
                print("ERROR: %s"%l)
            sys.exit(1)

    def configTest(self):

        # setup the configuration parser
        self.config = configparser.SafeConfigParser(interpolation=configparser.ExtendedInterpolation())

        # Set the config parser to make option names case sensitive.
        self.config.optionxform = str

        # fill ENV section with environemt variables
        self.fill_env_hidden_section()

        # log the list of files - note that the argument parser
        # puts the input files in a list, with the first member
        # being the list of input files
        self.log['inifiles'] = self.args.ini_files[0]
        # initialize the list of active sections
        self.actives = []
        # if they specified a list to execute, then use it
        sections = []
        if self.args.section:
            sections = self.args.section.split(",")
            skip = False
        elif self.args.skipsections:
            sections = self.args.skipsections.split(",")
            skip = True
        else:
            sections = None
        # cycle thru the input files
        for testFile in self.log['inifiles']:
            if not os.path.isfile(testFile):
                print("Test description file",testFile,"not found!")
                sys.exit(1)
            self.config.read(self.log['inifiles'])

        # Check for ENV input
        self.check_for_nondefined_env_variables()

        # find all the sections that match the wild card and expand them
        # this is simple wild carding, ie *text, text*, *text* and *
        # should all work
        if sections is not None:
            sections = self.expandWildCards(sections)

        #if sections is not None:
        #    expsec = []
        #    cpsections = list(sections)
        #    for sec in cpsections:
        #        if '*' in sec:
        #            modsec = sec.replace('*','')
        #            for s in self.config.sections():
        #                if modsec in s:
        #                    expsec.append(s)
        #            sections.remove(sec)
        #    sections = sections + expsec

        for section in self.config.sections():
            if section.startswith("SKIP") or section.startswith("skip"):
                # users often want to temporarily ignore a section
                # of their test definition file, but don't want to
                # remove it lest they forget what it did. So let
                # them just mark the section as "skip" to be ignored
                continue
            # if we are to filter the sections, then do so
            takeus = True
            if sections is not None:
                found = False
                for sec in sections:
                    if sec == section:
                        found = True
                        sections.remove(sec)
                        if skip:
                            takeus = False
                        break
                if not found and not skip:
                    takeus = False
            if takeus:
                self.actives.append(section)

        if sections is not None and 0 != len(sections) and not skip:
            print("ERROR: sections were specified for execution and not found:",sections)
            sys.exit(1)

        # set Defaults -command line args supercede .ini args
        try:
            if not self.options['scratchdir']:
                self.options['scratchdir'] = self.config.get('MTTDefaults', 'scratchdir')
        except:
            try:
                self.options['scratchdir'] = self.config.get('MTTDefaults', 'scratch')
            except:
                self.options['scratchdir'] = os.path.abspath('./mttscratch')
        self.options['scratchdir'] = os.path.abspath(self.options['scratchdir'])
        try:
            if not self.options['executor']:
                self.options['executor'] = self.config.get('MTTDefaults', 'executor')
        except:
            self.options['executor'] = 'sequential'
        # if they want us to clear the scratch, then do so
        if self.options['clean'] and os.path.isdir(self.options['scratchdir']) :
            shutil.rmtree(self.options['scratchdir'])
        # setup the scratch directory
        _mkdir_recursive(self.options['scratchdir'])
        return

    # Used with combinatorial executor, loads next .ini file to be run with the
    # sequential executor
    def configNewTest(self, file):
        # clear the configuration parser
        for section in self.config.sections():
            self.config.remove_section(section)
        # read in the file
        self.config.read(file)
        for section in self.config.sections():
            if section.startswith("SKIP") or section.startswith("skip"):
                # users often want to temporarily ignore a section
                # of their test definition file, but don't want to
                # remove it lest they forget what it did. So let
                # them just mark the section as "skip" to be ignored
                continue
            if self.logger is not None:
                self.logger.verbose_print("SECTION: " + section)
                self.logger.verbose_print(self.config.items(section))
        return

    def executeTest(self, executor="sequential"):
        self.logger.print_cmdline_args(self)

        if not self.loaded:
            print("Plugins have not been loaded - cannot execute test")
            sys.exit(1)
        if self.config is None:
            print("No test definition file was parsed - cannot execute test")
            sys.exit(1)
        if not self.tools.getPluginByName(executor, "Executor"):
            print("Specified executor %s not found" % executor)
            sys.exit(1)
        # activate the specified plugin
        self.tools.activatePluginByName(executor, "Executor")
        # execute the provided test description
        executor = self.tools.getPluginByName(executor, "Executor")
        status = executor.plugin_object.execute(self)
        if status == 0 and self.options['clean_after'] and os.path.isdir(self.options['scratchdir']):
            self.logger.verbose_print("Cleaning up scratchdir after successful run")
            shutil.rmtree(self.options['scratchdir'])
        return status

    def printOptions(self, options):
        # if the options are empty, report that
        if not options:
            lines = ["None"]
            return lines
        # create the list of options
        opts = []
        vals = list(options.keys())
        for val in vals:
            opts.append(val)
            if options[val][0] is None:
                opts.append("None")
            elif isinstance(options[val][0], bool):
                if options[val][0]:
                    opts.append("True")
                else:
                    opts.append("False")
            elif isinstance(options[val][0], list):
                opts.append(" ".join(options[val][0]))
            elif isinstance(options[val][0], int):
                opts.append(str(options[val][0]))
            else:
                opts.append(options[val][0])
            opts.append(options[val][1])
        # print the options, their default value, and
        # the help description in 3 column format
        max1 = 0
        max2 = 0
        for i in range(0,len(opts),3):
            # we want all the columns to line up
            # and left-justify, so first find out
            # the max len of each of the first two
            # column entries
            if len(opts[i]) > max1:
                max1 = len(opts[i])
            if type(opts[i+1]) is not str:
                optout = str(opts[i+1])
            else:
                optout = opts[i+1]
            if len(optout) > max2:
                max2 = len(optout)
        # provide some spacing
        max1 = max1 + 4
        max2 = max2 + 4
        # cycle thru again, padding each entry to
        # align the columns
        lines = []
        sp = " "
        for i in range(0,len(opts),3):
            line = opts[i] + (max1-len(opts[i]))*sp
            if type(opts[i+1]) is not str:
                optout = str(opts[i+1])
            else:
                optout = opts[i+1]
            line = line + optout + (max2-len(optout))*sp
            # to make this more readable, we will wrap the line at
            # 130 characters. First, see if the line is going to be
            # too long
            if 130 < (len(line) + len(opts[i+2])):
                # split the remaining column into individual words
                words = opts[i+2].split()
                first = True
                for word in words:
                    if (len(line) + len(word)) < 130:
                        if first:
                            line = line + word
                            first = False
                        else:
                            line = line + " " + word
                    else:
                        lines.append(line)
                        line = (max1 + max2)*sp + word
                if 0 < len(line):
                    lines.append(line)
            else:
                # the line is fine - so just add the last piece
                line = line + opts[i+2]
                # append the result
                lines.append(line)
        # add one blank line
        lines.append("")
        return lines


    def selectPlugin(self, name, category):
        if category == "stage":
            try:
                availStages = list(self.loader.stages.keys())
                for stage in availStages:
                    for pluginInfo in self.stages.getPluginsOfCategory(stage):
                        if name == pluginInfo.plugin_object.print_name():
                            return pluginInfo.plugin_object
                # didn't find it
                return None
            except:
                return None
        elif category == "tool":
            try:
                availTools = list(self.loader.tools.keys())
                for tool in availTools:
                    for pluginInfo in self.tools.getPluginsOfCategory(tool):
                        if name == pluginInfo.plugin_object.print_name():
                            return pluginInfo.plugin_object
                # didn't find it
                return None
            except:
                return None
        elif category == "utility":
            try:
                availUtils = list(self.loader.utilities.keys())
                for util in availUtils:
                    for pluginInfo in self.utilities.getPluginsOfCategory(util):
                        if name == pluginInfo.plugin_object.print_name():
                            return pluginInfo.plugin_object
                # didn't find it
                return None
            except:
                return None
        else:
            print("Unrecognized category:",category)
            return None
