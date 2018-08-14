# INI File Creation
MTT offers a high degree of flexibility by allowing phases to be effectively parameterized allowing for multiple executions of each phase.

Caution needs to be executed when creating an INI file that will not take days (or weeks!) to complete. Use the ```--print-time``` option to see how long each phase is taking to help tune your INI file.

# Run Time Execution
We recommend running with  `--verbose`. This provides a decent amount of output that confirms that most MTT things are running. However, if you run into weird issues that cannot be explained, run with  `--debug`. This will provide a  _lot_  of output (you'll want to save both stdout and stderr into a file for later analysis).

# Compiler Configuration
Some compilers (such as the Intel compilers) require additional environment variables such as PATH and LD_LIBRARY_PATH to be set properly in order to find their relevant parts. It is easiest to simply set these values  _before_  invoking the MTT client, but it is also possible to set them within the INI file directly (so that you don't have to worry about local environments). However, the syntax is a little odd, so it's worth describing here:
```
[MPI Install: Intel compiler]
...all the other fields...
setenv = PATH /path/to/intel/compiler/bin:/usr/bin/:...rest of path
setenv = LD_LIBRARY_PATH /path/to/intel/compiler/lib:...rest of LD path
```
# MPI Install Errors
Sometimes MTT finds a problem in a middleware install, but a human wants to go examine it manually. When MTT installs a middleware under its scratch tree, it will automatically drop two files -- one for sh-flavored shells and one for csh-flavored shells -- that set the PATH and LD_LIBRARY_PATH to get to the middleware install. The exact location of these files depends on the section names in your INI file and the exact version number of the MPI in question. Specifically, these files will be in:
```
<patch to your scratch>/installs/<MPI Get name>/<MPI Install name>/<MPI version number>/mpi_installed_vars.sh
<patch to your scratch>/installs/<MPI Get name>/<MPI Install name>/<MPI version number>/mpi_installed_vars.csh
```

Hence, you can source these files like this (assuming a csh-flavored shell):
```
shell% cd <patch to your scratch>/installs/<MPI Get name>/<MPI Install name>/<MPI version number>
shell% source mpi_installed_vars.csh
```

Mpicc, mpirun, etc. will then be in your PATH, and the appropriate libraries will be in your LD_LIBRARY_PATH. Additionally, the environment variable MPI_ROOT will be set that points to the top-level installation directory for the middlewareBuild. This is useful with Open MPI's ```--prefix``` option to mpirun, for example. Note that  _all_  the files related to the testing of that MPI are under this tree -- the source tree, the tests, etc. So you can go examine the entire test -- not just put the MPI in question in your path.
