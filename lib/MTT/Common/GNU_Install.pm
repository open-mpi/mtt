#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006-2012 Cisco Systems, Inc.  All rights reserved.
# Copyright (c) 2007-2008 Sun Microsystems, Inc.  All rights reserved.
# Copyright (c) 2009      High Performance Computing Center Stuttgart, 
#                         University of Stuttgart.  All rights reserved.
# Copyright (c) 2015      Research Organization for Information Science
#                         and Technology (RIST). All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

package MTT::Common::GNU_Install;
my $package = ModuleName(__PACKAGE__);

use strict;
use MTT::Messages;
use MTT::Values;
use MTT::Common::Do_step;

#--------------------------------------------------------------------------

# Do the following steps:
#   [?] autogen.[sh|pl]
#   [ ] configure
#   [?] make clean
#   [ ] make all
#   [?] make check
#   [ ] make install
#
# ? = optional step
sub Install {
    my ($config) = @_;

    my $x;
    my $result_stdout;
    my $result_stderr;

    # Prepare $ret
    my $ret;
    $ret->{test_result} = MTT::Values::FAIL;
    $ret->{exit_status} = 0;

    # If the user does not use --prefix on their own, default
    # to $installdir
    my $prefix;
    if ($config->{configure_arguments} !~ /--prefix\b/) {
        $config->{configure_arguments} .= " --prefix=$config->{installdir}";
    }

    # Process the optional step booleans
    if (!$config->{make_clean}) {
        $config->{skip_make_clean} = 1;
    }
    if (!$config->{make_check}) {
        $config->{skip_make_check} = 1;
    }

    # Run autogen (optional).  Older OMPI's had autogen.sh; newer
    # OMPI's have autogen.pl.
    if ($config->{autogen}) {
        my $autogen_cmd;
        $autogen_cmd = "./autogen.sh"
            if (-x "autogen.sh");
        $autogen_cmd = "./autogen.pl"
            if (-x "autogen.pl");
        if ($autogen_cmd) {
            $autogen_cmd .= " $config->{autogen_arguments}"
                if ($config->{autogen_arguments});
            $x = MTT::Common::Do_step::do_step($config, $autogen_cmd, 1);
            %$ret = (%$ret, %$x);
            return $ret if (!MTT::DoCommand::wsuccess($ret->{exit_status}));
        } else {
            $ret->{test_result} = MTT::Values::FAIL;
            $ret->{result_message} = "Could not find autogen.sh or autogen.pl";
            return $ret;
        }
    }

    # Run the configure script
    $x = MTT::Common::Do_step::do_step($config, "configure",
                  $config->{merge_stdout_stderr},  $config->{configdir});

    # Overlapping keys in $x override $ret
    %$ret = (%$ret, %$x);
    return $ret if (!MTT::DoCommand::wsuccess($ret->{exit_status}));

    # "make clean" can fail for all we care
    $x = MTT::Common::Do_step::do_step($config, "make clean", 1);
    %$ret = (%$ret, %$x);

    $x = MTT::Common::Do_step::do_step($config, "make all", $config->{merge_stdout_stderr});
    %$ret = (%$ret, %$x);
    return $ret if (!MTT::DoCommand::wsuccess($ret->{exit_status}));

    # Do we want to run "make check"?  If so, make sure a valid TMPDIR
    # exists.  Also, merge the result_stdout/result_stderr because we
    # really only want to see it if something fails (i.e., it's common
    # to display junk to result_stderr during "make check"'s normal
    # execution).

    my %ENV_SAVE = %ENV;
    $ENV{TMPDIR} = "$config->{installdir}/tmp";
    mkdir($ENV{TMPDIR}, 0777);
    # The intent here is just to ensure that the LD_LIBRARY_PATH
    # in the environment does not point to shared libraries
    # outside of MTT's scope that would interfere with "make
    # check" (e.g., another libmpi.so outside of MTT).  Just
    # prepend our own $libdir to LD_LIBRARY_PATH and hope that
    # that's Good Enough.  :-)
    if (exists($ENV{LD_LIBRARY_PATH})) {
        $ENV{LD_LIBRARY_PATH} = "$config->{libdir}:$ENV{LD_LIBRARY_PATH}";
    } else {
        $ENV{LD_LIBRARY_PATH} = "$config->{libdir}";
    }

    $x = MTT::Common::Do_step::do_step($config, "make check VERBOSE=1", 1);
    %$ret = (%$ret, %$x);
    return $ret if (!MTT::DoCommand::wsuccess($ret->{exit_status}));
    %ENV = %ENV_SAVE;

    $x = MTT::Common::Do_step::do_step($config, "make install", 1);
    %$ret = (%$ret, %$x);
    return $ret if (!MTT::DoCommand::wsuccess($ret->{exit_status}));

    # All done!
    $ret->{test_result} = MTT::Values::PASS;
    $ret->{result_message} = "Success";
    Debug("Build was a success\n");

    return $ret;
}

1;
