What is this software?
----------------------

This is the MPI Testing Tool (MTT) software package.  It is a
standalone tool for testing the correctness and performance of
arbitrary MPI implementations.

The MTT is an attempt to create a single tool to download and build a
variety of different MPI implementations, and then compile and run any
number of test suites against each of the MPI installations, storing
the results in a back-end database that then becomes available for
historical data mining.  The test suites can be for both correctness
and performance analysis (e.g., tests such as nightly snapshot compile
results as well as the latency of MPI_SEND can be historically
archived with this tool).

The MTT provides the glue to obtain and install MPI installations
(e.g., download and compile/build source distributions such as nightly
snapshots, or copy/install binary distributions, or utilize an
already-existing MPI installation), and then obtain, compile, and run
the tests.  Results of each phase are submitted to a centralized
PostgresSQL database via HTTP/HTTPS.  Simply put, MTT is a common
infrastructure that can be distributed to many different sites in
order to run a common set of tests against a group of MPI
implementations that all feed into a common PostgresSQL database of
results.

The MTT client is written almost entirely in perl; the MTT server side
is written almost entirely in PHP and relies on a back-end PostgresSQL
database.

The main (loose) requirements that we had for the MTT are:

- Use a back-end database / archival system.
- Ability to obtain arbitrary MPI implementations from a variety of
  sources (web/FTP download, filesystem copy, Subversion export,
  etc.).
- Ability to install the obtained MPI implementations, regardless of
  whether they are source or binary distributions.  For source
  distributions, include the ability to compile each MPI
  implementation in a variety of different ways (e.g., with different
  compilers and/or compile flags).
- Ability to obtain arbitrary test suites from a variety of sources
  (web/FTP download, filesystem copy, Subversion export, etc.).
- Ability to build each of the obtained test suites against each of
  the MPI implementation installations (e.g., for source MPI
  distributions, there may be more than one installation).
- Ability to run each of the built test suites in a variety of
  different ways (e.g, with a set of different run-time options).
- Ability to record the output from each of the steps above and
  submit securely them to a centralized database.
- Ability to run the entire test process in a completely automated
  fashion (e.g., via cron).
- Ability to run each of the steps above on physically different
  machines.  For example, some sites may require running the
  obtain/download steps on machines that have general internet access,
  running the compile/install steps on dedicated compile servers,
  running the MPI tests on dedicated parallel resources, and then
  running the final submit steps on machines that have general
  internet access.
- Use a component-based system (i.e., plugins) for the above steps so
  that extending the system to download (for example) a new MPI
  implementation is simply a matter of writing a new module with a
  well-defined interface.


How to cite this software
-------------------------
Hursey J., Mallove E., Squyres J.M., Lumsdaine A. (2007) An Extensible
Framework for Distributed Testing of MPI Implementations. In Recent
Advances in Parallel Virtual Machine and Message Passing Interface.
EuroPVM/MPI 2007. Lecture Notes in Computer Science, vol 4757. Springer,
Berlin, Heidelberg.
https://doi.org/10.1007/978-3-540-75416-9_15


Overview
--------

The MTT divides its execution into six phases:

1. MPI get: obtain MPI software package(s) (e.g., download, copy)
2. MPI install: install the MPI software package(s) obtained in phase 1.
   This may involve a binary installation or a build from source.
3. Test get: obtain MPI test(s)
4. Test build: build the test(s) against all MPI installations
   installed in phase 2.
5. Test run: run all the tests build in phase 4.
6. Report: report the results of phases 2, 4, and 5.

The phases are divided in order to allow a multiplicative effect.  For
example, each MPI package obtained in phase 1 may be installed in
multiple different ways in phase 2.  Tests that are built in phase 4
may be run multiple different ways in phase 5.  And so on.

This multiplicative effect allows testing many different code paths
through MPI even with a small number of actual tests.  For example,
the Open MPI Project uses the MTT for nightly regression testing.
Even with only several hundred MPI test source codes, Open MPI is
tested against a variety of different compilers, networks, number of
processes, and other run-time tunable options.  A typical night of
testing yields around 150,000 Open MPI tests.


