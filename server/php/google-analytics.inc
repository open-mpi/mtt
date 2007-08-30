<?php

# If global $mtt_google_anatics_account is defined, return some GA goodness.
# If a key is passed in, use that as the URL.  Otherwise, urchinTracker 
# will simply use the current URL. 
function print_ga($key = "") {
    global $mtt_google_analytics_account;

    if (empty($mtt_google_analytics_account)) {
        return "";
    }

    return "<!-- Start Google analytics -->
<script src=\"http://www.google-analytics-foo.com/urchin.js\" type=\"text/javascript\">
</script>
<script type=\"text/javascript\">
_uacct = \"$mtt_google_analytics_account\";
urchinTracker($key);
</script>
<!-- End Google analytics -->";
}
