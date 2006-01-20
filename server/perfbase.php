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
	
#foreach (array('PBUSER','PBPASS','PBXML','PBINPUT') as $var) {
foreach (array('PBXML','PBINPUT') as $var) {
    if(!isset($_POST[$var])) {
        printf("ERROR: %s not specified", $var);
        return;
    }

    printf("%s %s<br>\n", $var, $_POST[$var]);
}

# Push the input data out to a file
$filename = tempnam("", "");
chmod($filename, 0644);
$file = fopen($filename, "w");

fwrite($file, $_POST['PBINPUT']);
fclose($file);

# Run perfbase to import the data
# TODO - hardcoding this is BAD, make it not suck.
#$cmd = sprintf("pb-bin/perfbase input -u -d %s %s 2>&1",
#        $_POST['PBXML'], $filename);
$cmd = sprintf("./perfbase.sh %s %s", $_POST['PBXML'], $filename);
printf("cmd: %s<br>\n", $cmd);
$output = "foo";
$ret = exec($cmd, $output, $code);
printf("returned %d: %s<br>\n", $code, $ret);
print_r($output);

# Get rid of our temp file
#unlink($filename);

?>
