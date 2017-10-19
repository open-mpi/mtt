#!/usr/bin/env python
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
import sys
import select
import os
from io import StringIO
from BaseMTTUtility import *

## @addtogroup Utilities
# @{
# @section ModuleCmd
# @}
class ModuleCmd(BaseMTTUtility):
    def __init__(self):
        BaseMTTUtility.__init__(self)
        self.env_module_wrapper = None
        self.env_module_link = None
        self.options = {}
        return

    def print_name(self):
        return "ModuleCmd"

    def print_options(self, testDef, prefix):
        lines = testDef.printOptions(self.options)
        for line in lines:
            print(prefix + line)
        return

    def setCommand(self, options):
        # Check first if the --env-module-wrapper switch was used.  If not, then check for the LMOD_PKG environment variable.
        if options['env_module_wrapper'] is not None:
            self.env_module_wrapper = options['env_module_wrapper']
            if not os.path.isfile(self.env_module_wrapper):
                if options['verbose'] or options['debug'] :
                    print("Environment module python wrapper not found: " + self.env_module_wrapper)
                return
        else:
            try:
                mod_pkg = os.environ['MODULESHOME']
                if os.path.isfile(os.path.join(mod_pkg, "init/env_modules_python.py")) :
                   self.env_module_wrapper = os.path.join(mod_pkg, "init/env_modules_python.py")
                elif os.path.isfile(os.path.join(mod_pkg, "init/python.py")) :
                   self.env_module_wrapper = os.path.join(mod_pkg, "init/python.py")
                else:
                   if options['verbose'] or options['debug'] :
                       print("The --env-module-wrapper switch was not used and module python support via os.environ['MODULESHOME']/init/env_modules_python.py was not found")
                   return
            except KeyError:
                if options['verbose'] or options['debug'] :
                    print("The --env-module-wrapper switch was not used and module python support via os.environ['MODULESHOME'] was not found")
                return
        try:
            # scratchdir defaults to mttscratch if not set
            self.env_module_link = os.path.join(options['scratchdir'], "env_modules_python.py")
            if os.path.isfile(self.env_module_link):
                os.remove(self.env_module_link)
            # create a soft link that includes the .py extension; the tcl python module file does not include this
            os.symlink(self.env_module_wrapper, self.env_module_link)
        except:
            print("Unable to link to " + self.env_module_wrapper)
            print("Since we are unable to meet this basic user directive,")
            print("we will now abort")
            sys.exit(1)
        return

    def loadModules(self, modules, testDef):
        # Logging of results from the environment modules usage is the responsibility of the plugin that is making use of this utility.
        if self.env_module_wrapper is None:
            # cannot perform this operation
            return (1, None, "Module capability was not found")

        # Load the lmod python module() definition
        sys.path.insert(0, os.path.dirname(self.env_module_link))
        try:
            from env_modules_python import module
        except:
            return (1, None, "No module named env_modules_python found")

        # We have to run this in the same python context for it to take effect and be propagated to future children
        # Redirect the sys.stdout and sys.stderr for the module loads and unloads.
        saved_stdout = sys.stdout
        saved_stderr = sys.stderr
        load_stdout = sys.stdout = StringIO()
        load_stderr = sys.stderr = StringIO()

        modules = modules.split()
        for mod in modules:
            mod = mod.strip()
            try:
                module("load", mod)
            except:
                # If a module name is not found the module python flow will trigger this exception.
                return (1, None, "Attempt to load environment module " + mod + " failed")

        # Restore sys.stdout and sys.stderr
        sys.stdout = saved_stdout
        sys.stderr = saved_stderr

        status = load_stderr.seek(0, os.SEEK_END)
        stdout = load_stdout.getvalue()
        stderr = load_stderr.getvalue()
        load_stdout.close()
        load_stderr.close()
        return (status, stdout, stderr)

    def unloadModules(self, modules, testDef):
        if self.env_module_wrapper is None:
            # cannot perform this operation
            return (1, None, "Module capability was not found")

        # Load the lmod python module() definition
        sys.path.insert(0, os.path.dirname(self.env_module_link))
        try:
            from env_modules_python import module
        except:
            return (1, None, "No module named env_modules_python found")

        # We have to run this in the same python context for it to take effect and be propagated to future children
        # Redirect the sys.stdout and sys.stderr for the module loads and unloads.
        saved_stdout = sys.stdout
        saved_stderr = sys.stderr
        unload_stdout = sys.stdout = StringIO()
        unload_stderr = sys.stderr = StringIO()

        modules = modules.split()
        for mod in modules:
            mod = mod.strip()
            try:
                module("unload", mod)
            except:
                # Unlike the load, the module python flow will not cause an exception if the module can not be found.
                # Add this to catch any other unexpected exceptions.
                return (1, None, "Attempt to unload environment module " + mod + " failed")

        # Restore sys.stdout and sys.stderr
        sys.stdout = saved_stdout
        sys.stderr = saved_stderr

        status = unload_stderr.seek(0, os.SEEK_END)
        stdout = unload_stdout.getvalue()
        stderr = unload_stderr.getvalue()
        unload_stdout.close()
        unload_stderr.close()
        return (status, stdout, stderr)
