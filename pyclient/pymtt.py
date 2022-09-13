#!/usr/bin/env python3
#
# Copyright (c) 2015-2018 Intel, Inc. All rights reserved.
# Copyright (c) 2018 Cisco Systems, Inc. All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#


import os
import sys
import configparser
import importlib
import logging
from yapsy.PluginManager import PluginManager
import argparse
import shlex

def load_source(name, path):
    module_spec = importlib.util.spec_from_file_location(
        name, path
    )
    module = importlib.util.module_from_spec(module_spec)
    module_spec.loader.exec_module(module)
    return module

# First check for bozo error - we need to be given
# at least a cmd line option, so no params at all
# sounds like a plea for "help"
#if 1 == len(sys.argv):
#    sys.exit('MTT usage error: add -h for help')

# define the cmd line arguments
parser = argparse.ArgumentParser(
    formatter_class=argparse.RawDescriptionHelpFormatter,
    description='''\
Environment Variables:
  MTT_HOME - this must be set to the top-level directory of your MTT installation.
  MTT_ARGS - list of commandline arguments that you want set for each invocation.
    Example: export MTT_ARGS="--verbose --log=/tmp/out.log"
''')

parser.add_argument('ini_files', action='append', metavar='FILE', nargs='*', help = ".ini file to be used")

infoGroup = parser.add_argument_group('InfoGroup','Informational Options')
infoGroup.add_argument("-v", "--version",
                     action="store_true", dest="version", default=False,
                     help="Print version")
infoGroup.add_argument("--list-stages",
                     action="store_true", dest="listsections", default=False,
                     help="List section names understood by this client")
infoGroup.add_argument("--list-stage-plugins",
                     action="store", dest="listplugins", metavar="STAGE",
                     help="List available plugins for SECTION (* => all)")
infoGroup.add_argument("--list-stage-options",
                     action="store", dest="liststageoptions", metavar="STAGE",
                     help="List available options for STAGE (* => all)")
infoGroup.add_argument("--list-tools",
                     action="store_true", dest="listtools", default=False,
                     help="List tools available to this client")
infoGroup.add_argument("--list-tool-plugins",
                     action="store", dest="listtoolmodules", metavar="TYPE",
                     help="List available modules for TYPE (* => all)")
infoGroup.add_argument("--list-tool-options",
                     action="store", dest="listtooloptions", metavar="TOOL",
                     help="List available options for TOOL (* => all)")
infoGroup.add_argument("--list-utilities",
                     action="store_true", dest="listutils", default=False,
                     help="List utilities available to this client")
infoGroup.add_argument("--list-utility-plugins",
                     action="store", dest="listutilmodules", metavar="TYPE",
                     help="List available modules for TYPE (* => all)")
infoGroup.add_argument("--list-utility-options",
                     action="store", dest="listutiloptions", metavar="UTILITY",
                     help="List available options for UTILITY (* => all)")

execGroup = parser.add_argument_group('execGroup', "Execution Options")
execGroup.add_argument("--description", dest="description",
                     help="Provide a brief title/description to be included in the log for this test")
execGroup.add_argument("-e", "--executor", dest="executor",
                     help="Use the specified execution STRATEGY module", metavar="STRATEGY")
execGroup.add_argument("--base-dir", dest="basedir",
                     help="Specify the DIRECTORY where we can find the TestDef class (checks DIRECTORY, DIRECTORY/Utilities, and DIRECTORY/pylib/Utilities locations) - also serves as default plugin-dir", metavar="DIRECTORY")
execGroup.add_argument("--plugin-dir", dest="plugindir",
                     help="Specify the DIRECTORY where additional plugins can be found (or comma-delimited list of DIRECTORYs)", metavar="DIRECTORY")
execGroup.add_argument("--ignore-loadpath-errors", action="store_true", dest="ignoreloadpatherrs", default=False,
                     help="Ignore errors in plugin paths")
execGroup.add_argument("--scratch-dir", dest="scratchdir", default=None,
                     help="Specify the DIRECTORY under which scratch files are to be stored", metavar="DIRECTORY")
execGroup.add_argument("--print-section-time", dest="sectime",
                      action="store_true", default=True,
                      help="Display section timestamps and execution time")
execGroup.add_argument("--print-cmd-time", dest="cmdtime",
                     action="store_true", default=False,
                     help="Display stdout/stderr timestamps and cmd execution time")
execGroup.add_argument("--timestamp", dest="time",
                     action="store_true", default=False,
                     help="Alias for --print-section-time --print-cmd-time")
execGroup.add_argument("--clean-start", dest="clean",
                     action="store_true",
                     help="Clean the scratch directory from past MTT invocations before running")
execGroup.add_argument("-c", "--cleanup", dest="clean_after",
                     action="store_true",
                     help="Clean the scratch directory after a successful run")
execGroup.add_argument("-s", "--sections", dest="section",
                     help="Execute the specified SECTION (or comma-delimited list of SECTIONs)", metavar="SECTION")
execGroup.add_argument("--skip-sections", dest="skipsections",
                     help="Skip the specified SECTION (or comma-delimited list of SECTIONs)", metavar="SECTION")
