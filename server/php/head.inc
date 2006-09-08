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

#
#
# Stuff that goes in the HEAD section of the HTML document
#
#

$javascript = <<<EOT

    function popup(width,height,title,content,style) {

        newwindow2=window.open('','name','height=' + height + ',width=' + width + ' scrollbars=yes');
        var tmp = newwindow2.document;
        tmp.write('<html><head><title>' + title + '</title>');
        tmp.write('<body ' + style + '>' + content + '</body></html>');
        tmp.close();
    }

    // X: combine the following two functions

    // Disable all objects passed to the function
    function disable() {

        for (i = 0; i < arguments.length; i++) {

            // alert("list[i] = " + arguments[i]);

            // Aack! How do we check to see if the val is defined!
            // The function dies if we try to disable a single undefined object

            if (undefined != arguments[i]) {
                arguments[i].disabled=1;
            }
        }
    }

    // Enable all objects passed to the function
    function enable() {
        for (i = 0; i < arguments.length; i++) {
            if (undefined != arguments[i]) {
                arguments[i].disabled=0;
            }
        }
    }

    // Toggle all the arguments (check/uncheck)
    function toggle_checkboxes() {

        one_is_checked = false;

        for (i = 0; i < arguments.length; i++) {
            var box = document.getElementByName(arguments[i]);
            if (box.checked == true) {
                one_is_checked = true;
                break;
            }
        }

        toggle = ! one_is_checked;

        for (i = 0; i < arguments.length; i++) {
            var box = document.getElementByName(arguments[i]);
            box.checked = toggle;
        }
    }

EOT;

$style = <<<EOT

    a.lgray_ln:link    { color: #F8F8F8 } /* for unvisited links */
    a.lgray_ln:visited { color: #555555 } /* for visited links */
    a.lgray_ln:active  { color: #FFFFFF } /* when link is clicked */
    a.lgray_ln:hover   { color: #FFFF40 } /* when mouse is over link */

EOT;

?>
