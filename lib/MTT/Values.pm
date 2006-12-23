#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006      Cisco Systems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Values;

use strict;
use MTT::Messages;
use MTT::Values::Functions;
use Config::IniFiles;
use vars qw(@EXPORT);
use base qw(Exporter);
@EXPORT = qw(EvaluateString Value Logical ProcessEnvKeys);

# Exported result values.  These values are in sync with the server --
# do not change them without also changing the server!  ARRGH.  These
# constants must be before the rest of the "use" statements because
# they are used in MTT::Test::*, which are "used" below.  #@$%@#$%!
use constant {
    FAIL => 0,
    PASS => 1,
    SKIPPED => 2,
    TIMED_OUT => 3,
};

#--------------------------------------------------------------------------

sub EvaluateString {
    my ($str) = @_;
    Debug("Evaluating: $str\n");

    # Loop until there are no more &functions(...)
    while ($str =~ /\&(\w+)\(([^&\(]*?)\)/) {
        my $func_name = $1;
        my $func_args = $2;
        Debug("Got name: $func_name\n");
        Debug("Got args: $func_args\n");

        # Since we used a non-greedy regexp above, there cannot be any
        # &functions(...) in the $func_args, so just evaluate it.

        my $ret;
        my $eval_str = "\$ret = MTT::Values::Functions::$func_name($func_args)";
        Debug("_do: $eval_str\n");
        eval $eval_str;
        if ($@) {
            Error("Could not evaluate: $eval_str: $@\n");
        }

        # If we get a string back, just handle it.
        if (ref($ret) eq "") {
            # Substitute in the $ret in place of the &function(...)
            $str =~ s/(\&\w+\([^&\(]*?\))/$ret/;
            Debug("String now: $str\n");

            # Now loop around and see if there are any more
            # &function(...)s
            next;
        }

        # Otherwise, we get an array back, recursively call back
        # through for each item in the array.  Not efficient, but it
        # gets the job done.  However, we may have gotten an *empty*
        # array back, in which case we still need to substitute in
        # nothing into the string and continue looping around.

        if ($#{@$ret} < 0) {
            # Put an empty string in the return value's place in the
            # original string
            $str =~ s/(\&\w+\([^&\(]*?\))/""/;
            Debug("String now: $str\n");

            # Now loop around and see if there are any more
            # &function(...)s
            next;
        }

        # Now we handle all the array values that came back.

        # --- If you're trying to figure out the logic here, note that
        # --- beyond this point, we're not looping any more -- we'll
        # --- simply return.

        my @ret;
        foreach my $s (@$ret) {
            my $tmp = $str;
            # Substitute in the $s in place of the &function(...)
            $tmp =~ s/(\&\w+\([^&\(]*?\))/$s/;
            $ret = EvaluateString($tmp);
            if (ref($ret) eq "") {
                push(@ret, $ret);
            } else {
                push(@ret, @$ret);
            }
        }
        return \@ret;
    }

#    Debug("No more functions left; final: $str\n");
    return $str;
}

#--------------------------------------------------------------------------

# Get a value from an INI file and call all the functions that it may
# have invoked
sub Value {
    my ($ini, $section, $name) = @_;

    my $val = $ini->val($section, $name);
    return undef
        if (!defined($val));
    return EvaluateString($val);
}

#--------------------------------------------------------------------------

# Get a Value and evaluate it as either true or false; return value
# will be 0 or 1.
sub Logical {
    my ($ini, $section, $name) = @_;

    my $val = Value($ini, $section, $name);
    return undef
        if (!defined($val));
    if (!$val || 
        $val == 0 || 
        $val eq "0" ||
        lc($val) eq "no" ||
        lc($val) eq "false" ||
        lc($val) eq "off") {
        return 0;
    } elsif ($val == 1 ||
             $val eq "1" ||
             lc($val) eq "yes" ||
             lc($val) eq "true" ||
             lc($val) eq "on") {
        return 1;
    }

    # Assume true

    return 1;
}

#--------------------------------------------------------------------------

sub ProcessEnvKeys {
    my ($config, $save) = @_;

    # setenv
    my $val = $config->{setenv};
    if ($val) {
        my @vals = split(/\n/, $val);
        foreach my $v (@vals) {
            my $name = $v;
            $name =~ s/(\w+)\W.+/\1/;
            my $str = $v;
            $str =~ s/\w+\W+(.+)\W*/\1/;
            $ENV{$name} = $str;

            $str = "setenv $name $str";
            push(@$save, $str);
            Debug("$str\n");
        }
    }
    
    # unsetenv
    $val = $config->{unsetenv};
    if ($val) {
        my @vals = split(/\n/, $val);
        foreach my $v (@vals) {
            delete $ENV{$v};

            my $str = "unsetenv $v";
            push(@$save, $str);
            Debug("$str\n");
        }
    }
    
    # prepend_path
    $val = $config->{prepend_path};
    if ($val) {
        my @vals = split(/\n/, $val);
        foreach my $v (@vals) {
            my $name = $v;
            $name =~ s/(\w+)\W.+/\1/;
            my $str = $v;
            $str =~ s/\w+\W+(.+)\W*/\1/;
            
            if (exists($ENV{$name})) {
                $ENV{$name} = "${str}:" . $ENV{$name};
            } else {
                $ENV{$name} = $str;
            }

            $str = "prepend_path $name $str";
            push(@$save, $str);
            Debug("$str\n");
        }
    }
    
    # append_path
    $val = $config->{append_path};
    if ($val) {
        my @vals = split(/\n/, $val);
        foreach my $v (@vals) {
            my $name = $v;
            $name =~ s/(\w+)\W.+/\1/;
            my $str = $v;
            $str =~ s/\w+\W+(.+)\W*/\1/;
            
            if (exists($ENV{$name})) {
                $ENV{$name} = $ENV{$name} . ":$str";
            } else {
                $ENV{$name} = $str;
            }

            $str = "append_path $name $str";
            push(@$save, $str);
            Debug("$str\n");
        }
    }
}

# This function generates random strings of a given length
sub RandomString {

    # length of the random string to generate
    my $length_of_randomstring = shift;
    my @chars = ('a'..'z','A'..'Z','0'..'9','_');
    my $random_string;

    foreach (1..$length_of_randomstring) {
        $random_string .= $chars[rand @chars];
    }
    return $random_string;
}

1;
