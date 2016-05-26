#!/usr/bin/env python
#
# Copyright (c) 2015-2016 Intel, Inc. All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

import sys
import select
import os
from StringIO import StringIO
from BaseMTTUtility import *

class ModuleCmd(BaseMTTUtility):
    def __init__(self):
        BaseMTTUtility.__init__(self)
        self.lmod_env_modules_python_path = None
        self.options = {}
        return

    def print_name(self):
        return "ModuleCmd"

    def print_options(self, testDef, prefix):
        lines = testDef.printOptions(self.options)
        for line in lines:
            print prefix + line
        return

    def setCommand(self, options):
        # Check first if the --env-module-cmd-path switch was used.  If not, then check for the LMOD_PKG environment variable.
        if options['env_module_cmd_path'] is not None:
            self.lmod_env_modules_python_path = options['env_module_cmd_path']
            check_if_wrapper_file_exists = os.path.join(self.lmod_env_modules_python_path , "env_modules_python.py")
            if not os.path.isfile(check_if_wrapper_file_exists):
                print "Module (lmod) python support via --env-module-cmd-path + env_modules_python.py was not found"
                return 1
        else:
            try:
                lmod_pkg = os.environ['LMOD_PKG']
                env_modules_python_path = os.path.join(lmod_pkg, "init")
                self.lmod_env_modules_python_path = env_modules_python_path
            except KeyError:
                print "Module (lmod) python support via os.environ['LMOD_PKG']/init/env_modules_python.py was not found"
                return 1
        return

    def loadModules(self, log, modules, testDef):
        if self.lmod_env_modules_python_path is None:
            # cannot perform this operation
            log['status'] = 1
            log['stderr'] = "Module (lmod) capability was not found"
            return (1, None, "Module (lmod) capability was not found")

        # Load the lmod python module() definition
        sys.path.insert(0, self.lmod_env_modules_python_path)
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
                # If a module name is not found the lmod python flow will trigger this exception.
                return (1, None, "Attempt to load environment module " + mod + " failed")

        # Restore sys.stdout and sys.stderr
        sys.stdout = saved_stdout
        sys.stderr = saved_stderr

        status = load_stderr.len
        stdout = load_stdout.getvalue()
        stderr = load_stderr.getvalue()
        load_stdout.close()
        load_stderr.close()
        log['status'] = status
        log['stdout'] = stdout
        log['stderr'] = stderr
        return (status, stdout, stderr)

    def unloadModules(self, log, modules, testDef):
        if self.lmod_env_modules_python_path is None:
            # cannot perform this operation
            log['status'] = 1
            log['stderr'] = "Module (lmod) capability was not found"
            return (1, None, "Module (lmod) capability was not found")
        
        # Load the lmod python module() definition
        sys.path.insert(0, self.lmod_env_modules_python_path)
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
                # Unlike the load, the lmod python flow will not cause an exception if the module can not be found.  
                # Add this to catch any other unexpected exceptions.
                return (1, None, "Attempt to unload environment module " + mod + " failed")

        # Restore sys.stdout and sys.stderr
        sys.stdout = saved_stdout
        sys.stderr = saved_stderr

        status = unload_stderr.len
        stdout = unload_stdout.getvalue()
        stderr = unload_stderr.getvalue()
        unload_stdout.close()
        unload_stderr.close()
        log['status'] = status
        log['stdout'] = stdout
        log['stderr'] = stderr
        return (status, stdout, stderr)
