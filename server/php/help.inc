<?php

#
# Copyright (c) 2006 Sun Microsystems, Inc.
#                         All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

$help['Main Menu'] = <<<EOT

...

EOT;

$help['Timestamp (GMT)'] = <<<EOT

The time-zone independent timestamp for when the test started.

EOT;

$help['Timestamp aggregation'] = <<<EOT

To see timestamps for each row use this menu.

EOT;

$help['Phase'] = <<<EOT

<a name=phase_help>

MTT submits results to the database on three of its phases. The column
headers above the pass/fail columns map to the following ini section
names:

EOT;

$help['installs'] = <<<EOT

<a name=installs_help>
<strong>MPI Install</strong> <br>

The configuring and building of the MPI library.

EOT;

$help['builds'] = <<<EOT

<a name=builds_help>
<strong>Test Build</strong> <br>

The compiling of the individual tests with the Open MPI wrapper
compilers. (Whether tests are compiled in batches or individually may
vary from test suite to test suite. Thus, a single failed Test Build may
indicate that more than one test resulted in a compilation error.)

EOT;

$help['runs'] = <<<EOT

<a name=runs_help>
<strong>Test Run</strong> <br>

The running of the individual tests using <tt>mpirun</tt> or your chosen
resource manager.

EOT;

$help['Result'] = <<<EOT

Tests have only two possible outcomes: pass or fail.

EOT;

$help['Selections'] = <<<EOT

EOT;

$help['Aggregation'] = <<<EOT

To generate more generalized reports (meaning fewer rows and columns), use
the 'Aggregate' checkboxes. Checking a selection as 'Aggregate' will remove it
from the output table, counting the number of rows collapsed by the aggregation.

EOT;

$help['Hardware'] = <<<EOT

...

EOT;

$help['Os'] = <<<EOT

...

EOT;

$help['Os ver'] = <<<EOT

...

EOT;

$help['Cluster'] = <<<EOT

...

EOT;

$help['Mpi'] = <<<EOT

...

EOT;

$help['Mpi rev'] = <<<EOT

...
EOT;

$help['Filters'] = <<<EOT

The textfield filters are categorized into phase independent, test run
filters, and MPI install/test build filters.

EOT;

$help['Phase Independent'] = <<<EOT

The following fields are present in all MTT phases.

EOT;

$help['Stderr'] = <<<EOT

Everything sent to stderr by the test case.

EOT;

$help['Stdout'] = <<<EOT

Everything sent to stdout by the test case.

EOT;

$help['Env'] = <<<EOT

Environment variables set in the ini file for the given test case.

EOT;

$help['Config args'] = <<<EOT

The <tt>configure</tt> arguments supplied in the in file for the MPI Install.

EOT;

$help['Test msg'] = <<<EOT

The result message output by the test.

EOT;

$help['Section (MPI Get)'] = <<<EOT

...

EOT;

$help['Section (MPI Install)'] = <<<EOT

...

EOT;

$help['Test Run Filters'] = <<<EOT

...

EOT;

$help['Test name'] = <<<EOT

...

EOT;

$help['Mpirun cmd'] = <<<EOT

...

EOT;

$help['Np'] = <<<EOT

<tt>np</tt> argument passed to the <tt>mpirun</tt> command.

EOT;

$help['Suite (Build)'] = <<<EOT

This is the section name in the ini file. Generally, each ini section is
devoted to a single testsuite or a subset of a testsuite.

EOT;

$help['Suite (Run)'] = <<<EOT

Compiler used for compiling the MPI library and tests.

EOT;

$help['MPI Install/Test Build Filters'] = <<<EOT

EOT;

$help['Compiler'] = <<<EOT

Compiler used for compiling the MPI library and tests.

EOT;

$help['Compiler ver'] = <<<EOT

Version of compiler used for compiling the MPI library and tests.

EOT;

$help['Settings'] = <<<EOT

EOT;

$help['Count'] = <<<EOT

EOT;

$help['By test case'] = <<<EOT

A test case is the testing of a single command (e.g.,
<tt>configure</tt>, <tt>mpirun</tt>, <tt>mpicc</tt>, etc.).

EOT;

$help['By test run'] = $help['By test case'] . <<<EOT

A test run is the testing of a series of test cases that are performed
in a single invocation of the MTT client. An MTT test run "pass" is a
series of "MTT test cases" belonging to a single MTT test run that do
not contain a single test case failure.

EOT;

$help['Debug'] = <<<EOT

EOT;

$help['SQL'] = <<<EOT

Display underlying SQL queries.

EOT;

$help['CGI'] = <<<EOT

Echo the CGI input parameters to the screen.

EOT;

$help['Saving queries'] = <<<EOT

Each query can be saved by bookmarking the link labeled "Link to this query"
at the foot of each report.

EOT;

$help['Phase combining and implicit phase selection'] = <<<EOT

The Reporter will combine phases if either 'All' has been selected from the
Phase menu, or if the filters will permit this to happen. For example, if a
phase-specific filter is being used (e.g., "Test name" does not exist in the MPI
Install/Test Build phase, it only exists in the Test Run phase), then the report
will only display results for that phase.

EOT;

?>
