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

# Make these a $colors array for easier globalizing in functions
$gray    = "#A0A0A0";
$dgray   = "#808080";
$lgray   = "#C0C0C0";
$llgray  = "#DEDEDE";
$lllgray = "#E8E8E8";
$lred    = "#FFC0C0";
$lgreen  = "#C0FFC0";
$lyellow = "#FFFFC0";
$white   = "#FFFFFF";

$align   = "center";

$thcolor  = $llgray;

$menu_width    = '220px';
$ft_menu_width = '125px';

$domain             = "http://www.open-mpi.org";
$images_dir         = "images";
$self               = $_SERVER['PHP_SELF'];
$url_basename       = "$domain/" . preg_replace('/[^\/]+$/', '', $self);
$logo_img           = "open-mpi-logo.png";
$reporter_img       = "reporter_logo.gif";
$mpi_logo_url       = "$url_basename/$images_dir/$logo_img";
$reporter_logo_url  = "$url_basename/$images_dir/$reporter_img";
$mpi_logo_path      = "./$images_dir/$logo_img";
$reporter_logo_path = "./$images_dir/$reporter_img";

$mpi_logo_url      = perfect_url($mpi_logo_url);
$reporter_logo_url = perfect_url($reporter_logo_url);
$url_basename      = perfect_url($url_basename);

# double slashes -> single slashes
# http:/ -> http://
function perfect_url($url) {
    $url = preg_replace('/[\/]+/', '/', $url);
    $url = preg_replace('/(^\w+:)(\/+)/', '${1}//', $url);
    return $url;
}

?>
