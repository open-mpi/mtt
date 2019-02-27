# User Guide

First check out the [MTT Overview](https://open-mpi.github.io/mtt/), [Getting Started](https://open-mpi.github.io/mtt/pages/environment_setup.html), [Plugins](https://open-mpi.github.io/mtt/pages/plugins_docs.html) and [INI](https://open-mpi.github.io/mtt/pages/ini_docs.html) guides to get familiar with MTT.

MTT users need to be cautious and ensure not to create an INI file that will take days (or weeks!) to complete. Use the "--print-section-time" option to the MTT client to see how long each phase is taking to help tune your INI file.

## INI file setup

All INI file parameters can be overridden at the command-line. This is helpful in avoiding the need for numerous INI files that are virtually identical.   
INI files can also be chained together on the command line. For example:    

pyclient/pymtt.py --verbose ../INIfiles/a.ini ../INIfiles/b.ini ../INIfiles/c.ini  
 
The chained files will work with each other so you can make each section of the INI file independently if you want to and then mix and match them. This can help avoid the problem of making INI files that take forever to run.

### Example INI files

Example INI files can be found in the mtt/samples/python directory. 'ompi_snapshot_seq.ini' is a short example version of an INI file that is a good place to start building your own. 'extensive_example' covers most of the possible plugins and values that are available. Since custom plugins can be used with MTT they cannot all be covered here.

### INI Section MTTDefaults
MTTDefaults phase - Some general settings for the run.

##### OPTIONS
<pre><font color="white">
 trial:                Default = False, Use when testing your MTT client setup; 
                                 results that are generated and submitted to the database 
                                 are marked as \"trials\" and are not included 
                                 in normal reporting.
 scratchdir:           Default = ./mttscratch, Specify the DIRECTORY under which 
                                  scratch files are to be stored
 description:          Default = None, Provide a brief title/description to be
                                 included in the log for this test
 platform:             Default = None, Name of the system under test
 organization:         Default = None, Name of the organization running the test
 merge_stdout_stderr:  Default = False, Merge stdout and stderr into one output 
                                 stream
 stdout_save_lines:    Default = -1, Number of lines of stdout to save 
                                 (-1 for unlimited)
 stderr_save_lines:    Default = -1, Number of lines of stderr to save 
                                 (-1 for unlimited)
 executor:             Default = sequential, Strategy to use: combinatorial or
                                 sequential executor
 time:                 Default = True, Record how long it takes to run each 
                                 individual test
</font></pre>
##### Example usage

[MTTDefaults]  
trial = True  
scratchdir = /Users/tmp/mttscratch  
description = OpenMPI master  
executor = sequential  
platform = Your_Platform  


### INI Section BIOS
COMING SOON

### INI Section Firmware
COMING SOON

### INI Section Provision
COMING SOON

### INI Section Profile
Profile phase - Runs a plugin that gets system information.
**This phase is required.**

##### Example usage
[Profile:Installed]

### INI Section MiddlewareGet
MiddlewareGet phases - can have multiple phases using a colon and unique ending identifier [MiddlewareGet:UniqueID]

This isn't a required phase - if the purpose of this test is to simply stress the physical system, then one can skip this phase by adding SKIP to the title. To avoid reprocessing sections add ASIS to the title. To run using an already installed version of MPI use the AlreadyInstalled plugin.

##### OPTIONS
<pre><font color="white">
plugin: Has no Default and other options depend on which plugin is used 

  = AlreadyInstalled     Used when the Middleware is already installed.
        module:          Default = None, Modules (or lmod modules) to be loaded for 
                                   accessing this package.
  = OMPI_Snapshot        Used to get tarballs, options are:
      url:               Default = None, URL to access the repository
      version_file:      Default = None, File containing name of most recent tarball
                                  version tested. Will not run if version matches.
      mpi_name:          Default = None, Name of OMPI tarball being tested
  = Git                  Used to get software via Git, options are:
       module:           Default = None, Modules (or lmod modules) to be loaded for 
                                   accessing this package.
       url:              Default = None, URL to access the repository
       username:         Default = None, Username required for accessing the repository
       password:         Default = None, Password required for that user to access the
                                   repository
       pwfile:           Default = None, File where password can be found
       branch:           Default = None, Branch (if not master) to be downloaded
       pr:               Default = None, Pull request to be downloaded
       subdir:           Default = None, "Subdirectory of interest in repository
</font></pre>

##### Example usage

[ASIS MiddlewareGet:OMPIMaster]  
plugin = OMPI_Snapshot  
url =  https://download.open-mpi.org/nightly/open-mpi/master  
version_file = /Path/to/your/version_file  
mpi_name = ompi-nightly-master  


[SKIP MiddlewareGet:OMPI]  
plugin = Git  
url = git@github.com:open-mpi/ompi.git  
branch = v1.10  


### INI Section MiddlewareBuild

MiddlewareBuild phases - can have multiple phases using a colon and 
unique ending identifier [MiddlewareBuild:UniqueID]

This isn't a required phase - if the purpose of this test
is to simply stress the physical system, then
one can skip this phase by adding SKIP to the title. 
To avoid reprocessing sections add ASIS to the title.

##### OPTIONS
<pre><font color="white">
       parent:             Default = None, Section that precedes this one in the
                                     dependency tree. Checks to see if the parent 
                                     successfully ran and aborts if the parent failed.
plugin: Has no Default and other options depend on which plugin is used
  = Autotools
       middleware:         Default = None, Middleware stage that these tests are to 
                                     be built against.
       autogen_cmd:        Default = None, Command to be executed to setup the  
                                     configure script, usually called autogen.sh or
                                     autogen.pl
       configure_options:  Default = None, Options to be passed to configure. 
                                     Note that the prefix will be automatically set
                                     and need not be provided here
       make_options:       Default = None, Options to be passed to the make command
       build_in_place:     Default = False, Build tests in current location 
                                     (no prefix or install)
       merge_stdout_stderr:Default = False, Merge stdout and stderr into one 
                                     output stream
       stdout_save_lines:  Default = -1, Number of lines of stdout to save 
                                    (-1 means no limit)
       stderr_save_lines:  Default = -1, Number of lines of stderr to save 
                                    (-1 means no limit)
       modules:            Default = None, Modules to load
       modules_unload:     Default = None, Modules to unload
</font></pre>

##### Example usage

[MiddlewareBuild:OMPIMaster]  
parent = MiddlewareGet:OMPIMaster  
plugin = Autotools  
configure_options = --enable-debug  
make_options = -j 1  


### INI Section TestGet

Test get phases - get the tests that the target software will run.

##### OPTIONS
<pre><font color="white">
       parent:        Default = None, Section that precedes this one in the
                                dependency tree. Checks to see if the parent 
                                successfully ran and aborts if the parent failed. 
plugin: Has no Default and other options depend on which plugin is used
  = Git               Used to get software via Git
      module:         Default = None, Modules (or lmod modules) to be loaded for
                                accessing this package
      url:            Default = None, URL to access the repository
      username:       Default = None, Username required for accessing the repository
      password:       Default = None, Password required for that user to access the
                                repository
      pwfile:         Default = None, File where password can be found
      subdir:         Default = None, "Subdirectory of interest in repository
</font></pre>

##### Example usage
[ASIS TestGet:IBM]  
parent = MiddlewareBuild:OMPIMaster  
plugin = Git  
url =  git@github.com:open-mpi/ompi-tests  
subdir = ibm  


[SKIP TestGet:Intel]  
parent = MiddlewareBuild:OMPIMaster  
plugin = Git  
url =  git@github.com:open-mpi/ompi-tests  
subdir = intel_tests  

### INI Section TestBuild
Test build phases - build the tests
##### OPTIONS
<pre><font color="white">
      parent:            Default = None, Section that precedes this one in the
                                   dependency tree. Checks to see if the parent 
                                   successfully ran and aborts if the parent failed.
DefaultTestBuild / very similar to Autotools
     middleware:         Default = None, Middleware stage that these tests are to
                                   be built against
     autogen_cmd:        Default = None, Command to be executed to setup the
                                   configure script, usually called autogen.sh 
                                   or autogen.pl
     configure_options:  Default = None, Options to be passed to configure. 
                                   Note that the prefix will be automatically set
                                   and need not be provided here
     make_options:       Default = None, Options to be passed to the make command
     build_in_place:     Default = True, Build tests in current location 
                                   (no prefix or install)
     merge_stdout_stderr:Default = False, Merge stdout and stderr into one 
                                   output stream
     stdout_save_lines:  Default = None, Number of lines of stdout to save
     stderr_save_lines:  Default = None, Number of lines of stderr to save
     modules:            Default = None, Modules to load
     modules_unload:     Default = None, "Modules to unload
</font></pre>
##### Example usage
[ASIS TestBuild:IBMInstalled]  
parent = TestGet:IBM  
middleware = MiddlewareBuild:OMPIMaster  
autogen_cmd = ./autogen.sh  
configure_options = CC=mpicc CXX=mpic++ F77=mpif77 FC=mpifort  
make_options = -j 1  
merge_stdout_stderr = 1  
stderr_save_lines = 100  

### INI Section LauncherDefaults
Define some default launcher execution parameters -

##### OPTIONS
<pre><font color="white">
       parent:            Default = None, Section that precedes this one in the
                                    dependency tree. Checks to see if the parent 
                                    successfully ran and aborts if the parent failed.
plugin: Has no Default and other options depend on which plugin is used
        There are three plugins, most of the OPTIONS are the same for all three
  = ALPS, OpenMPI, Slurm
       hostfile:         Default = None, The hostfile for The Launcher to use 
       np:               Default = None, Number of processes to run 
       options:          Default = None, Comma-delimited sets of command line
                                   options that shall be used on each test 
       skipped:          Default = 77, Exit status of a test that declares it was
                                   skipped 
       merge_stdout_stderr:Default = False, Merge stdout and stderr into one
                                     output stream 
       stdout_save_lines:Default = -1, Number of lines of stdout to save 
       stderr_save_lines:Default = -1, Number of lines of stderr to save 
       test_dir:         Default = None, Names of directories to be scanned 
                                   for tests 
       fail_tests:       Default = None, Names of tests that are expected to fail 
       fail_returncodes: Default = None, Expected return code of tests expected 
                                   to fail 
       fail_timeout:     Default = None, Maximum execution time for tests 
                                   expected to fail 
       skip_tests:       Default = None, Names of tests to be skipped 
       max_num_tests:    Default = None, Maximum number of tests to run 
       test_list:        Default = None, List of tests to run, default is all 
       allocate_cmd:     Default = None, Command to use for allocating nodes 
                                   from the resource manager 
       deallocate_cmd:   Default = None, Command to use for deallocating nodes 
                                   from the resource manager 
  = ALPS
       command:          Default = aprun, Command for executing the application
       modules:          Default = None, Modules to load 
       modules_unload:   Default = None, Modules to unload 
  = OpenMPI
       command:          Default = mpirun, Command for executing the application 
       ppn:              Default = None, Number of processes per node to run 
       timeout:          Default = None, Maximum execution time - terminate a test
                                   if it exceeds this time 
  = Slurm
       command:          Default = srun, Command for executing the application 
       timeout:          Default = None, Maximum execution time - terminate a 
                                   test if it exceeds this time 
       job_name:         Default = None, User-defined name for job 
       modules:          Default = None, Modules to load 
       modules_unload:   Default = None, Modules to unload 
</font></pre>

##### Example usage

[LauncherDefaults:OMPI]  
plugin = OpenMPI  
command = mpirun  
np = 2  
options = --verbose  
skipped = 77  
merge_stdout_stderr = 1  
stdout_save_lines = 100  
stderr_save_lines = 100  


### INI Section TestRun
Test run phase - the executor will automatically change directory to
the top directory where the tests were installed, so any search for
executables will take place relative to that point

##### OPTIONS
<pre><font color="white">
See options for Launcher Defaults above
      parent:            Default = None, Section that precedes this one in the
                                   dependency tree. Checks to see if the parent 
                                   successfully ran and aborts if the parent failed.
</font></pre>

##### Example Usage

[TestRun:IBMInstalledOMPI]  
parent = TestBuild:IBMInstalled  
plugin = OpenMPI  
timeout = 600  
test_dir = "collective, communicator, datatype, environment, group, info, io, onesided, pt2pt, random, topology"  
max_num_tests = 10  
fail_tests = abort final  
fail_timeout = max_procs  

/# THREAD_MULTIPLE test will fail with the openib btl because it  
/# deactivates itself in the presence of THREAD_MULTIPLE.  So just skip  
/# it.  loop_child is the target for loop_spawn, so we don't need to  
/# run it (although it'll safely pass if you run it by itself).  
skip_tests = init_thread_multiple comm_split_f  


### INI Section Reporter

Reporter phases - output the results of the tests  

##### OPTIONS
<pre><font color="white">
plugin: Has no Default and other options depend on which plugin is used
   = IUDatabase
       realm:          Default = None, Database name 
       username:       Default = None, Username to be used for submitting data 
       password:       Default = None, Password for that username 
       pwfile:         Default = None, File where password can be found 
       platform:       Default = None, Name of the platform (cluster) upon 
                                 which the tests were run 
       hostname:       Default = None, Name of the hosts involved in the tests 
                                 (may be regular expression) 
       url:            Default =  None, URL of the database server 
       debug_filename: Default = None, Debug output file for server interaction 
                                 information 
       keep_debug_files:Default= False, Retain reporter debug output after execution 
       debug_server:   Default = False, Ask the server to return its debug output
                                 as well 
       email:          Default = None, Email to which errors are to be sent 
       debug_screen:   Default = False, Print debug output to screen 
   
  = JunitXML
       filename:       Default = None, Name of the file into which the report 
                                 is to be written 
       textwrap:       Default = 80, Max line length before wrapping 
   = TextFile
       filename:       Default = None, Name of the file into which the report 
                                 is to be written. 
       summary_footer: Default = None, Footer to be placed at bottom of summary 
       detail_header:  Default = None, Header to be put at top of detail report 
       detail_footer:  Default = None, Footer to be placed at bottom of detail 
                                 report 
       textwrap:       Default = 80, Max line length before wrapping 
</font></pre>
##### Example usage

[Reporter: text file backup]  
plugin = TextFile  
filename = mttresults.txt  
textwrap = 78  
  
[SKIP Reporter: IU database]  
plugin = IUDatabase  
realm = OMPI  
username = database user name  
password = database password  
platform = Your_Platform  
url = https://mtt.open-mpi.org/submit/cpy/api/  