execGroup.add_argument("-l", "--log", dest="logfile", default=None,
                     help="Log all output to FILE (defaults to stdout)", metavar="FILE")
execGroup.add_argument("--group-results", dest="submit_group_results", default=True,
                     help="Report results from each test section as it is completed")
execGroup.add_argument("--default-make-options", dest="default_make_options", default="-j10",
                     help="Default options when running the \"make\" command")
execGroup.add_argument("--env-module-wrapper", dest="env_module_wrapper", default=None,
                     help="Python environment module wrapper")
execGroup.add_argument("--stop-on-fail", dest="stop_on_fail",
                     action="store_true", default=False,
                     help="If a stage fails, exit and issue a non-zero return code")
execGroup.add_argument("--duration",
                     dest="duration", default=None,
                     help="Add a maximum duration for test before interrupting.")
execGroup.add_argument("--loop",
                     dest="loop", default=None,
                     help="Causes MTT to loop until provided number of seconds finishes")
execGroup.add_argument("--loopforever", dest="loopforever",
                     action="store_true", default=False,
                     help="Causes MTT to continue to loop forever running same set of tests")
execGroup.add_argument("--harass_trigger",
                     dest="harass_trigger_scripts", default=None,
                     help="Paths to scripts that are run to harass the system while the test is running.")
execGroup.add_argument("--harass_stop",
                     dest="harass_stop_scripts", default=None,
                     help="Paths to scripts that are run to stop harassing the system after the test finishes.")
execGroup.add_argument("--harass_join_timeout",
                     dest="harass_join_timeout", default=None,
                     help="Number of seconds to wait while ending harass scripts. Default is infinity.")

debugGroup = parser.add_argument_group('debugGroup', 'Debug Options')
debugGroup.add_argument("-d", "--debug", dest="debug",
                      action="store_true", default=False,
                      help="Output lots of debug messages")
debugGroup.add_argument("--verbose",
                      action="store_true", dest="verbose", default=False,
                      help="Output some status/verbose messages while processing")
debugGroup.add_argument("--extraverbose",
                      action="store_true", dest="extraverbose", default=False,
                      help="Output timestamps with every verbose message")
debugGroup.add_argument("--dryrun",
                      action="store_true", dest="dryrun", default=False,
                      help="Show commands, but do not execute them")
debugGroup.add_argument("--trial",
                      action="store_true", dest="trial", default=None,
                      help="Use when testing your MTT client setup; results that are generated and submitted to the database are marked as \"trials\" and are not included in normal reporting.")

elkGroup = parser.add_argument_group('elkGroup','ELK-friendly output options')
elkGroup.add_argument("--elk_testcase", dest="elk_testcase",
                        default=os.environ['MTT_ELK_TESTCASE'] if 'MTT_ELK_TESTCASE' in os.environ else None,
                        help="Specifies which testcase to log results as when using elk-friendly output. You can also set this through the enviroment variable MTT_ELK_TESTCASE")
elkGroup.add_argument("--elk_testcycle", dest="elk_testcycle",
                        default=os.environ['MTT_ELK_TESTCYCLE'] if 'MTT_ELK_TESTCYCLE' in os.environ else None,
                        help="Specifies which testcycle to log results as when using elk-friendly output. You can also set this through the enviroment variable MTT_ELK_TESTCYCLE")
elkGroup.add_argument("--elk_id", dest="elk_id",
                        default=os.environ['MTT_ELK_ID'] if 'MTT_ELK_ID' in os.environ else None,
                        help="Specifies which execution id to log results as when using elk-friendly output. You can also set this through the enviroment variable MTT_ELK_ID")
elkGroup.add_argument("--elk_head", dest="elk_head",
                        default=os.environ['MTT_ELK_HEAD'] if 'MTT_ELK_HEAD' in os.environ else None,
                        help="Specifies which location to log <caseid>_<elk_id>.elog files for elk-friendly output. You can also set this through the environment variable MTT_ELK_HEAD")
elkGroup.add_argument("--elk_chown", dest="elk_chown",
                        default=os.environ['MTT_ELK_CHOWN'] if 'MTT_ELK_CHOWN' in os.environ else None,
                        help="Specifies what user and group to set for *.elog file permissions. You can also set this through the environment variable MTT_ELK_CHOWN")
elkGroup.add_argument("--elk_maxsize", dest="elk_maxsize",
                        default=os.environ['MTT_ELK_MAXSIZE'] if 'MTT_ELK_MAXSIZE' in os.environ else None,
                        help="Specifies a max number of lines to log for stdout and stderr in elk-friendly output, and otherwise truncate. You can also set this through the environment variable MTT_ELK_MAXSIZE")
elkGroup.add_argument("--elk_nostdout", dest="elk_nostdout", action="store_true",
                        default=True if 'MTT_ELK_NOSTDOUT' in os.environ and os.environ['MTT_ELK_NOSTDOUT'].lower() != 'false' else False,
                        help="Specifies whether to include stdout in elk-friendly output. You can also set this through the environment variable MTT_ELK_NOSTDOUT")
