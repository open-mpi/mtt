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

# Include the site-specific configuration
include("config.php");

# Current MTT version
define("MTT_VERSION", "0");

# POST variables:
# PBXML - name of xml file to use for input parsing
# PBINPUT - big variable, of data for perfbase to parse.
# MTTVERSION_MAJOR - Major revision of MTT, must match server version
# MTTVERSION_MINOR - Minor revision of MTT
	
foreach(array('PBXML','PBINPUT',
        'MTTVERSION_MAJOR', 'MTTVERSION_MINOR') as $var) {
    if(!isset($_POST[$var])) {
        header("HTTP/1.0 501 Not Implemented");
        printf("ERROR: %s not specified", $var);
        return;
    }

    if(MTT_DEBUG) {
        printf("CGI %s %s\n", $var, $_POST[$var]);
    }
}

if(MTT_VERSION != $_POST['MTTVERSION_MAJOR']) {
    header("HTTP/1.0 501 Not Implemented");
    printf("ERROR: Server major version is %s, client is %s, please upgrade\n",
            MTT_VERSION, $_POST['MTTVERSION_MAJOR']);
}


# Extend the environment
foreach($mtt_pb_config as $key => $value) {
    # Expand any environment variables in the value
    if(preg_match_all("/\\\$([a-zA-Z_][a-zA-Z_0-9]*)/",
            $value, $matches, PREG_SET_ORDER) > 0) {
        foreach($matches as $var) {
            $value = str_replace($var[0], getenv($var[1]), $value);
        }
    }

    # Update the environment
    putenv("$key=$value");
    $_ENV[$key]=$value;

    if(MTT_DEBUG) {
        printf("config: %s => %s\n", $key, $value);
    }
}


if(MTT_DEBUG) {
    printf("environment:\n");
    exec("/usr/bin/env", $output, $code);
    print_r($output);
}


# Push the input data out to a file
$filename = tempnam("", "");
chmod($filename, 0644);
$file = fopen($filename, "w");

fwrite($file, $_POST['PBINPUT']);
fclose($file);


# Set up our shell command
$cmd = escapeshellcmd(sprintf("perfbase input -u -d %s %s",
        $_POST['PBXML'], $filename));

if(MTT_DEBUG) {
    printf("cmd: %s\n", $cmd);
}


# Run perfbase to import the data
$ret = exec($cmd, $output, $code);
if(0 != $code) {
    header("HTTP/1.0 501 Not Implemented");
    printf("ERROR: exec returned code %s, output follows:\n", $code);
    foreach($output as $str) print("$str\n");
} else if(MTT_DEBUG) {
    printf("perfbase input: succeeded\n");
    foreach($output as $str) print("$str\n");
}


# Get rid of our temp file
unlink($filename);

?>
