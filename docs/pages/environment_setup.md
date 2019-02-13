# Python Virtual Environment Setup

Python virtual environments create an isolated environment for python based applications. Using a virtual environment for MTT means you can install all necessary dependencies without worrying about affecting other applications. This document covers two ways to set up python virtual environments. The Conda package and environment manager is the easiest to use. It is included with all versions of Anaconda and Miniconda. If you do not have access to Conda then you will need to install the virtualenv and virtualenvwrapper packages.

## Environment Setup With Conda

### Set up ~/.condarc
   Before creating a conda environment, a user will need to set up a .condarc file that will tell conda where to put conda environments. Set up your .condarc to use a location to store conda environments by issuing the following commands.

	$ conda config --add envs_dirs /path/to/your/envs

This will create ~./condarc if it doesn't exist and will add the necessary information to it. 

### Verify that 'envs directories' is correctly set using the 'conda info' command:

<pre>
$ conda info  
     active environment : None  
       user config file : /Users/username/.condarc  
 populated config files : /Users/username/.condarc  
          conda version : 4.5.11  
    conda-build version : 3.10.5  
         python version : 2.7.15.final.0  
       base environment : /Users/username/anaconda2  (writable)  
           channel URLs : https://repo.anaconda.com/pkgs/main/osx-64  
                          https://repo.anaconda.com/pkgs/r/noarch  
                          https://repo.anaconda.com/pkgs/pro/osx-64  
                          https://repo.anaconda.com/pkgs/pro/noarch  
          package cache : /Users/username/anaconda2/pkgs  
                          /Users/username/.conda/pkgs  
       envs directories : /Users/username/anaconda2/envs  
                          /Users/username/.conda/envs  
               platform : osx-64  
             user-agent : conda/4.5.11 requests/2.18.4 CPython/2.7.15 Darwin/17.7.0 OSX/10.13.6  
                UID:GID : 502:20  
             netrc file : None  
           offline mode : False   
</pre> 
 Check the 'envs directories:' it should be set to the directory given to the 'conda config --add' command. Redo if necessary (remove bad values by using 'conda config --remove envs_dirs /path/to/remove or by editing ~/.condarc)

### Create your environment using the condaEnv.txt file in the mtt directory as follows:

	$ conda env create -f /path/to/mtt/condaEnv.txt <env_name> 

### Your conda mtt environment is ready to use. 
To activate the environment use:

	$ source activate <env_name>

 To exit the environment use:

	$ source deactivate


## Environment Setup With virtualenvwrapper

Install virtualenv and virtualenvwrapper as follows:

	$ pip install virtualenv
	$ pip install virtualenvwrapper

### Set up ~/.bashrc or ~/.bash_profile
Before creating a python virtual environment with virtualenvwrapper add the following lines to your ~/.bashrc file or equivalent:

	$ source /usr/local/virtualenvwrapper.sh
	$ export WORKON_HOME=$HOME/virtualenvs

Refresh your bash shell.

	$ source ~/.bashrc  (or .bash_profile)

### Create your environment using the pyenv.txt file in the mtt directory as follows:

	$ mkvirtualenv -r /Path/to/mtt/pyenv.txt <env_name>

### Your conda mtt environment is ready to use. 
To activate the environment use:

	$ workon <env_name>

To exit the virtual environment type:

	$ deactivate

### Problems you may encounter.

* If python.h is missing you need to install python-dev and/or python3-dev.
* If pg_config is not found you need to install libpq-dev.
* Psycopg errors mean python-psycopg2 and/or python3-psycopg2 need to be installed.
* Other packages that could be missing are:
	* automake
  * libtool
  * flex
 