elkGroup.add_argument("--elk_nostderr", dest="elk_nostderr", action="store_true",
                        default=True if 'MTT_ELK_NOSTDERR' in os.environ and os.environ['MTT_ELK_NOSTDERR'].lower() != 'false' else False,
                        help="Specifies whether to include stdout in elk-friendly output. You can also set this through the environment variable MTT_ELK_NOSTDERR")
elkGroup.add_argument("--elk_debug", dest="elk_debug", action="store_true",
                        default=True if 'MTT_ELK_DEBUG' in os.environ and os.environ['MTT_ELK_DEBUG'].lower() != 'false' else False,
                        help="Specifies whether to output everything logged to *.elog files to the screen as extra verbose output. You can also set this through the environment variable MTT_ELK_DEBUG")
elkGroup.add_argument("--elk_hide_execmd", dest="elk_hide_execmd",
                      default=True if 'MTT_ELK_HIDE_EXECID' in os.environ and os.environ['MTT_ELK_HIDE_EXECID'].lower() != 'false' else False,
                      help="Comma delimited list of plugins and/or sections to hide execmd output from. Also set through environment variable MTT_ELK_HIDE_EXECMD. Use \"Default\" to hide execmd output when no plugin is specified.")

args = parser.parse_args()

# get any arguments set in MTT_ARGS environment variable and combine them with
# any set on the command line.  Environment will override the commandline.
mttArgs = []
if 'MTT_ARGS' in os.environ and os.environ.get('MTT_ARGS') != None:
    mttArgs = shlex.split(os.environ['MTT_ARGS'])
    args = parser.parse_args(sys.argv[1:] + mttArgs)

# check to see if MTT_HOME has been set - we require it
try:
    mtthome = os.environ['MTT_HOME']
except KeyError:
    print("MTT_HOME could not be found in your environment")
    print("Python client requires that this be set and point")
    print("to the top-level directory of your MTT installation")
    sys.exit(1)

# check to see if it is an absolute path, as we require
if not os.path.isabs(mtthome):
    print("MTT_HOME environment variable:")
    print("    ", mtthome)
    print("is not an absolute path")
    sys.exit(1)

# check to see if MTT_HOME exists
if not os.path.exists(mtthome):
    print("MTT_HOME points to a non-existent location:")
    print("    ", mtthome)
    print("Please correct")
    sys.exit(1)

# set topdir and check for existence
topdir = os.path.join(mtthome, "pylib")
if not os.path.exists(topdir) or not os.path.isdir(topdir):
    print("MTT_HOME points to a location that does not\ninclude the \"pylib\" subdirectory:")
    print("   ", topdir)
    print("does not exist. Please correct")
    sys.exit(1)

# set basedir and check for existence
if args.basedir and not os.path.isabs(args.basedir):
    print("The basedir cmd line option is not an absolute path:")
    print("   ", args.basedir)
    print("Please correct")
    sys.exit(1)

basedir = args.basedir or os.path.join(mtthome, "pylib", "System")
if not os.path.exists(basedir) or not os.path.isdir(basedir):
    if basedir == args.basedir:
        print("The basedir cmd line option points to a location that does not exist:")
        print("   ", basedir)
        print("Please correct")
    else:
        print("MTT_HOME points to a location that does not\ninclude the \"pylib/System\" subdirectory:")
        print("   ", basedir)
        print("does not exist. Please correct")
    sys.exit(1)

# if they want debug, set the logging level
if (args.debug):
    logging.basicConfig(level=logging.DEBUG)

# load the "testdef" Test Definition class so we can
# begin building this test
try:
    m = load_source("TestDef", os.path.join(basedir, "TestDef.py"))
except Exception:
    print("ERROR: unable to load TestDef that must contain the Test Definition object")
    exit(1)
cls = getattr(m, "TestDef")
a = cls()

# create the Test Definition object and set the
# options and arguments
testDef = a.__class__();
testDef.setOptions(args)

# load the plugins for this test
testDef.loadPlugins(basedir, topdir)

# provide an opportunity to print various requested
# outputs before starting to process the test
testDef.printInfo()

# if they didn't specify any files, then there is nothing
# for us to do
if not args.ini_files or not args.ini_files[0]:
    sys.exit('MTT requires at least one test-specification file')

# sanity check a couple of options
if args.section and args.skipsections:
    print("ERROR: Cannot both execute specific sections and specify sections to be skipped")
    sys.exit(1)

# open the logging file if given - otherwise, we log
# to stdout
testDef.openLogger()

# open the elk logger if given, otherwise don't log to *.elog files
testDef.openElkLogger()

# Read the input test definition file(s)
testDef.configTest()

# Cli specified executor takes precedent over INI
# If there is nothing defined in either use fallback
fallback = "sequential"
executor = args.executor or testDef.config.get('MTTDefaults', 'executor', fallback=fallback)

# Do not verify that executor exists now
# When the executor is loaded it ensures it exists
testDef.config.set('MTTDefaults', 'executor', executor.lower())

status = testDef.executeTest(executor=executor.lower())
sys.exit(status)
