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

	# First thing, do a dumb authentication check
	define("USERNAME", "afriedle");
	define("PASSWORD", "135w00t");

	# POST variables:
	# PBUSER - username for us to authenticate
	# PBPASS - password for us to auth (these are not postgres user/pass)
	# PBXML - name of xml file to use for input parsing
	# PBINPUT - big variable, of data for perfbase to parse.

	foreach (array('PBUSER','PBPASS','PBXML','PBINPUT') as $var) {
		if(!isset($_POST[$var])) {
			printf("ERROR: $var not specified");
			return;
		}

		printf("%s %s<br>\n", $var, $_POST[$var]);
	}

	# Authenticate the user - really dumb method, right now.
#   if(USERNAME != $_POST['PBUSER'] || PASSWORD != $_POST['PBPASS']) {
#		printf("ERROR: authentication failed");
#		return;
#	}

	# Push the input data out to a file
#	$filename = tempnam("", "");
#	$file = fopen($filename, "w");

#	fwrite($file, $_POST['PBINPUT']);
#	fclose($file);

	# Run perfbase to import the data
	# TODO - hardcoding this is BAD, make it not suck.
#$cmd = sprintf("/u/afriedle/pb-bin/perfbase input -u -d %s %s",
#			$_POST['PBXML'], $filename);
#	printf("cmd: %s<br>\n", $cmd);
#	system($cmd);

	# Get rid of our temp file
#	unlink($filename);
?>
