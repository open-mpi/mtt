### MTT Console

#### Building the console

The MTT console is a Python-based application constructed on top of several key software platforms. The primary console uses Django to provide a Web-based method for scanning available test options (e.g., node inventory, images), selecting both configuration and tests to be executed on that configuration, and submitting the test to the resource manager.

The console is executed inside a "virtual" Python environment to avoid conflicts between the console's required packages and those installed on the host system. Users are free to build/run the console directly on the host system if they so choose - instructions for setting up the virtual environment are provided for those seeking to use it.

##### Install Python

It probably is already there, but Django doesn't support all versions. You should ensure that you either have Python 2.7, or Python 3.4 before continuing.

##### Install the Pythoon virtual tools (optional)

This can be done several ways, but the easiest is to just utilize the _easy_install_ script:

```
$ easy_install virtualenv virtualenv-wrappers
```

This should install virtualenv and the virtualenv-wrappers in your default site-packages directory. In order to use them, you need to add the following lines to your .bashrc (or the equivalent lines in the setup file for whichever shell you prefer):

```
source "/usr/bin/virtualenvwrapper.sh"
export WORKON_HOME=~/virtualenvs
```

where WORKON_HOME points to wherever you want your virtual environments to be stored. It is best to make it somewhere convenient as you'll need to "source" the activate script from that location when wanting to use a particular virtual environment.

##### Download the MTT code

How you choose to organize code is up to you. Most developers prefer to put the source code in a directory separate from the virtual environment. This leaves the Git management a little easier since Git won't see all the Python packages.

Assuming that is what you choose to do, create some top-level directory for code development:

```
$ mkdir ~/code
$ cd ~/code
```
and clone the MTT repo into it:

```
$ git clone http://github.com/open-mpi/mtt
$ cd mtt
```

Now you can setup the Python environment by simply typing:

```
$ mkvirtualenv -r pyenv.txt
```

This will create the virtual environment in a subdirectory created under your WORKON_HOME location, and add all the required packages (django, django-enumfield, etc.) to it. It will also create an executable "manage.py" file in your current working directory. At this time, you are nearly ready to go - all that is necessary is to setup your database.

##### Setup a database

Your system almost certainly came with sqlite3 on it, but if not, this is the time to download and install that package. You can run with a variety of more sophisticated databases (e.g., PostGRES and MySQL), but sqlite3 is just fine for development and other non-production uses. Use your favorite package manager (yum, apt-get, or rpm) to install it.

The database is not included in the repository to avoid repo conflicts caused by different users testing with their own data. However, all the changes made to the model have been included. You first need to create a "superuser" account for the database:

```
$ python manage.py createsuperuser
```

You can use any username, email address, and password you desire. Once that has been done, we move the model definitions into the db using some help from Django:

```
$ python manage.py migrate
```

You are now ready to play! You can start the Django server with:

```
$ python manage.py runserver
```

Aim your browser at 127.0.0.1:8080 to see the web site. Alternatively, if you want to be able to view the site from other computers, you can either set the IP address or listen on all available interfaces:

```
$ python manage.py runserver <IP>:<port>
$ python manage.py runserver 0.0.0.0:<port>
```

You can then connect to the MTT console by pointing your web browser at the IP address and port of the server, adding the "admin" modifier:

```
http://<IP>:<port>/admin
```


##### References

There are some good resources out there to help with Django and its use in projects such as MTT:

[Test-Driven Development with Python](http://chimera.labs.oreilly.com/books/1234000000754/index.html) by Harry Percival (available both online and in print) 

[Django documentation](https://docs.djangoproject.com/en/1.8/)


