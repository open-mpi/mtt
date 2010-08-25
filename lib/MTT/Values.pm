#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006-2007 Cisco Systems, Inc.  All rights reserved.
# Copyright (c) 2007-2009 Sun Microsystems, Inc.  All rights reserved.
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
use MTT::Values::Functions::InfiniBand;
use MTT::Values::Functions::MPI::CrayMPI;
use MTT::Values::Functions::MPI::HPMPI;
use MTT::Values::Functions::MPI::IntelMPI;
use MTT::Values::Functions::MPI::OMPI;
use MTT::Values::Functions::MPI::MPICH2;
use MTT::Values::Functions::MPI::MVAPICH;
use MTT::Values::Functions::MPI::ScaliMPI;
use MTT::Values::Functions::MPI::ClusterTools;
use MTT::Values::Functions::SSH;
use MTT::Values::Functions::SVK;
use MTT::Values::Functions::SVN;
use MTT::Values::Functions::OS::Solaris;
use Data::Dumper;
use Config::IniFiles;
use Carp qw(cluck);
use vars qw(@EXPORT);
use base qw(Exporter);
@EXPORT = qw(EvaluateString IniValue Value Logical ProcessEnvKeys);

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

# Map to human-readable English labels
our $result_messages;
$result_messages->{MTT::Values::FAIL}      = "fail";
$result_messages->{MTT::Values::PASS}      = "pass";
$result_messages->{MTT::Values::TIMED_OUT} = "timeout";
$result_messages->{MTT::Values::SKIPPED}   = "skipped";

# current $ini and $section parameters (we use it in funclets)
our $evaluate_string_ini;
our $evaluate_string_section;

#--------------------------------------------------------------------------

# Returns either a scalar or array ref
sub EvaluateString {

    # Output can get pretty volumnious in this sub.
    # Someday there will be a slicker way to silence debug messages:
    #   https://svn.open-mpi.org/trac/mtt/ticket/284
    my ($d, $v) = MTT::Messages::Messages(0, 1);

    my ($str, $ini, $section) = @_;
    Debug("Evaluating: $str\n");

    # update current $ini and $section parameters
    my $evaluate_string_ini_saved = $evaluate_string_ini;
    $evaluate_string_ini = $ini;
    my $evaluate_string_section_saved = $evaluate_string_section;
    $evaluate_string_section = $section;


    # Loop over the string looking for &functions and @vars@
    my $last = 0;
    my $prefix;
    while (1) {
        # If we got an $ini and $section, replace all @vars@
        $str = _replace_vars($str, $ini, $section)
            if (defined($ini) && defined($section));
        
        my $start_pos = index($str, '&', $last);
        # If we didn't find a &, bail
        last
            if ($start_pos < 0);
        # If the & we found was actually \&, skip it
        if ($start_pos > 0 && '\\' eq substr($str, $start_pos - 1, 1)) {
            $last = $start_pos + 1;
            next;
        }

        # Keep the prefix; we'll be replacing (part of the) suffix
        $prefix .= substr($str, 0, $start_pos);
        my $remaining = substr($str, $start_pos + 1);
        Debug("--> Prefix now: $prefix\n");
        Debug("--> Remaining (after &): $remaining\n");

        # Get the function name
        my $func_name;
        ($func_name, $remaining) = _find_func_name($remaining);

        # Get the args
        my $func_args;
        ($func_args, $remaining) = _find_func_args($remaining);

        # Evaluate the function
        my $ret = _eval_func($func_name, $func_args);

        # If we got a string back, append the remaining and loop
        # around looking for more &funclets.
        if (ref($ret) eq "") {
            $str = $ret . $remaining;
            Debug("--> After eval(string), remaining: $str\n");
        } 

        # We may have gotten an *empty* array back, but in this case
        # we still want to insert one empty value (and keep looking
        # for more &funclets).
        elsif ($#{@$ret} < 0) {
            $str = $remaining;
            Debug("--> After eval(empty array), remaining: $str\n");
        }

        # Otherwise, we need to loop over all the array values and
        # evaluate all of them.  Note that we are effectively aborting
        # the loop at this point; we will return straight from here.
        else {
            my @ret;
            foreach my $s (@$ret) {
                Debug("--> After eval(array string), remaining: $s$remaining\n");
                my $result = EvaluateString($s . $remaining, $ini, $section);
                if (ref($result) eq "") {
                    push(@ret, $prefix . $result);
                } else {
                    foreach my $t (@$result) {
                        push(@ret, $prefix . $t);
                    }
                }
            }

            $evaluate_string_ini = $evaluate_string_ini_saved;
            $evaluate_string_section = $evaluate_string_section_saved;

            MTT::Messages::Messages($d, $v);
            return \@ret;
        }
    }

    # All done -- no more &functions
    Debug("Got final version before escapes: $str\n");
    $str = _replace_escapes($prefix . $str);
    Debug("Returning: $str\n");

    # restore old $ini and $section parameters
    $evaluate_string_ini = $evaluate_string_ini_saved;
    $evaluate_string_section = $evaluate_string_section_saved;

    MTT::Messages::Messages($d, $v);
    return $str;
}

