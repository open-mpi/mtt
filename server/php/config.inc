<?php

#
#
# Configuration
#   (Sort of a leftover from how summary.php was set up)
#
#

# This var is a little silly since there is currently only one 'level' of
# detail per invocation of this script, but maybe it will get used again
# when/if we add a feature that breaks-up reports into seperate tables
$level = -1;

$linked_stuff_top = array(
    "stdout",
    "stderr",
    "environment",
);

$linked_stuff_bottom = array(
    "test_duration_interval",
);

# Additional phase-specific parameters that go in the linked table
$config['details'] = array(
    $level => array(
        'runs' => array_merge(
                        array( "test_command", "result_message",),
                        $linked_stuff_top,
                        $linked_stuff_bottom
                    ),
        'builds' => array_merge(
                        array( "configure_arguments" ),
                        $linked_stuff_top,
                        $linked_stuff_bottom
                    ),
        'installs' => array_merge(
                        array( "configure_arguments" ),
                        $linked_stuff_top,
                        $linked_stuff_bottom
                    ),
    ),
);

# Additional phase-specific parameters that go in the main table
# Note: installs/builds have identical 'add_params', so sometimes
# we will be able to merge the result sets of those two phases
# The usage of these is *broken*
$config['add_params'] = array(
    $level => array (
        'installs' => array("compiler_name","compiler_version"),
        'builds'   => array("compiler_name","compiler_version"),
        'runs'     => array("test_name", "test_np", "test_run_section_name"),
    ),
);

$config['filter'][$level] = array();
$config['by_run'][$level] = strstr($_GET["by_atom"], "by_test_run") ? true : null;

?>
