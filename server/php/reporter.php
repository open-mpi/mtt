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

if (array_key_exists("QUERY_STRING", $_SERVER) && 
    !empty($_SERVER["QUERY_STRING"])) {
    header("Location: ./?" . $_SERVER["QUERY_STRING"]);
} else {
    header("Location: .");
}

?>