Quick start
-----------

Testers run the MTT client on their systems to do all the work.  A
configuration file is used to specify which MPI implementations to use
and which tests to run.  

The Open MPI Project uses MTT for nightly regression testing.  A
sample Perl client configuration file is included in
samples/perl/ompi-core-template.ini.  This template will require
customization for each site's specific requirements.  It is also
suitable as an example for organizations outside of the Open MPI
Project.

Open MPI members should visit the MTT wiki for instructions on how to
setup for nightly regression testing:

    https://github.com/open-mpi/mtt/wiki/OMPITesting

The MTT client requires a few perl packages to be installed locally,
such as LWP::UserAgent.  Currently, the best way to determine if you
have all the required packages is simply to try running the client and
see if it fails due to any missing packages.

Note that the INI file can be used to specify web proxies if
necessary.  See comments in the ompi-core-template.ini file for
details.


Running the MTT Perl client
---------------------------

Having run the MTT client across several organizations within the Open
MPI Project for quite a while, we have learned that even with common
goals (such as Open MPI nightly regression testing), MTT tends to get
used quite differently at each site where it is used.  The
command-line client was designed to allow a high degree of flexibility
for site-specific requirements.

The MTT client has many command line options; see the following for a
full list:

$ client/mtt --help

Some sites add an upper layer of logic/scripting above the invocation
of the MTT client.  For example, some sites run the MTT on
SLURM-maintained clusters.  A variety of compilers are tested,
yielding multiple unique (MPI get, MPI install, Test get, Test build)
tuples.  Each tuple is run in its own 1-node SLURM allocation,
allowing the many installations/builds to run in parallel.  When the
install/build tuple has completed, more SLURM jobs are queued for each
desired number of nodes/processes to test.  These jobs all execute in
parallel (pending resource availability) in order to achieve maximum
utilization of the testing cluster.

Other scenarios are also possible; the above is simply one way to use
the MTT.


Current status
--------------

This tool was initially developed by the Open MPI team for nightly and
periodic compile and regression testing.  However, enough other
parties have expressed [significant] interest that we have open-sourced
the tool and are eagerly accepting input from others.  Indeed, having
a common tool to help objectively evaluate MPI implementations may be
an enormous help to the High Performance Computing (HPC) community at
large.

We have no illusions of MTT becoming the be-all/end-all tool for
testing software -- we do want to keep it somewhat focused on the
needs and requires of testing MPI implementations.  As such, the usage
flow is somewhat structured towards that bias.

It should be noted that the software has been mostly developed internally
to the Open MPI project and will likely experience some growing pains
while adjusting to a larger community.


License
-------

Because we want MTT to be a valuable resource to the entire HPC
community, the MTT uses the new BSD license -- see the LICENSE file in
the MTT distribution for details.


Get involved
------------

We *want* your feedback.  We *want* you to get involved.

The main web site for the MTT is:

    http://www.open-mpi.org/projects/mtt/

User-level questions and comments should generally be sent to the
user's mailing list (mtt-users@open-mpi.org).  Because of spam, only
subscribers are allowed to post to this list (ensure that you
subscribe with and post from *exactly* the same e-mail address --
joe@example.com is considered different than
joe@mycomputer.example.com!).  Visit this page to subscribe to the
user's list:

     https://lists.open-mpi.org/mailman/listinfo/mtt-users

Developer-level bug reports, questions, and comments should generally
be sent to the developer's mailing list (mtt-devel@open-mpi.org).
Please do not post the same question to both lists.  As with the
user's list, only subscribers are allowed to post to the developer's
list.  Visit the following web page to subscribe:

     https://lists.open-mpi.org/mailman/listinfo/mtt-devel
     http://www.open-mpi.org/mailman/listinfo.cgi/mtt-devel

When submitting bug reports to either list, be sure to include as much
extra information as possible.

Thanks for your time.