sub _replace_vars {
    my ($str, $ini, $section) = @_;

    # Loop until there are no more @vars@, but only if $ini and
    # $section were provided
    Debug("Replacing vars from section $section: $str\n");
    while ($str =~ /\@(\!?[\w]+?)\@/) {
        my $var_name = $1;
        my $prefix = $`;
        my $suffix = $';

        # @foo@ gets evaluated before it gets substituted in
        my $val;
        if ($var_name =~ m/^!/) {
            # don't call EvaluateString for @!var_name@, only "copy-paste" value from section parameter
            $val = $ini->val($section, substr($var_name,1));
        } else {
            $val = EvaluateString($ini->val($section, $var_name), $ini, $section);
        }
        Debug("Got var_name: $var_name -> $val\n");
        if (!defined($val)) {
            # If we got nothing back, eliminate the token
            $str = $prefix . $suffix;
        } else {
            # If we got a string back, substitute it in
            if (ref($val) ne "") {
                my $val_str = Dumper($val);
                $val_str =~ s/\$VAR(\d+)\s=\s//;
                $val_str =~ s/;$//;
                Debug("value=$val_str\n");
                $val = $val_str;
            } 
            $str = $prefix . $val . $suffix;
        }
    }

    return $str;
}

sub _find_func_name {
    my ($str) = @_;

    $str =~ m/^\s*([a-zA-Z_][a-zA-Z_:0-9]*)\s*\(.*/;
    my $func_name = $1;
    Debug("--> Found func name: $func_name\n");
    if (!defined($func_name) || "" eq $func_name) {
        Error("Bad parse!  Malformed function name: $str\n");
    }

    # Now look for the beginning of the arguments
    $str =~ s/^\s*$func_name\s*\(//;
    Debug("--> Found beginning of arguments: $str\n");

    return ($func_name, $str);
}

sub _find_func_args {
    my ($str) = @_;

    # Loop getting all the arguments.  Each argument will be
    # surrounded by arbitrary whitespace (which will be trimmed) and
    # delimited by either a , (indicating more arguments are coming)
    # or a ) (indicating that the argument list is done).  Take care
    # to observe quoted arguments so that we do not prematurely end an
    # argument (e.g., a comma inside a quoted argument should not end
    # that argument), and also take into account nested function calls
    # that have their own matching ( and ).

    my $orig_str = $str;
    my @args;
    my $arg_end_pos;
    my $done_with_all_args = 0;
    Debug("--> Initial param search: $str\n");
    while (!$done_with_all_args) {
        # We're at the beginning of the arg; trim whitespace and
        # start moving right looking for double quote, single
        # quote, comma, and close parens.
        $str =~ s/^\s*(\S*)\s*$/\1/;
        Debug("--> Loop: trimmed search: $str\n");
        if ("" eq $str) {
            Debug("--> Loop: now empty; done\n");
        }
        
        my $start = 0;
        my $pos = 0;
        my $parens_count = 0;
        my $c;
        # Loop over each character (to find arguments)
        while ($pos <= length($str)) {
            $c = substr($str, $pos, 1);
            Debug("--> Examining char: $c (pos $pos)\n");

            # If we find a comma and the parens count is 0, we're done
            # with this argument
            if (0 == $parens_count &&
                (',' eq $c || ')' eq $c)) {
                Debug("--> Found end of arg (pos $pos)\n");
                $done_with_all_args = 1 
                    if (')' eq $c);
                last;
            } 

            # If we find a ), increment the parens count and move on
            if ('(' eq $c) {
                ++$parens_count;
                ++$pos;
                next;
            }

            # If we find a ( (if we're here, we know the parens count
            # is > 0), decrement the parens count and move on.
            elsif (')' eq $c) {
                --$parens_count;
                ++$pos;
                next;
            }

            # If we find a & (that is not a \&), replace it with
            # MTT::Values::Functions:: so that it can properly be
            # called by perl's eval and find nested functions with
            # MTT::Values::Functions (we know that we can do this
            # because we're not inside a "" or '').
            elsif ('&' eq $c && 
                   (0 == $pos || '\\' ne substr($str, $pos - 1, 1))) {
                my $p = "MTT::Values::Functions::";
                if (0 == $pos) {
                    $str = $p . substr($str, 1);
                } else {
                    $str = substr($str, 0, $pos) . $p . 
                        substr($str, $pos + 1);
                }
                $pos += length($p);
                Debug("--> Added \"$p\"; jumped to position $pos\n");
                next;
            }

            # If we find ' or ", look for the matching end quote
            elsif ('\'' eq $c || '"' eq $c) {
                Debug("--> Found beginning quote\n");
                ++$pos;
                while ($pos <= length($str)) {
                    # Make sure the quote we find is not escaped
                    if ($c eq substr($str, $pos, 1) && 
                        '\\' ne substr($str, $pos - 1, 1)) {
                        Debug("--> Found last quote\n");
                        last;
                    }
                    ++$pos;
                }
                if ($pos > length($str)) {
                    Error("Bad parse!  Could not find closing quote: $orig_str\n");
                }
            }
            ++$pos;
        }

        # Sanity check
        if ($parens_count > 0) {
            Error("Bad parse!  Did not find trailing ): $orig_str\n");
        }
        
        # We found an argument.  Was it empty?
        if (0 == $pos) {
            Debug("Found empty argument\n");
            # If there are more arguments, save an undef
            if (!$done_with_all_args) {
                Debug("...but there are more coming, so I'll save it\n");
                push(@args, undef);
            }
        } else {
            # It was not empty; trim it and save it
            my $arg = substr($str, 0, $pos);
            $arg =~ s/^\s*(\S+)\s*$/\1/;
            Debug("Found argument: $arg\n");
            push(@args, $arg);
        }
        
        # Remove what we examined from the search string
        $str = substr($str, $pos + 1);
    }
    
    Debug("--> Remainder: $str\n");
    return (\@args, $str);
}

sub _eval_func {
    my ($func_name, $func_args) = @_;

    my $ret;
    my $eval_str = "\$ret = MTT::Values::Functions::$func_name(";
    my $first = 1;
    foreach my $f (@$func_args) {
        $eval_str .= ", "
            if (!$first);
        $first = 0;
        $eval_str .= $f;
    }
    $eval_str .= ");";
    Debug("--> Calling: $eval_str\n");
    
    # Loosen stricture on this eval to allow funclets
    # (e.g., &perl()) to have their own variables
    no strict;
    eval $eval_str;
    use strict;
    
    if ($@) {
        Error("Could not evaluate: $eval_str: $@\n");
    }

    # We'll get back either a string or an array reference, but just
    # return it; the caller will handle it.
    return $ret;
}

sub _replace_escapes {
    my ($str) = @_;

    $str =~ s/\\\"/\"/g;
    $str =~ s/\\\'/\'/g;
    $str =~ s/\\\&/\&/g;
    $str =~ s/\\\\/\\/g;
    return $str;
}

#--------------------------------------------------------------------------

# Get a value from an INI file and call all the functions that it may
# have invoked
sub Value {
    Debug("Value got: @_\n");
    my $ini = shift @_;
    my $section = shift @_;
    my @names = @_;

    my $val;
    my $ret;
    foreach my $name (@names) {
        $val = $ini->val($section, $name);
        if (defined($val)) {
            $ret = EvaluateString($val, $ini, $section);
            last;
        }
    }
    Debug("Value returning: $ret\n");
    return $ret;
}

# Same as Value, but do not do EvaluateString
sub IniValue {
    Debug("IniValue got: $@_\n");
    my $ini = shift @_;
    my $section = shift @_;
    my @names = @_;

    my $val;
    my $ret;
    foreach my $name (@names) {
        $val = $ini->val($section, $name);
        if (defined($val)) {
            $ret = $val;
            last;
        }
    }
    Debug("IniValue returning: $ret\n");
    return $ret;
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
    if (defined($val)) {
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
    if (defined($val)) {
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
    if (defined($val)) {
        my @vals = split(/\n/, $val);

        # If the prepend_path parameter is a newline-delimited list, e.g.,
        #
        #   prepend_path = <<EOT
        #   PATH /foo
        #   PATH /bar
        #   PATH /baz
        #   EOT
        #
        # We assume the user means they want their PATH to be
        # /foo:/bar:/baz:$PATH with the top lines at the top of the PATH.
        # To get this behavior we have to *reverse* the ordering of @vals when 
        # prepending.
        foreach my $v (reverse @vals) {
            $v =~ m/^(\w+)\s+(.+)$/;

            if ((!defined($1)) or (!defined($2))) {
                Error("prepend_path usage: prepend_path = <path_variable> <directory>");
            }

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
    if (defined($val)) {
        my @vals = split(/\n/, $val);
        foreach my $v (@vals) {
            $v =~ m/^(\w+)\s+(.+)$/;

            if ((!defined($1)) or (!defined($2))) {
                Error("append_path usage: append_path = <path_variable> <directory>");
            }

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

    # env_module (grab the value here for reporter(s))
    $val = $config->{env_module};
    if (defined($val)) {
        my @vals = split(/\n/, $val);
        foreach my $v (@vals) {
            push(@$save, "env_module $v");
        }
    }

    # env_importer (grab the value here for reporter(s))
    $val = $config->{env_importer};
    if (defined($val)) {
        my @vals = split(/\n/, $val);
        foreach my $v (@vals) {
            push(@$save, "env_importer $v");
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
