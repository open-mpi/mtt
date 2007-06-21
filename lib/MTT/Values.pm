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
use Data::Dumper;
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
    my ($str, $ini, $section) = @_;
    Debug("Evaluating: $str\n");

    # Loop until there are no more $vars
    while ($str =~ /\$(\w+)\b/) {
        my $var_name = $1;

        Debug("Got var_name: $var_name\n");

        # $var gets evaluated
        my $ret;
        my $eval_str = "\$ret = MTT::Values::Value(\$ini, \$section, \$var_name)";
        Debug("_do: $eval_str\n");
        eval $eval_str;
        if ($@) {
            Error("Could not evaluate: $eval_str: $@\n");
        }

        # $var (which is *not* an array) gets substituted
        # back into $str
        # 
        # (EAM: maybe someday we'd want to allow INI params
        # to multiply amongst each other. Today is not that
        # day.)

        $str =~ s/\$\w+\b/$ret/;
    }

    # Pattern for the next funclet
    my $regexp = '(\&\w+\((?:\"[^\"]*?\"|[^&\(]*?)\))';

    # Loop until there are no more &functions(...)
    while ($str =~ /\&(\w+)\((\"[^\"]*?\"|[^&\(]*?)\)/) {
        my $func_name = $1;
        my $func_args = $2;

        Debug("Got func_name: $func_name\n");
        Debug("Got func_args: $func_args\n");

        # Since we used a non-greedy regexp above, there cannot be any
        # &functions(...) in the $func_args, so just evaluate it.

        my $ret;
        my $eval_str = "\$ret = MTT::Values::Functions::$func_name($func_args)";
        Debug("_do: $eval_str\n");

        # Loosen stricture on this eval to allow funclets
        # (e.g., &perl()) to have their own variables
        no strict;
        eval $eval_str;
        use strict;

        if ($@) {
            Error("Could not evaluate: $eval_str: $@\n");
        }

        # If we get a string back, just handle it.
        if (ref($ret) eq "") {
            # Substitute in the $ret in place of the &function(...)
            $str =~ s/$regexp/$ret/;

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
            $str =~ s/$regexp/""/;
            Debug("String now: $str\n");

            # Now loop around and see if there are any more
            # &function(...)s
            next;
        }

        # Now we handle all the array values that came back.

        # --- If you're trying to figure out the logic here, note that
        # --- beyond this point, we're not looping any more -- we'll
        # --- simply return the list of strings.

        my @ret;
        foreach my $s (@$ret) {
            my $tmp = $str;

            # Substitute in the $s in place of the &function(...)
            $tmp =~ s/$regexp/$s/;
            $ret = EvaluateString($tmp, $ini, $section);

            if (ref($ret) eq "") {
                push(@ret, $ret);
            } else {
                push(@ret, @$ret);
            }
        }
        
        return \@ret;
    }

    #Debug("No more functions left; final: $str\n");
    return $str;
}

#--------------------------------------------------------------------------

# Get a value from an INI file and call all the functions that it may
# have invoked
sub Value {
    my ($ini, $section, $name) = @_;
    Debug("Value: $name\n");

    my $val = $ini->val($section, $name);
    return undef
        if (!defined($val));
    return EvaluateString($val, $ini, $section);
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
            $v =~ m/^(\w+)\s+(.+)$/;
            $ENV{$1} = $2;

            my $str = "setenv $1 $2";
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
            $v =~ m/^(\w+)\s+(.+)$/;
            if (exists($ENV{$1})) {
                $ENV{$1} = "${2}:" . $ENV{$1};
            } else {
                $ENV{$1} = $2;
            }

            my $str = "prepend_path $1 $2";
            push(@$save, $str);
            Debug("$str (now: $ENV{$1})\n");
        }
    }
    
    # append_path
    $val = $config->{append_path};
    if ($val) {
        my @vals = split(/\n/, $val);
        foreach my $v (@vals) {
            $v =~ m/^(\w+)\s+(.+)$/;
            if (exists($ENV{$1})) {
                $ENV{$1} = $ENV{$1} . ":$2";
            } else {
                $ENV{$1} = $2;
            }

            my $str = "append_path $1 $2";
            push(@$save, $str);
            Debug("$str (now: $ENV{$1})\n");
        }
    }
}

#--------------------------------------------------------------------------

# This function generates random strings of a given length
my $_seeded = 0;
sub RandomString {
    # length of the random string to generate
    my $length_of_randomstring = shift;

    # Need something at least sorta random -- doesn't have to be
    # entirely unique (see "srand" in perlfunc(1))
    if (!$_seeded) {
        srand(time() ^ $$ ^ unpack "%L*", `hostname`);
        $_seeded = 1;
    }

    my @chars = ('a'..'z','A'..'Z','0'..'9','_');
    my $random_string;

    foreach (1..$length_of_randomstring) {
        $random_string .= $chars[rand @chars];
    }
    return $random_string;
}

1;
