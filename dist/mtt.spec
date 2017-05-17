%define baseName mtt
%define version 0.1
%define install_path /opt/%{baseName}

# Used to ignore files packaged automatically from sdist command
# makes error become a warning when there are installed but unpackaged files
%define _unpackaged_files_terminate_build 0

Summary: MTT
Name: %{baseName}
Version: %{version} 
Release: 1
Source0: %{baseName}-%{version}.tar.gz
License: BSD
Group: Development/Libraries
BuildRoot: %{_tmppath}/%{baseName}-%{version}-%{release}-buildroot
Prefix: /opt 
BuildArch: noarch
Url: https://github.com/open-mpi/mtt

# Use RPM's automatic dependency processing? (yes by default)
#AutoReqProv: no

%description
This is the MPI Testing Tool (MTT) software package.  It is a
standalone tool for testing the correctness and performance of
arbitrary MPI implementations.

%package common
Summary: MTT Common Files
Group: Development/Libraries
%description common
This is the MPI Testing Tool (MTT) software package for the common files.

%package pyclient
Summary: MTT PyClient
Group: Development/Libraries
Requires: mtt-common, python, python-virtualenv 
%description pyclient
This is the MPI Testing Tool (MTT) software package for the python client.

%package server 
Summary: MTT Server 
Group: Development/Libraries
Requires: mtt-common, httpd, php, postgresql >= 9.0, python, python-virtualenv, python-cherrypy 
%description server 
This is the MPI Testing Tool (MTT) software package for the server. 

%package perlclient 
Summary: MTT Perl Client 
Group: Development/Libraries
Requires: mtt-common, perl, perl-libwww-perl
%description perlclient 
This is the MPI Testing Tool (MTT) software package for the perl client.

%package bat
Summary: BAT Tests
Group: Development/Libraries
Requires: mtt-common
%description bat
This is the MPI Testing Tool (MTT) software package for Basic Acceptance (BAT) Tests.

%prep
%setup -n %{baseName}-%{version}

%build

%install
# Basic copy all files from tarball to install
rm -rf "$RPM_BUILD_ROOT"
mkdir -p "$RPM_BUILD_ROOT%{install_path}"
cp -R * "$RPM_BUILD_ROOT%{install_path}"

%clean
rm -rf $RPM_BUILD_ROOT

%files common
%defattr(-,root,root)
%dir %{install_path}
%{install_path}/README
%{install_path}/CHANGES
%{install_path}/INSTALL
%{install_path}/LICENSE
%{install_path}/samples

%files pyclient
%defattr(-,root,root)
%dir %{install_path}
%{install_path}/pyenv.txt
%{install_path}/docs
%{install_path}/pyclient
%{install_path}/pylib

%files server 
%defattr(-,root,root)
%dir %{install_path}
%{install_path}/server

%files perlclient
%defattr(-,root,root)
%dir %{install_path}
%{install_path}/client
%{install_path}/lib

%files bat
%defattr(-,root,root)
%dir %{install_path}
%{install_path}/tests

%changelog
