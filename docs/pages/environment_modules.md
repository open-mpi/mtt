# Environment Modules

This page describes a template for adding environment module support to SW packages and the MTT examples of using environment modules.
The examples are taken from the [OpenHPC](https://openhpc.community/) project.

# Environment Modules Reference Documentation Links
[TACC Lua based LMOD documentation](https://lmod.readthedocs.io/en/latest/)

[Legacy TCL based Modules documentation](http://modules.sourceforge.net/)

# MTT Support
By default, MTT will search for the following:

LMOD:  $MODULESHOME/init/env_modules_python.py 

Legacy: $MODULESHOME/init/python.py

When using LMOD, MODULESHOME=/opt/ohpc/admin/lmod/lmod

If needed (i.e. on Cray OS) you can also specify the location of the python interface file using the --env-module-wrapper ENV_MODULE_WRAPPER switch to pymtt.py

MTT plugins for ComandNControl (CNC), Fetch, Build, and Launcher support the following name value pairs as part of the .ini file:

```
modules_unload	Modules to unload
modules	Modules to load
modules_swap	Modules to swap
```
Examples of .ini files using environment modules can be found in the [ModuleCmd Basic Acceptance Tests](https://github.com/open-mpi/mtt/tree/master/tests/bat/ModuleCmd)

The most complex example (environment modules are inherited from middleware and parent build stages) can be found in the [ModuleCmd OpenMPI Test](https://github.com/open-mpi/mtt/blob/master/tests/bat/ModuleCmd/env_mod_openmpi.ini)

# LMOD creation via RPM .spec file
This example is from the [ClusterShell RPM](http://build.openhpc.community/OpenHPC:/1.3/updates/SLE_12/src/clustershell-ohpc-1.8-38.1.src.rpm).  To install and download on sles12 you can do the following:

```
zypper si --download-only clustershell-ohpc
cp /var/cache/zypp/packages/OpenHPC-updates/src/clustershell-ohpc-1.8-38.1.src.rpm .
rpm -ivh clustershell-ohpc-1.8-38.1.src.rpm
vi rpmbuild/SPECS/clustershell.spec
```

Here is the relevant code from the spec file

```
# OpenHPC module file
%{__mkdir_p} %{buildroot}%{OHPC_MODULES}/%{pname}
%{__cat} << EOF > %{buildroot}/%{OHPC_MODULES}/%{pname}/%{version}
#%Module1.0#####################################################################

proc ModulesHelp { } {

puts stderr " "
puts stderr "This module loads the %{pname} utility"
puts stderr "\nVersion %{version}\n"

}
module-whatis "Name: %{pname}"
module-whatis "Version: %{version}"
module-whatis "Category: python module"
module-whatis "Description: %{summary}"
module-whatis "URL %{url}"

set version %{version}

prepend-path PATH %{install_path}/bin
prepend-path PYTHONPATH %{install_path}/lib/python2.7/site-packages
prepend-path MANPATH %{install_path}/share/man

setenv %{pname}_DIR %{install_path}
setenv %{pname}_BIN %{install_path}/bin

EOF

%{__cat} << EOF > %{buildroot}/%{OHPC_MODULES}/%{pname}/.version.%{version}
#%Module1.0#####################################################################
##
## version file for %{pname}-%{version}
##
set ModulesVersion "%{version}"
EOF
```
LMOD Specific Configuration Files Examples
```
[noah@toad:pylib] cat /opt/ohpc/pub/modulefiles/clustershell/1.8
#%Module1.0#####################################################################

proc ModulesHelp { } {

puts stderr " "
puts stderr "This module loads the clustershell utility"
puts stderr "\nVersion 1.8\n"

}
module-whatis "Name: clustershell"
module-whatis "Version: 1.8"
module-whatis "Category: python module"
module-whatis "Description: VIM files for ClusterShell"
module-whatis "URL http://clustershell.sourceforge.net/"

set version 1.8

prepend-path PATH /opt/ohpc/pub/libs/clustershell/1.8/bin
prepend-path PYTHONPATH /opt/ohpc/pub/libs/clustershell/1.8/lib/python2.7/site-packages
prepend-path MANPATH /opt/ohpc/pub/libs/clustershell/1.8/share/man

setenv clustershell_DIR /opt/ohpc/pub/libs/clustershell/1.8
setenv clustershell_BIN /opt/ohpc/pub/libs/clustershell/1.8/bin

[noah@toad:pylib] cat /opt/ohpc/pub/modulefiles/clustershell/.version.1.8
#%Module1.0#####################################################################
##
## version file for clustershell-1.8
##
set ModulesVersion "1.8"
```
