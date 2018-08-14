# What is this software?
This is the Middleware Testing Tool (MTT) software package.  It is a standalone tool for testing the correctness and performance of arbitrary MPI implementations.

This website focuses on documenting the Python Client. For more documentation on the Perl Client, please refer to the [Wiki Pages](https://github.com/open-mpi/mtt/wiki/MTTOverview). 

MTT is a single tool created to download and build a variety of different middleware implementations, and then compile and run any number of test suites against each of the installations, storing the results in a back-end database that then becomes available for
historical data mining.  The test suites can be for both correctness and performance analysis (e.g., tests such as nightly snapshot compile results as well as the latency of MPI_SEND can be historically archived with this tool).

MTT provides the glue to obtain and install middleware installations (e.g., download and compile/build source distributions such as nightly snapshots, or copy/install binary distributions, or utilize an already-existing middleware installation), and then obtain, compile, and run the tests.  

Results of each phase are submitted to a centralized PostgresSQL database via HTTP/HTTPS.  Simply put, MTT is a common infrastructure that can be distributed to many different sites in
order to run a common set of tests against a group of Middleware implementations that all feed into a common PostgresSQL database of results.

# Overview

MTT is divided into multiple phases of execution to split up grabbing content, building content, running content, and reporting results (please refer to the [INI documentation](/mtt/pages/ini_docs.html) to learn more).

The phases are divided to allow a multiplicative effect.  For example, each middleware package obtained may be installed in multiple different ways.  The built tests may be executed in multiple different ways. And so on.

Phases are effectively templated to allow multiple executions of each phase based on parameterization. For example, you can specify a single middleware implementation, but have MTT compile it against both the GNU and Intel compilers. MTT will automatically track that there is one middleware source, but two installations of it. Every test suite that is specified will therefore be compiled and run against _both_ middleware installations, and their results filed accordingly. Hence, the MTT gives a multiplicitive effect. A simplistic view:
-   M middleware implementations are specified
-   I installations of each middleware implementation are specified
-   A total of (M * I) installations are created (assuming all are successful)
-   T test suites are specified, each of which is compiled against the (M * I) middleware installation
-   R different run parameters are specified for each test suite
-   A total of (T * R * M * I) tests are run.

Hence, you must be careful not to specify too much work to MTT -- it will happily do all of it, but it may take a long, long time!

*Note:* MTT takes care of all PATH and LD_LIBRARY_PATH issues when building and installing both middleware implementations and test suites. There is no need for the user to setup anything special in their shell startup files.

The following graphic is a decent representation of the relationships of the phases to each other, and the general sequence of phases. It shows two example middleware implementations (open MPI and MPICH), but any middleware implementation could be used (even multiple versions of the same middleware implementation):

![](/mtt/assets/images/mtt-functional.png)

# Quick start
Testers run the MTT client on their systems to do all the work.  A configuration file is used to specify which middleware implementations to use and which tests to run.  

The Open MPI Project uses MTT for nightly regression testing.  A sample Python client configuration file is included in samples/python/ompi_hello_world.ini.  It is also suitable as an example for organizations outside of the Open MPI Project.

# Nightly Regression Testing
Open MPI members should visit the [MTT Wiki](https://github.com/open-mpi/mtt/wiki/OMPITesting) for instructions on how to setup for nightly regression testing.

To configure nightly testing with Travis CI, please refer to the [Travis CI documentation](/mtt/pages/travis.html).

# Running the MTT Python client

Having run the MTT client across several organizations within the Open MPI Project for quite a while, we have learned that even with common goals (such as Open MPI nightly regression testing), MTT tends to get used quite differently at each site where it is used.  The
command-line client was designed to allow a high degree of flexibility for site-specific requirements.

The MTT client has many command line options; try the following command to see the full list of options:

```mtt/pyclient/pymtt.py --help```

Some sites add an upper layer of logic/scripting above the invocation of the MTT client.  For example, some sites run the MTT on SLURM-maintained clusters.  A variety of compilers are tested, yielding multiple unique (MiddlewareGet, MiddlewareBuild, TestGet, TestBuild) tuples. Each tuple is run in its own 1-node SLURM allocation, allowing the many installations/builds to run in parallel.  When the install/build tuple has completed, more SLURM jobs are queued for  each desired number of nodes/processes to test.  These jobs all execute in parallel (pending resource availability) in order to achieve maximum utilization of the testing cluster.

Other scenarios are also possible; the above is simply one way to use MTT.

# How to cite this software

Hursey J., Mallove E., Squyres J.M., Lumsdaine A. (2007) An Extensible Framework for Distributed Testing of MPI Implementations. In Recent Advances in Parallel Virtual Machine and Message Passing Interface. EuroPVM/MPI 2007. Lecture Notes in Computer Science, vol 4757. Springer, Berlin, Heidelberg. https://doi.org/10.1007/978-3-540-75416-9_15

# License
Because we want MTT to be a valuable resource to the entire HPC community, the MTT uses the new BSD license -- see the LICENSE file in the MTT distribution for details.

