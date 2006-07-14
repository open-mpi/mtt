<?php
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

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
if (!isset($mtt_pb_config[cwd])) {
    print "CWD NOT FOUND<br>\n";
    $mtt_pb_config[cwd] = "/tmp";
}
if (!isset($mtt_pb_config[perfbase])) {
    $mtt_pb_config[perfbase] = "perfbase";
}
$debug = isset($mtt_pb_config[debug]) ? $mtt_pb_config : 0;
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

# Check that the XML file that the client sent exists and is readable
$pbxml = basename($_POST[PBXML]);
if (!@stat($pbxml)) {
    mtt_error("501 Could not find XML file",
              "The XML file '$pbxml' was unable to be found on the server.");
}
$pbxml = getcwd() . "/$pbxml";
$fp = fopen($pbxml, "r");
if (!$fp) {
    mtt_error("501 Could not open XML file",
              "The file $pbxml was found but was unable to be opened on the server.");
}
fclose($fp);

# Extend the environment for the child process
if (isset($mtt_pb_config[env])) {
    foreach ($mtt_pb_config[env] as $key => $value) {
        # Expand any environment variables in the value
        if (preg_match_all("/\\\$([a-zA-Z_][a-zA-Z_0-9]*)/",
                           $value, $matches, PREG_SET_ORDER) > 0) {
            foreach ($matches as $var) {
                $value = str_replace($var[0], getenv($var[1]), $value);
            }
        }
        
        # Update the environment (do both $_ENV assign and putenv() so
        # that we can print_r($_ENV) if we're debugging.  Otherwise,
        # only putenv(), because assigning $_ENV only affects the
        # environment of *this php script*.

        if (MTT_DEBUG) {
            $_ENV[$key]=$value;
        }
        putenv("$key=$value");

        mtt_debug("config: $key => $value\n");
    }
}
mtt_debug("environment = " . print_r($_ENV, true));

# Pipes to open
$descriptors = array(0 => array("pipe", "r"),
                     1 => array("pipe", "w"));
$cmd = $mtt_pb_config[perfbase] . " input -v -u -i -d $pbxml -";
chdir($mtt_pb_config[cwd]);
$process = proc_open($cmd, $descriptors, $pipes);
if (!is_resource($process)) {
    mtt_error("500 Failed to run perfbase", 
              "The perfbase command failed to execute for some reason.  Aborting in despair.");
}
mtt_debug("Opened cmd: $cmd\n");

# Write the data to perfbase
fwrite($pipes[0], $_POST[PBINPUT]);
fclose($pipes[0]);

# Read the result back from perfbase
$output = "";
while (!feof($pipes[1])) {
    $frag = fread($pipes[1], 8192);
    if (is_string($frag)) {
        $output .= $frag;
    }
}
fclose($pipes[1]);

# Get perfbase's exit status
$status = proc_close($process);
if (0 != $status) {
    mtt_error("501 Perfbase exited with error",
              "Perfbase returned with exit status $status.  Its output was:\n$output\n");
} else {
    mtt_debug("perfbase input: succeeded\n$output\n");
}
