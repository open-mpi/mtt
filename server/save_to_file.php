<?php
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006      Cisco Systems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

# This was started on 10 July 2006 and not finished.  It's of a lesser
# concern because of
# http://perfbase.tigris.org/servlets/ReadMsg?list=users&msgNo=124.
# The issue of large uploads to apache is still a concern (e.g., a
# single MPI_Install step could generate *huge* amounts of stdout),
# but I think we're currently under whatever the limite is for
# www.open-mpi.org and probably will be for at least the near future.
# So perfbase.php will probably continue to be ok for a little while
# -- this script can be continued when a) we are sending inputs that
# are too big, and/or b) we decide that we do want to send test run
# results in "groups" (vs. individually, as they are now).

#--------------------------------------------------------------------------

# Function to reporting errors back to the client
function mtt_error($status, $str) {
    if (!headers_sent()) {
        header("HTTP/1.0 $status");
    } else {
        print("ERROR: (Tried to send HTTP error) $status\n");
    }
    print("ERROR: $str\n");
    exit(0);
}

#--------------------------------------------------------------------------

# Function for printing debugging information

function mtt_debug($str) {
    if (MTT_DEBUG) {
        print($str);
    }
}

#--------------------------------------------------------------------------

# Check to see if we can find the site-specific configuration
if (!@stat("mtt_config.php")) {
    mtt_error("501 Configuration Missing",
              "Could not find server-side 'mtt_config.php' file; aborting");
}

# Include the site-specific configuration
require("mtt_config.php");

# Set some defaults in the config data
$debug = isset($mtt_config[debug]) ? $mtt_config : 0;
if ($debug) {
    define(MTT_DEBUG, 1);
} else {
    define(MTT_DEBUG, 0);
}

# Current MTT version
define("MTT_VERSION", "0");

# Check for all the required POST variables:
# PBXML - name of xml file to use for input parsing
# PBINPUT - big variable, of data for perfbase to parse.
# MTTVERSION_MAJOR - Major revision of MTT, must match server version
# MTTVERSION_MINOR - Minor revision of MTT
foreach(array('PBXML', 'PBINPUT',
              'MTTVERSION_MAJOR', 'MTTVERSION_MINOR') as $var) {
    if (!isset($_POST[$var])) {
        mtt_error("409 Missing client data",
                  "The field $var was not specified");
    }

    mtt_debug("CGI $var $_POST[$var]\n");
}

# Check the client's version and see if it's acceptable
if (MTT_VERSION != $_POST['MTTVERSION_MAJOR']) {
    mtt_error("409 Incorrect client version",
              "This server only accepts MTT client version " . MTT_VERSION .
              ".x (your client is version " . 
              $_POST['MTTVERSION_MAJOR'] . "." .
              $_POST['MTTVERSION_MINOR'] . 
              ").  Please change your client to an appropriate version.");
}

# Get the action
$action = $_POST[action];

# Upload a fragment
if ($action == "upload_fragment") {
    $id = $_POST[id];
    $fragment = $_POST[fragment];
    if ($id == "" || $fragment = "") {
        mtt_error("501 Need to supply ID and fragment",
                  "Must supply both ID and fragment numbers when uploading data");
    }
    $datafile = tempnam($mtt_config[save_root] . "/fragments/", "upload-data.$id.$fragment.");
    $fp = fopen($datafile, "w");
    if (!$fp) {
        mtt_error("409 Could not open fragment output file",
                  "Contact the system administrator; I was unable to open the output fragment file");
    }
    fwrite($fp, $POST[data]);
    fclose($fp);
} 

# Get a new ID
else if ($action == "get_new_id") {
    $idfile = $mtt_config[save_root] . "/data/id.txt";
    $fp = fopen($idfile, "rw");
    if (!$fp) {
        mtt_error("409 Couldn't open ID file",
                  "Contact the system administrator; I was unable to open the output ID file");
    }
    if (flock($fp, LOCK_EX)) {
        # Read the last used value
        $id = fread($fp, filesize($idfile));
        if ($id == "") {
            # If there was no last value, make a new one
            $id = "0";
        }
        # Increment and write back
        ++$id;
        fseek($fp, 0, SEET_SET);
        fwrite($fp, $id);
        fclose($fp);
    } else {
        mtt_error("409 Couldn't lock ID file",
                  "Contact the system administrator; I was unable to lock the output ID file");
    }

    # Send the ID back to the client
    print($id);
} 

# Send a bunch of fragments to perfbase
else if ($action == "input_to_perfbase") {
    # JMS write more here
} 

# Unknown
else {
    mtt_error("501 Unknown action",
              "Unknown \"action\" field sent -- nothing done.");
}

mtt_debug("all done");

