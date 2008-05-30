<?php

#
# Copyright (c) 2008 Sun Microsystems, Inc.
#                    All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

#
# Functions used by both the MTT Reporter and the MTT Submitter scripts
#

# Function for reporting errors back to the client
function mtt_error($str) {
    print("MTTDatabase server error: $str\n");
}

# Function for reporting notices back to the client
function mtt_notice($str) {
    print("MTTDatabase server notice: $str\n");
}

?>
