# MTT Plugin Overview
To make the tool more modular and easier to generate tests, MTT makes use of the yapsy plugin system for python. Each stage that executes an .ini file makes use of at least one plugin. 

Example:
```
[TestGet:HelloWorld]
plugin = Copytree
src = /opt/mtt/samples/python/
```

Plugins are divided into categories:
-  Stages: Stages of test execution
    - MTTDefaults
    - BIOS
    - Firmware
    - Provision
    - Profile
    - MiddlewareGet
    - MiddlewareBuild
    - TestGet
    - TestBuild
    - LauncherDefaults
    - TestRun
    - Reporter
-  System: Plugins essential for MTT to run
-  Tools: Plugins required by Stages
    - The Tools plugins are split into modules:
        - Build
        - CNC
        - Executor
        - Fetch
        - Harraser
        - Launcher
        - Version
-  Utilities: Plugins used by the MTT framework

You can see the hierarchy where the plugins are defined along with their ordering on [Doxygen](/mtt/html/inherits.html). 

### Stages
The stages, as mentioned above, are used for stages. Some stages may contain additional plugins (i.e. [Reporter](https://github.com/open-mpi/mtt/tree/master/pylib/Stages/Reporter)). Each plugin in the Stages category has a set ordering which dictates what order the plugins should run.

A list of stages and their ordering can be found on [Doxygen](/mtt/html/group__Stages.html)

### System
These plugins are essential for MTT to run. However, they are not actually plugins although we treat them as such. They simply extend the object class. For explanation purposes, we will continue to refer to them as plugins.
- [LoadClasses.py](https://github.com/open-mpi/mtt/blob/master/pylib/System/LoadClasses.py)
- [TestDef.py](https://github.com/open-mpi/mtt/blob/master/pylib/System/TestDef.py)

LoadClasses is called by TestDef and loads all plugins by going through the directories and loading plugins to memory.

TestDef is passed to all other plugins so that they have access to the log, to global plugins (i.e. logger, modcmd, execmd, etc. that are saved to TestDef so they are accessible by other plugins) and to the options. This plugin is important for several reasons:
- It is the center point for setting configurations for MTT
- Sets the configuration for tests
- Logs results
- Loads plugins by called LoadClasses
- Starts execution of tests by calling one of the [Executor](https://github.com/open-mpi/mtt/tree/master/pylib/Tools/Executor) plugins. The [sequential](https://github.com/open-mpi/mtt/blob/master/pylib/Tools/Executor/sequential.py) plugin is currently the default plugin; however, the [combinatorial](https://github.com/open-mpi/mtt/blob/master/pylib/Tools/Executor/combinatorial.py) plugin can be set by using the ```--executor=combinatorial``` flag.  
- Will add two hidden sections to ConfigParser (ENV and LOG) where environment variables are stuffed into ENV and log results from other plugins are added to LOG.
    - [ConfigParser](https://docs.python.org/3/library/configparser.html) is a python library for parsing INI files

### Tools
The tool plugins are separated into modules that have no ordering. These plugins are required by the Stage plugins. 

A list of available modules and their modules along with descriptions of what they do are found on [Doxygen](/mtt/html/group__Tools.html).

### Utilities
Utility plugins are used by the MTT framework. Like the tool plugins, there is no ordering for plugins in the Utilities category. 

A list of Utility plugins can be found on [Doxygen](/mtt/html/group__Utilities.html).


# Plugin Ingredients
Each plugin is composed of two files. A yapsy-plugin file and a python file. Both of these are required when you are creating your own plugin so that MTT's plugin manager can identify where the files are located and how to connect them to the plugin framework.

## Yapsy-Plugin Config File
A yapsy-plugin requires a few key elements:
- Name of the plugin
- Author of the plugin
- Short plugin description
- Plugin version

## Python file
The python file provides the execution phase of the plugin. There are a few requirements for the python file. 

Also, a key note is that while some plugins will only run in a certain stage, not all plugins have such a requirement (i.e. [Shell.py](https://github.com/open-mpi/mtt/blob/master/pylib/Tools/Build/Shell.py)). 


### Doxygen Documentation
To make sure the plugin with all its parameters are properly recorded in Doxygen, we require a certain syntax. 
```
# @addtogroup <plugin category>
# @{
# @addtogroup <module category name if needed>
# @section <plugin name>
# Description of plugin!
# @param option_name        Description of option
# @param another_option     Additional params follow same syntax
# @}
```

### Imports
To integrate the python file into the plugin framework, there are few required imports. These imports are based on the type of plugin that you are implementing. There are four main types of plugins in MTT.  

- Stage Plugins
```from <stage_name> import * ```
- System Plugins
    -   These are not plugins, but technically classes that extend the Python object class. However, they are treated as plugins, hence why they are listed here.
- Tools Plugins
``` from <module_name> import * ```
-  Utilities Plugins
``` from BaseMTTUtility import * ```

### Options
Each plugin has a set of options that you can configure via an INI file that controls their operation.

These are set with the following syntax:
```
self.options = {}
self.options['option'] = (None, 'Description')
```
Options are the only method an INI file has to control the plugin. Options are defined in the ```__init__``` function of the plugin class.

### Required Functions
**Init Function**
The init function needs to be defined. This is where the INI file will configure the plugin through the option object. 
``` 
def __init__(self):
   # Define options
```
**Print Name**
Return the name of the function. This function is required by MTT to display the plugin in use in the logs.
```
def print_name(self):
    return "Name of Plugin"    
```
**Activate Function**
This function is **not** necessary, but may be useful when the plugin activates. The following example models the structure of the function. Add in additional functionality as needed.
```
def activate(self):
   if not self.activated:
       IPlugin.activate(self)
       self.activated = True
```
**Deactivate Function**
This function is **not** necessary, but may be useful when the plugin deactivates (i.e. acts like a destructor function for cleaning up).  The following example models the structure of the function. Add in additional functionality as needed.
```
def deactivate(self):
    if self.activates:
        IPlugin.deactivate(self)
        self.activated = False
```
 **Execute Function**
 This function controls the execution of the plugin. There are a couple key things that this function needs to do. For a complete example, please view [Shell.py](https://github.com/open-mpi/mtt/blob/master/pylib/Tools/Build/Shell.py).

- Parse Options:
```
testDef.parseOptions(log, self.options, keyvals, cmds)
``` 
- Verify cmds have the correct format and error if they do not. Errors would look like this:
```
log['status'] = 1   # 0 on success, otherwise non-zero
log['stderr'] = "error that happened"
```
- Return "location" to log: (this could be inherited from the parent log)
```
log['location'] = <file path to where plugin is executing>
```
- Execute plugin functionality. For example, in the Shell plugin, it will execute a shell command. Another thing to note is that ```execmd``` is a utility plugin (executeCmd plugin) which is meant to be called in the context of other plugins and **not** to be called by an INI file. 
```
status,stdout,stderr,time = testDef.execmd.execute(cmds, cmdargs, testDef)
```
- Send output of plugin to log. Some log information is required to be filled out for other plugins (i.e. Build Stage Plugins **need** to record ```log['compiler']``` and ```log['mpi_info']```). 
```
log['status'] = 0  # if success, otherwise non-zero
log['stdout'] = output of plugin
log['stderr'] = record any errors
log['location'] = location # record location for children plugins
```
