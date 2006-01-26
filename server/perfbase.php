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

# POST variables:
# PBUSER - username for us to authenticate
# PBPASS - password for us to auth (these are not postgres user/pass)
# PBXML - name of xml file to use for input parsing
# PBINPUT - big variable, of data for perfbase to parse.
	
foreach (array('PBXML','PBINPUT') as $var) {
    if(!isset($_POST[$var])) {
        printf("ERROR: %s not specified", $var);
        return;
    }

    printf("%s %s<br>\n", $var, $_POST[$var]);
}

# Extend the environment with the site-specific config
include("config.php");

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
    printf("config: %s => %s (%s) (%s)\n", $key, $value, getenv($key), $_ENV[$key]);
}


exec("/usr/bin/env", $output, $code);
print_r($output);

# Push the input data out to a file
$filename = tempnam("", "");
chmod($filename, 0644);
$file = fopen($filename, "w");

fwrite($file, $_POST['PBINPUT']);
fclose($file);

# Run perfbase to import the data
$cmd = sprintf("perfbase input -u -d %s %s", $_POST['PBXML'], $filename);
printf("cmd: %s<br>\n", $cmd);

$ret = exec($cmd, $output, $code);
printf("returned %d: %s<br>\n", $code, $ret);
print_r($output);

# Get rid of our temp file
unlink($filename);

?>
