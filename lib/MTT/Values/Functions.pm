#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006-2008 Cisco Systems, Inc.  All rights reserved.
# Copyright (c) 2007-2008 Sun Microsystems, Inc.  All rights reserved.
# Copyright (c) 2010      Oracle and/or its affiliates.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Values::Functions;

use strict;
use File::Find;
use File::Temp qw(tempfile);
use File::Basename;
use Sys::Hostname;
use MTT::Messages;
use MTT::Globals;
use MTT::Files;
use MTT::FindProgram;
use MTT::Lock;
use MTT::Util;
use MTT::INI;
use MTT::Values;
use Data::Dumper;
use MTT::Values::Functions::Icc_codecov;
# Do NOT use MTT::Test::Run here, even though we use some
# MTT::Test::Run values below.  This will create a "use loop".  Be
# confident that we'll get the values as appropriate when we need them
# through other "use" statements.
my @check_ib_errors;
#--------------------------------------------------------------------------
sub check_ib_errors
{
    my $parametr = $_[0];
    if($parametr eq "save")
    {
        print "qwerty save\n";
        my $str = `ibcheckerrors -N`;
        my @local_array = split("\n",$str);
        pop(@local_array);
        pop(@local_array);
        pop(@local_array);
        $str = join("\nq",@local_array);
        @local_array = split("q",$str);
        push @check_ib_errors, [@local_array];
    }
    elsif($parametr eq "compare")
    {
        print "qwerty compare\n";
        my $str = `ibcheckerrors -N`;
        my @local_array = split("\n",$str);
        pop(@local_array);
        pop(@local_array);
        pop(@local_array);
        $str = join("\n%%%",@local_array);
        @local_array = split("%%%",$str);
        push @check_ib_errors, [@local_array];
        my $all_report_string;
        my $flag;
        for(my $q=2;$q<=$#check_ib_errors+1;$q++)
        {
            my @array1 = @{$check_ib_errors[0]};
            my @array2 = @{$check_ib_errors[$q-1]};
            my $report_string = "-->errors appears after mtt start:\n";
            for(my $i=0;$i<=$#array2;$i++)
            {
                $flag = 0;
                for(my $j=0;$j<=$#array1;$j++)
                {
                    if($array2[$i] eq $array1[$j])
                    {
                        $flag = 1;
                        $array1[$j] = "";
                        last;
                    }
                }
                if($flag == 0)
                {
                    $report_string .= $array2[$i];
                }
            }
            $report_string .= "-->errors no longer observed after mtt:\n" . join("",@array1);
            $all_report_string .= "\ncompare 1 call  and $q  call \n$report_string\n";
        }
        print "qwerty\n $all_report_string\n";
        return $all_report_string;
    }else
    {
        Warning("get_ib_errors: unknow parametr $parametr\n");
    }
}
sub get_codecov
{
    MTT::Values::Functions::Icc_codecov::get_codecov_result();
}

# Returns the result value (array or scalar) of a perl eval
sub perl {
    my $funclet = '&' . FuncName((caller(0))[3]);
    Debug("&perl $funclet: got @_\n");

    my $cmd = join(/ /, @_);
    Debug( "CMD: $cmd\n");

    # Loosen stricture here to allow &perl() to 
    # have its own variables
    no strict;
    my $ret = eval $cmd;
    use strict;
    Debug("ERROR: $?\n");

    if (ref($ret) =~ /array/i) {
        Debug("$funclet: returning array [@$ret]\n");
    } else {
        Debug("$funclet: returning scalar $ret\n");
    }

    return $ret;
}

#--------------------------------------------------------------------------

# Returns the result_stdout of running a shell command
sub shell {
    Debug("&shell: got @_\n");
    my $cmd = join(/ /, @_);
    open SHELL, "$cmd|";
    my $ret;
    while (<SHELL>) {
        $ret .= $_;
    }
    chomp($ret);
    Debug("&shell: returning $ret\n");
    return $ret;
}

#--------------------------------------------------------------------------

# Runs MTT::Messages::Verbose
sub verbose {
    MTT::Messages::Verbose(@_);
    return undef;
}

#--------------------------------------------------------------------------

# Runs MTT::Messages::Debug
sub debug {
    MTT::Messages::Debug(@_);
    return undef;
}

#--------------------------------------------------------------------------

# Runs print
sub print {
    print(@_);
    return undef;
}

#--------------------------------------------------------------------------

# Return the sum of all parameters
sub sum {
    my $array = get_array_ref(\@_);
    Debug("&sum got: @$array\n");
    return "0"
        if (!defined($array));

    my $sum = 0;
    foreach my $val (@$array) {
        $sum += $val;
    }

    Debug("&sum returning: $sum\n");
    return $sum;
}

#--------------------------------------------------------------------------

# Increment the argument:
#   * For integers, add $offset
#   * For non-integers, increment the ASCII value by $offset
# The offset defaults to 1.
sub increment {
    my ($val, $offset) = @_;
    my $ret;
    Debug("&increment got: $val\n");

    $offset = 1 if (!defined($offset));

    # Pass through, if there's no alphanumeric
    # to increment
    if ($val !~ /\w/) {
        $ret = $val;

    } elsif ($val =~ /(.*)?([a-zA-Z])$/) {
        $ret = $1 . chr(ord($2) + $offset);

    # For an integer, add $offset
    } elsif ($val =~ /\d+/) {
        $ret = $val + $offset;
    } 

    Debug("&increment returning: $ret\n");
    return $ret;
}

# Decrement the argument:
#   * For integers, subtract $offset
#   * For non-integers, decrement the ASCII value by $offset
# The offset defaults to 1.
sub decrement {
    my ($val, $offset) = @_;
    my $ret;
    Debug("&decrement got: $val\n");

    $offset = 1 if (!defined($offset));

    # Pass through, if there's no alphanumeric
    # to decrement
    if ($val !~ /\w/) {
        $ret = $val;

    # If there's only a trailing letter, decrement
    # just that
    } elsif ($val =~ /(.*)?([a-zA-Z])$/) {
        $ret = $1 . chr(ord($2) - $offset);

    # For an integer, subtract $offset
    } elsif ($val =~ /\d+/) {
        $ret = $val - $offset;
    } 

    Debug("&decrement returning: $ret\n");
    return $ret;
}

sub multiply {
    my $array = get_array_ref(\@_);
    Debug("&multiply got: @$array\n");
    return "0"
        if (!defined($array));

    my $prod = 1;
    foreach my $val (@$array) {
        $prod *= $val;
    }

    Debug("&multiply returning: $prod\n");
    return $prod;
}

sub divide {
    my $array = get_array_ref(\@_);
    Debug("&divide got: @$array\n");
    return "0"
        if (!defined($array));

    my $dividend = shift @$array;
    my $divisor =  shift @$array;
    my $quotient = int($dividend / $divisor);

    Debug("&divide returning: $quotient\n");
    return $quotient;
}

#--------------------------------------------------------------------------

# Return all the squares
sub squares {
    Debug("&squares got: @_\n");
    my ($min, $max) = @_;

    my @ret;
    my $val = $min;
    while ($val <= $max) {
        push(@ret, $val * $val);
        ++$val;
    }

    return \@ret;
}

#--------------------------------------------------------------------------

# Similar to the PHP array_fill function
sub array_fill {
    Debug("&array_fill got: @_\n");
    my ($num, $value) = @_;

    my @ret;
    foreach (1..$num) {
        push(@ret, $value);
    }

    Debug("&array_fill returning: @ret\n");
    return \@ret;
}

#--------------------------------------------------------------------------

# Returns the log of a number in base N
sub log {
    Debug("&log got: @_\n");
    my ($base, $val) = @_;
    return log($val) / log($base);
}

#--------------------------------------------------------------------------

# Return all the powers of a given base from [base^min, base^max]
sub pow {
    Debug("&pow got: @_\n");
    my ($base, $min, $max) = @_;

    my @ret;
    my $val = $min;
    while ($val <= $max) {
        push(@ret, $base ** $val);
        ++$val;
    }

    return \@ret;
}

#--------------------------------------------------------------------------

# Return a list of prime numbers between min and max
sub prime {
    Debug("&prime got: @_\n");
    my ($min, $max) = @_;

    my @primes = qw/  
      2      3      5      7     11     13     17     19     23     29 
     31     37     41     43     47     53     59     61     67     71 
     73     79     83     89     97    101    103    107    109    113 
    127    131    137    139    149    151    157    163    167    173 
    179    181    191    193    197    199    211    223    227    229 
    233    239    241    251    257    263    269    271    277    281 
    283    293    307    311    313    317    331    337    347    349 
    353    359    367    373    379    383    389    397    401    409 
    419    421    431    433    439    443    449    457    461    463 
    467    479    487    491    499    503    509    521    523    541 
    547    557    563    569    571    577    587    593    599    601 
    607    613    617    619    631    641    643    647    653    659 
    661    673    677    683    691    701    709    719    727    733 
    739    743    751    757    761    769    773    787    797    809 
    811    821    823    827    829    839    853    857    859    863 
    877    881    883    887    907    911    919    929    937    941 
    947    953    967    971    977    983    991    997   1009   1013 
   1019   1021   1031   1033   1039   1049   1051   1061   1063   1069 
   1087   1091   1093   1097   1103   1109   1117   1123   1129   1151 
   1153   1163   1171   1181   1187   1193   1201   1213   1217   1223 
   1229   1231   1237   1249   1259   1277   1279   1283   1289   1291 
   1297   1301   1303   1307   1319   1321   1327   1361   1367   1373 
   1381   1399   1409   1423   1427   1429   1433   1439   1447   1451 
   1453   1459   1471   1481   1483   1487   1489   1493   1499   1511 
   1523   1531   1543   1549   1553   1559   1567   1571   1579   1583 
   1597   1601   1607   1609   1613   1619   1621   1627   1637   1657 
   1663   1667   1669   1693   1697   1699   1709   1721   1723   1733 
   1741   1747   1753   1759   1777   1783   1787   1789   1801   1811 
   1823   1831   1847   1861   1867   1871   1873   1877   1879   1889 
   1901   1907   1913   1931   1933   1949   1951   1973   1979   1987 
   1993   1997   1999   2003   2011   2017   2027   2029   2039   2053 
   2063   2069   2081   2083   2087   2089   2099   2111   2113   2129 
   2131   2137   2141   2143   2153   2161   2179   2203   2207   2213 
   2221   2237   2239   2243   2251   2267   2269   2273   2281   2287 
   2293   2297   2309   2311   2333   2339   2341   2347   2351   2357 
   2371   2377   2381   2383   2389   2393   2399   2411   2417   2423 
   2437   2441   2447   2459   2467   2473   2477   2503   2521   2531 
   2539   2543   2549   2551   2557   2579   2591   2593   2609   2617 
   2621   2633   2647   2657   2659   2663   2671   2677   2683   2687 
   2689   2693   2699   2707   2711   2713   2719   2729   2731   2741 
   2749   2753   2767   2777   2789   2791   2797   2801   2803   2819 
   2833   2837   2843   2851   2857   2861   2879   2887   2897   2903 
   2909   2917   2927   2939   2953   2957   2963   2969   2971   2999 
   3001   3011   3019   3023   3037   3041   3049   3061   3067   3079 
   3083   3089   3109   3119   3121   3137   3163   3167   3169   3181 
   3187   3191   3203   3209   3217   3221   3229   3251   3253   3257 
   3259   3271   3299   3301   3307   3313   3319   3323   3329   3331 
   3343   3347   3359   3361   3371   3373   3389   3391   3407   3413 
   3433   3449   3457   3461   3463   3467   3469   3491   3499   3511 
   3517   3527   3529   3533   3539   3541   3547   3557   3559   3571 
   3581   3583   3593   3607   3613   3617   3623   3631   3637   3643 
   3659   3671   3673   3677   3691   3697   3701   3709   3719   3727 
   3733   3739   3761   3767   3769   3779   3793   3797   3803   3821 
   3823   3833   3847   3851   3853   3863   3877   3881   3889   3907 
   3911   3917   3919   3923   3929   3931   3943   3947   3967   3989 
   4001   4003   4007   4013   4019   4021   4027   4049   4051   4057 
   4073   4079   4091   4093   4099   4111   4127   4129   4133   4139 
   4153   4157   4159   4177   4201   4211   4217   4219   4229   4231 
   4241   4243   4253   4259   4261   4271   4273   4283   4289   4297 
   4327   4337   4339   4349   4357   4363   4373   4391   4397   4409 
   4421   4423   4441   4447   4451   4457   4463   4481   4483   4493 
   4507   4513   4517   4519   4523   4547   4549   4561   4567   4583 
   4591   4597   4603   4621   4637   4639   4643   4649   4651   4657 
   4663   4673   4679   4691   4703   4721   4723   4729   4733   4751 
   4759   4783   4787   4789   4793   4799   4801   4813   4817   4831 
   4861   4871   4877   4889   4903   4909   4919   4931   4933   4937 
   4943   4951   4957   4967   4969   4973   4987   4993   4999   5003 
   5009   5011   5021   5023   5039   5051   5059   5077   5081   5087 
   5099   5101   5107   5113   5119   5147   5153   5167   5171   5179 
   5189   5197   5209   5227   5231   5233   5237   5261   5273   5279 
   5281   5297   5303   5309   5323   5333   5347   5351   5381   5387 
   5393   5399   5407   5413   5417   5419   5431   5437   5441   5443 
   5449   5471   5477   5479   5483   5501   5503   5507   5519   5521 
   5527   5531   5557   5563   5569   5573   5581   5591   5623   5639 
   5641   5647   5651   5653   5657   5659   5669   5683   5689   5693 
   5701   5711   5717   5737   5741   5743   5749   5779   5783   5791 
   5801   5807   5813   5821   5827   5839   5843   5849   5851   5857 
   5861   5867   5869   5879   5881   5897   5903   5923   5927   5939 
   5953   5981   5987   6007   6011   6029   6037   6043   6047   6053 
   6067   6073   6079   6089   6091   6101   6113   6121   6131   6133 
   6143   6151   6163   6173   6197   6199   6203   6211   6217   6221 
   6229   6247   6257   6263   6269   6271   6277   6287   6299   6301 
   6311   6317   6323   6329   6337   6343   6353   6359   6361   6367 
   6373   6379   6389   6397   6421   6427   6449   6451   6469   6473 
   6481   6491   6521   6529   6547   6551   6553   6563   6569   6571 
   6577   6581   6599   6607   6619   6637   6653   6659   6661   6673 
   6679   6689   6691   6701   6703   6709   6719   6733   6737   6761 
   6763   6779   6781   6791   6793   6803   6823   6827   6829   6833 
   6841   6857   6863   6869   6871   6883   6899   6907   6911   6917 
   6947   6949   6959   6961   6967   6971   6977   6983   6991   6997 
   7001   7013   7019   7027   7039   7043   7057   7069   7079   7103 
   7109   7121   7127   7129   7151   7159   7177   7187   7193   7207
   7211   7213   7219   7229   7237   7243   7247   7253   7283   7297 
   7307   7309   7321   7331   7333   7349   7351   7369   7393   7411 
   7417   7433   7451   7457   7459   7477   7481   7487   7489   7499 
   7507   7517   7523   7529   7537   7541   7547   7549   7559   7561 
   7573   7577   7583   7589   7591   7603   7607   7621   7639   7643 
   7649   7669   7673   7681   7687   7691   7699   7703   7717   7723 
   7727   7741   7753   7757   7759   7789   7793   7817   7823   7829 
   7841   7853   7867   7873   7877   7879   7883   7901   7907   7919/;
   
    my @ret;
    foreach my $prime (@primes) {
        next if ($prime < $min);
        last if ($prime > $max);
        push(@ret, $prime);
    }

    Debug("&prime returning: @ret\n");
    return \@ret;
}

#--------------------------------------------------------------------------

# Return the minimum value of all parameters
sub min {
    my $array = get_array_ref(\@_);
    Debug("&min got: @$array\n");
    return "0"
        if (!defined($array));

    my $min = shift(@$array);
    foreach my $val (@$array) {
        $min = $val
            if ($val < $min)
    }

    Debug("&min returning: $min\n");
    return $min;
}

#--------------------------------------------------------------------------

# Return the maximum value of all parameters
sub max {
    my $array = get_array_ref(\@_);
    Debug("&max got: @$array\n");
    return "0"
        if (!defined($array));

    my $max = shift(@$array);
    foreach my $val (@$array) {
        $max = $val
            if ($val > $max)
    }

    Debug("&max returning: $max\n");
    return $max;
}

#--------------------------------------------------------------------------

# Return 1 if all the values are not equal, 0 otherwise.  If there are
# no arguments, return 1.
sub ne {
    my $array = get_array_ref(\@_);
    Debug("&ne got: @$array\n");
    return "0"
        if (!defined($array));

    my $first = shift(@$array);
    do {
        my $next = shift(@$array);
        if ($first eq $next) {
            Debug("&ne: returning 0\n");
            return "0";
        }
    } while (@$array);
    Debug("&ne: returning 1\n");
    return "1";
}

#--------------------------------------------------------------------------

# Return 1 if the first argument is greater than the second
sub gt {
    my $array = get_array_ref(\@_);
    Debug("&gt got: @$array\n");
    return "0"
        if (!defined($array));

    my $a = shift(@$array);
    my $b = shift(@$array);

    if ($a > $b) {
        Debug("&gt: returning 1\n");
        return "1";
    } else {
        Debug("&gt: returning 0\n");
        return "0";
    }
}

#--------------------------------------------------------------------------

# Return 1 if the first argument is greater than or equal to the second
sub ge {
    my $array = get_array_ref(\@_);
    Debug("&ge got: @$array\n");
    return "0"
        if (!defined($array));

    my $a = shift(@$array);
    my $b = shift(@$array);

    if ($a >= $b) {
        Debug("&ge: returning 1\n");
        return "1";
    } else {
        Debug("&ge: returning 0\n");
        return "0";
    }
}

#--------------------------------------------------------------------------

# Return 1 if the first argument is less than the second
sub lt {
    my $array = get_array_ref(\@_);
    Debug("&lt got: @$array\n");
    return "0"
        if (!defined($array));

    my $a = shift(@$array);
    my $b = shift(@$array);

    if ($a < $b) {
        Debug("&lt: returning 1\n");
        return "1";
    } else {
        Debug("&lt: returning 0\n");
        return "0";
    }
}

#--------------------------------------------------------------------------

# Return 1 if the first argument is less than or equal to the second
sub le {
    my $array = get_array_ref(\@_);
    Debug("&le got: @$array\n");
    return "0"
        if (!defined($array));

    my $a = shift(@$array);
    my $b = shift(@$array);

    if ($a <= $b) {
        Debug("&le: returning 1\n");
        return "1";
    } else {
        Debug("&le: returning 0\n");
        return "0";
    }
}

#--------------------------------------------------------------------------

# Return 1 if all the values are equal, 0 otherwise.  If there are no
# arguments, return 1.
sub eq {
    my $array = get_array_ref(\@_);
    Debug("&eq got: @$array\n");
    return "1"
        if (!defined($array));

    my $first = shift(@$array);
    do {
        my $next = shift(@$array);;
        if ($first ne $next) {
            Debug("&eq: returning 0\n");
            return "0";
        }
    } while (@$array);
    Debug("&eq: returning 1\n");
    return "1";
}

#--------------------------------------------------------------------------

# Return "1" if the first arg matches the second arg (the regexp)
sub regexp {
    my $funclet = "regexp";
    Debug("&$funclet got: @_\n");
    return "1"
        if (!@_);

    my $string = shift;
    my $pattern = shift;

    if ($string =~ /$pattern/m) {
        Debug("$funclet: returning 1\n");
        return "1";
    }
    Debug("$funclet: returning 0\n");
    return "0";
}

#--------------------------------------------------------------------------

# Return the captured group in the regular expression
# E.g.,:
#   &regexp_capture("foo bar", "\w+ (\w+)")
#   returns "bar"
sub regexp_capture {
    my $funclet = "regexp_capture";
    Debug("&$funclet got: @_\n");
    return ""
        if (!@_);

    my $string = shift;
    my $pattern = shift;

    if ($string =~ /$pattern/) {
        Debug("$funclet: returning $+\n");
        return $+;
    }
    Debug("$funclet: returning \"\"\n");
    return "";
}

#--------------------------------------------------------------------------

sub and {
    my $array = get_array_ref(\@_);
    Debug("&and got: @$array\n");
    return "1"
        if (!@$array);

    do {
        my $val = shift(@$array);
        if (!$val) {
            Debug("&and: returning 0\n");
            return "0";
        }
    } while (@$array);
    Debug("&and: returning 1\n");
    return "1";
}

#--------------------------------------------------------------------------

# Return 1 if any of the values are true, 0 otherwise.  If there are no
# arguments, return 1.
sub or {
    my $array = get_array_ref(\@_);
    Debug("&or got: @$array\n");
    return "1"
        if (!@$array);

    do {
        my $val = shift(@$array);
        if ($val) {
            Debug("&or: returning 1\n");
            return "1";
        }
    } while (@$array);
    Debug("&or: returning 0\n");
    return "0";
}

#--------------------------------------------------------------------------

# If the first argument is true (nonzero), return the 2nd argument.
# Otherwise, return the 3rd argument.
sub if {
    Debug("&if got: @_\n");
    my ($t, $a, $b) = @_;

    my $ret = $t ? $a : $b;
    Debug("&if returning $ret\n");
    return $ret;
}

#--------------------------------------------------------------------------

# Return a reference to all the strings passed in as @_
# skip empty elements
sub enumerate_notempty {
    my $array = get_array_ref(\@_);
    Debug("&enumerate_notempty got: @$array\n");

    my @ret;
    foreach my $arg (@$array) {
        if (length($arg) > 0) {
            push(@ret, $arg);
        } else {
            Debug("&enumerate_notempty: skip empty");
        }
    }
    return \@ret;
}
#--------------------------------------------------------------------------

# Return a reference to all the strings passed in as @_
sub enumerate {
    my $array = get_array_ref(\@_);
    Debug("&enumerate got: @$array\n");

    my @ret;
    foreach my $arg (@$array) {
        push(@ret, $arg);
    }
    return \@ret;
}

# Calc np from ppn array, example:
# number of hosts is 4
# desired ppn=1,4,8
# calc_np_from_ppn(4,1,4,8) will generate array of desired NP values, i.e.
# 4,16,32
#
sub calc_np_from_ppn {
    my $array = get_array_ref(\@_);
    Debug("&calc_np_from_ppn got: @$array\n");

    my @ret;
    my $nhosts = 0;
    foreach my $arg (@$array) {
        if (!$nhosts) {
            $nhosts = $arg;
            next;
        }
        push(@ret, $arg * $nhosts);
    }
    return \@ret;
}

#--------------------------------------------------------------------------

# Joint multiple enumerate results and join them together sequentially.  E.g., 
#
# a = &enumerate("1", "2", "3")
# b = &enumerate("4", "5", "6")
# c = &enumerate_join(@a@, @b@)
#
# c will equal "1", "2", "3", "4", "5", "6"
sub enumerate_join {
    my $str;

    my $first = 1;
    foreach my $arg (@_) {
        $str .= "\n"
            if (!$first);
        $first = 0;

        my $bar = get_array_ref($arg);
        $str .= join("\n", @$bar);
    }
    Debug("&enumerate_join got: $str\n");

    my @ret;
    foreach my $arg (@_) {
        my $array = get_array_ref($arg);
        foreach my $arg (@$array) {
            push(@ret, $arg)
                if (defined($arg));
        }
    }

    Debug("&enumerate_join returning: " . join("\n", @ret) . "\n");
    return \@ret;
}

#--------------------------------------------------------------------------

# Return a reference to all the strings passed in as @_
sub split {
    Debug("&split got: @_\n");
    my $str = shift;
    my $n = shift;

    my @ret = split(/\s+/, $str);
    if (defined($n)) {
        return $ret[$n];
    } else {
        return \@ret;
    }
}

#--------------------------------------------------------------------------

# Prepend a string to a string or an array of stringd
sub prepend {
    my $str = shift;
    my $array = get_array_ref(\@_);
    Debug("&prepend got $str @$array\n");
    return undef
        if (!defined($array));

    # $array is now guaranteed to be a reference to an array.
    my @ret;
    my $val;
    push(@ret, $str . $val)
        while ($val = shift @$array);

    return \@ret;
}


#--------------------------------------------------------------------------

# Join all the strings passed into one string and return it
sub stringify {
    my $array = get_array_ref(\@_);
    Debug("&stringify got: @$array\n");

    my $str;
    while (@$array) {
        my $val = shift(@$array);
        if (ref($val) =~ /array/i) {
            $str .= stringify(@$val);
        } elsif ("" eq ref($val)) {
            $str .= $val;
        } else {
            Warning("Got an argument to &stringify() that was not understood; ignored\n");
        }
    }
    Debug("&stringify returning: $str\n");
    return $str;
}

#--------------------------------------------------------------------------

sub preg_replace {
    Debug("&preg_replace got: @_\n");
    my ($pattern, $replacement, $subject) = @_;

    my $ret = $subject;
    $ret =~ s/$pattern/$replacement/;
    Debug("&preg_replace returning: $ret\n");
    return $ret;
}

#--------------------------------------------------------------------------

sub strstr {
    Debug("&strstr got: @_\n");
    my ($s1, $s2) = @_;

    if ($s2 =~ s/($s1.*)/\1/) {
        Debug("&strstr returning: $s2\n");
        return $s2;
    } else {
        Debug("&strstr returning: <undef>\n");
        return undef;
    }
}

#--------------------------------------------------------------------------

# First argument is the lower bound, second argument is upper bound,
# third [optional] argument is the stride (is 1 if not specified).
# Return a reference to all values starting with $lower and <=$upper
# with the given $stride.  E.g., &step(3, 10, 2) returns 3, 5, 7, 9.
sub step {
    Debug("&step got: @_\n");

    my $lower = shift;
    my $upper = shift;
    my $step = shift;
    $step = 1
        if (!$step);

    my @ret;
    while ($lower <= $upper) {
        push(@ret, "$lower");
        $lower += $step;
    }
    return \@ret;
}

#--------------------------------------------------------------------------

# Get the platform type
sub get_platform_type {
    Debug("&get_platform_type\n");
    my $ret = whatami("-t");
    return $ret
        if (defined($ret));

    my $x = MTT::DoCommand::Cmd(1, "uname -p");
    if (0 == $x->{return_status}) {
        chomp($x->{result_stdout});
        return $x->{result_stdout};
    }
    return "unknown";
}

# Get the platform hardware
sub get_platform_hardware {
    Debug("&get_platform_hardware\n");
    my $ret = whatami("-m");
    return $ret
        if (defined($ret));

    my $x = MTT::DoCommand::Cmd(1, "uname -m");
    if (0 == $x->{return_status}) {
        chomp($x->{result_stdout});
        return $x->{result_stdout};
    }
    return "unknown";
}

# Get the OS name
sub get_os_name {
    Debug("&get_os_name\n");
    my $ret = whatami("-n");
    return $ret
        if (defined($ret));

    my $x = MTT::DoCommand::Cmd(1, "uname -s");
    if (0 == $x->{return_status}) {
        chomp($x->{result_stdout});
        return $x->{result_stdout};
    }

    return "unknown";
}

# Get the OS version
sub get_os_version {
    Debug("&get_os_version\n");
    my $ret = whatami("-r");
    return $ret
        if (defined($ret));

    my $x = MTT::DoCommand::Cmd(1, "uname -v");
    if (0 == $x->{return_status}) {
        chomp($x->{result_stdout});
        return $x->{result_stdout};
    }
    return "unknown";
}

#--------------------------------------------------------------------------

# Run the "whatami" command
my $_whatami;
sub whatami {
    Debug("&whatami got: @_\n");

    # Find whatami
    if (!defined($_whatami)) {
        my $dir = MTT::FindProgram::FindZeroDir();
        $_whatami = "$dir/whatami/whatami"
            if (-x "$dir/whatami/whatami");
        $_whatami = "$dir/whatami"
            if (!defined($_whatami) && -x "$dir/whatami");
        foreach my $dir (split(/:/, $ENV{PATH})) {
            if (!defined($_whatami) && -x "$dir/whatami") {
                $_whatami = "$dir/whatami";
                last;
            }
        }
        $_whatami = $ENV{MTT_WHATAMI}
            if (!defined($_whatami) && exists($ENV{MTT_WHATAMI}) &&
                -x $ENV{MTT_WHATAMI});
        return undef
            if (!defined($_whatami));
        Debug("Found whatami: $_whatami\n");
    }

    # Run the whatami program
    my $x = MTT::DoCommand::Cmd(1, "$_whatami @_");
    return undef
        if (0 != $x->{exit_status});
    chomp($x->{result_stdout});
    return $x->{result_stdout};
}

#--------------------------------------------------------------------------

# Return the current np value from a running test.
sub test_command_line {
    Debug("&test_command_line returning: $MTT::Test::Run::test_command_line\n");

    return $MTT::Test::Run::test_command_line;
}

#--------------------------------------------------------------------------

# Return the current np value from a running test.
sub test_np {
    Debug("&test_np returning: $MTT::Test::Run::test_np\n");

    return $MTT::Test::Run::test_np;
}

#--------------------------------------------------------------------------

# Return the current prefix value from a running test
sub test_prefix {
    Debug("&test_prefix returning: $MTT::Test::Run::test_prefix\n");

    return $MTT::Test::Run::test_prefix;
}

# Return the current prefix value from a running test.
# substitute test directory name (which was created with random name)
# with symbolic name which contains mpi/compiler version information
#
# before: /path/to/scratch/installs/GrBg/install 
# after: /path/to/scratch/installs/ompi-nightly-v1.3--gcc--1.3rc2r20078/install
#
sub test_prefix_pretty {
    my $exe1 = test_prefix();
    $MTT::Test::Run::test_prefix_pretty = $exe1; 
    my ($up1_name, $up1_path) = fileparse($exe1);
    $up1_path =~ s/\/$//g;

    my ($up2_name, $up2_path) = fileparse($up1_path);
    my $cmd = "find $up2_path -maxdepth 1 -type l -ls";
    foreach my $item (`$cmd`) {
        if ($item =~ /\b$up2_name\b$/) {
            my @tokens = split(" ", $item);
            my $res = $tokens[10] . "/$up1_name";
            if ( -d $res ) {
                Debug("&test_prefix_pretty returning: $res\n");
                return $res;
            }
        }
        next;
    }
    Debug("&test_prefix_pretty returning: $MTT::Test::Run::test_prefix\n");
    return $MTT::Test::Run::test_prefix;
}

#--------------------------------------------------------------------------

# Return the current executable value from a running test
sub test_executable {
    Debug("&test_executable returning: $MTT::Test::Run::test_executable\n");

    return $MTT::Test::Run::test_executable;
}

sub test_executable_dir {
    Debug("&test_executable_dir returning: $MTT::Test::Run::test_executable_dir\n");

    return $MTT::Test::Run::test_executable_dir;
}

sub test_executable_abspath{
    Debug("&test_executable_abspath returning: $MTT::Test::Run::test_executable_abspath\n");

    return $MTT::Test::Run::test_executable_abspath;
}

sub test_executable_basename {
    Debug("&test_executable_basename returning: $MTT::Test::Run::test_executable_basename\n");

    return $MTT::Test::Run::test_executable_basename;
}

#--------------------------------------------------------------------------

# Return the current argv (excluding $argv[0]) from a running test
sub test_argv {
    Debug("&test_argv returning $MTT::Test::Run::test_argv\n");

    return $MTT::Test::Run::test_argv;
}

sub test_alloc {
    my $sect = $MTT::Globals::Values->{active_section} ;
    my $val = get_ini_val($sect, "alloc");
    Debug("&test_alloc returning $val for $sect\n");
    return $val;
}

# return MPI extra argv which are needed for specific test, example:
# -x LD_PRELOAD=libhugetlbfs.so -x HUGETLB_MORECORE=yes -x OMPI_MCA_memory_ptmalloc2_disable=1
sub test_extra_mpi_argv {
    my $sect = $MTT::Globals::Values->{active_section} ;
    my $val = get_ini_val($sect, "mpi_extra_argv");
    Debug("&test_alloc returning $val for $sect\n");
    return $val;
}

#--------------------------------------------------------------------------

# Return whether the last test run was terminated by a signal
sub mpi_details {
    my $name = shift;
    Debug("&mpi_details: $name returning: " . 
            $MTT::Test::Run::mpi_details->{$name});

    return $MTT::Test::Run::mpi_details->{$name};
}

#--------------------------------------------------------------------------

# Return the exit exit_status from the last test run
# DEPRECATED
sub test_exit_status {
    Debug("&test_exit_status: this function is deprecated; please call test_wexitstatus()\n");
    return test_wexitstatus();
}

#--------------------------------------------------------------------------

# Return whether the last test run terminated normally
sub test_wifexited {
    my $ret = MTT::DoCommand::wifexited($MTT::Test::Run::test_exit_status);
    Debug("&test_wifexited returning: $ret\n");
    return $ret ? "1" : "0";
}

#--------------------------------------------------------------------------

# Return the exit status from the last test run
sub test_wexitstatus {
    my $ret = MTT::DoCommand::wexitstatus($MTT::Test::Run::test_exit_status);
    Debug("&test_wexitstatus returning $ret\n");
    return "$ret";
}

#--------------------------------------------------------------------------

# Return whether the last test run was terminated by a signal
sub test_wifsignaled {
    my $ret = MTT::DoCommand::wifsignaled($MTT::Test::Run::test_exit_status);
    Debug("&test_widsignaled returning: $ret\n");
    return $ret ? "1" : "0";
}

#--------------------------------------------------------------------------

# Return whether the last test run was terminated by a signal
sub test_wtermsig {
    my $ret = MTT::DoCommand::wtermsig($MTT::Test::Run::test_exit_status);
    Debug("&test_wtermsig returning: $ret\n");
    return "$ret";
}

#--------------------------------------------------------------------------

# Return whether the last DoCommand::Cmd[Script] terminated normally
sub cmd_wifexited {
    my $ret = MTT::DoCommand::wifexited($MTT::DoCommand::last_exit_status);
    Debug("&cmd_wifexited returning: $ret\n");
    return $ret ? "1" : "0";
}

#--------------------------------------------------------------------------

# Return the exit status from the last DoCommand::Cmd[Script]
sub cmd_wexitstatus {
    my $ret = MTT::DoCommand::wexitstatus($MTT::DoCommand::last_exit_status);
    Debug("&cmd_wexitstatus returning $ret\n");
    return "$ret";
}

#--------------------------------------------------------------------------

# Return whether the last DoCommand::Cmd[Script] was terminated by a signal
sub cmd_wifsignaled {
    my $ret = MTT::DoCommand::wifsignaled($MTT::DoCommand::last_exit_status);
    Debug("&cmd_widsignaled returning: $ret\n");
    return $ret ? "1" : "0";
}

#--------------------------------------------------------------------------

# Return whether the last DoCommand::Cmd[Script] was terminated by a signal
sub cmd_wtermsig {
    my $ret = MTT::DoCommand::wtermsig($MTT::DoCommand::last_exit_status);
    Debug("&cmd_wtermsig returning: $ret\n");
    return "$ret";
}

#--------------------------------------------------------------------------

# Return pid of last DoCommand::Cmd
sub cmd_pid {
    my $ret = $MTT::DoCommand::pid;
    Debug("&cmd_pid returning: $ret\n");
    return "$ret";
}

#--------------------------------------------------------------------------

# Return stdout from last DoCommand::Cmd
sub cmd_stdout {
    my $ret = $MTT::Globals::Values->{last_cmd_stdout};
    Debug("&cmd_stdout returning: $ret\n");
    return "$ret";
}

# Return stderr from last DoCommand::Cmd
sub cmd_stderr {
    my $ret = $MTT::Globals::Values->{last_cmd_stderr};
    Debug("&cmd_stderr returning: $ret\n");
    return "$ret";
}

#--------------------------------------------------------------------------

# Return a reference to an array of strings of the contents of a file
sub cat {
    my $array = get_array_ref(\@_);
    Debug("&cat: @$array\n");

    my @ret;
    foreach my $file (@$array) {
        if (-f $file) {
            open(FILE, $file);
            while (<FILE>) {
                chomp;
                push(@ret, $_);
            }
            close(FILE);
        }
    }

    Debug("&cat returning: @ret\n");
    return \@ret;
}

#--------------------------------------------------------------------------

# Traverse a tree (or a bunch of trees) and return all the executables
# found
my @find_executables_data;
my $find_executables_template;
sub find_executables {
    my $array = get_array_ref(\@_);
    Debug("&find_executables got @$array\n"); 

    @find_executables_data = ();
    my @dirs;
    foreach my $d (@$array) {
        push(@dirs, $d)
            if ("" ne $d);
    }
    File::Find::find(\&find_executables_sub, @dirs);

    Debug("&find_exectuables returning: @find_executables_data\n");
    return \@find_executables_data;
}

sub find_executables_sub {
    # Don't process directories and links, and don't recurse down
    # "special" directories
    if ( -l $_ ) { return; }
    if ( -d $_ ) { 
        if ((/\.svn/) || (/\.deps/) || (/\.libs/) || (/autom4te\.cache/)) {
            $File::Find::prune = 1;
        }
        return;
    }

    # $File::Find::name is the path relative to the starting point.
    # $_ contains the file's basename.  The code automatically changes
    # to the processed directory, so we want to examine $_.
    push(@find_executables_data, $File::Find::name)
        if (-x $_);
}

sub find_executables_regexp {
    $find_executables_template = shift(@_);
    my $array = get_array_ref(\@_);
    Debug("&find_executables_regexp got $find_executables_template, @$array\n");

    @find_executables_data = ();
    my @dirs;
    foreach my $d (@$array) {
        push(@dirs, $d)
            if ("" ne $d);
    }
    File::Find::find(\&find_executables_sub_regexp, @dirs);

    Debug("&find_exectuables_regexp returning: @find_executables_data\n");
    return \@find_executables_data;
}

sub find_executables_sub_regexp {
    # Don't process directories and links, and don't recurse down
    # "special" directories
    if ( -l $_ ) { return; }
    if ( -d $_ ) {
        if ((/\.svn/) || (/\.deps/) || (/\.libs/) || (/autom4te\.cache/)) {
            $File::Find::prune = 1;
        }
        return;
    }

    # $File::Find::name is the path relative to the starting point.
    # $_ contains the file's basename.  The code automatically changes
    # to the processed directory, so we want to examine $_.
    push(@find_executables_data, $File::Find::name)
        if ( (-x $_) and ($_ =~ /$find_executables_template/));
}


#--------------------------------------------------------------------------

# Traverse a tree (or a bunch of trees) and return all the Java
# executables found (i.e., *.class)
my @find_java_executables_data;
sub find_java_executables {
    my $array = get_array_ref(\@_);
    Debug("&find_java_executables got @$array\n");

    @find_java_executables_data = ();
    my @dirs;
    foreach my $d (@$array) {
        push(@dirs, $d)
            if ("" ne $d);
    }
    File::Find::find(\&find_java_executables_sub, @dirs);

    Debug("&find_java_exectuables returning: @find_java_executables_data\n");
    return \@find_java_executables_data;
}

sub find_java_executables_sub {
    # Don't process directories and links, and don't recurse down
    # "special" directories
    if ( -l $_ ) { return; }
    if ( -d $_ ) { 
        if ((/\.svn/) || (/\.deps/) || (/\.libs/) || (/autom4te\.cache/)) {
            $File::Find::prune = 1;
        }
        return;
    }

    # $File::Find::name is the path relative to the starting point.
    # $_ contains the file's basename.  The code automatically changes
    # to the processed directory, so we want to examine $_.
    if ($_ =~ /.class$/) {
        my $class = $_;
        $class =~ s/.class$//;
        my $classpath = $File::Find::dir;
        push(@find_java_executables_data, "-classpath $classpath $class");
    }
}

#--------------------------------------------------------------------------

sub java_executable {
    my $array = get_array_ref(\@_);
    Debug("&java_executable got @$array\n");

    my @ret;
    foreach my $name (@$array) {
        if (-r "$name.class") {
            my $str;
            my $d = dirname($name);
            if ($d ne ".") {
                $str = "-classpath $d ";
            }
            $str .= basename($name);
            push(@ret, $str);
        }
    }

    Debug("&java_exectuable returning: @ret\n");
    return \@ret;
}

#--------------------------------------------------------------------------

# Traverse a tree (or a bunch of trees) and return all the files
# matching a regexp
my @find_data;
my $find_regexp;
sub find {
    my $array = get_array_ref(\@_);
    Debug("&find got @$array\n");

    $find_regexp = shift(@$array);
    @find_data = ();
    my @dirs;
    foreach my $d (@$array) {
        push(@dirs, $d)
            if ("" ne $d);
    }
    File::Find::find(\&find_sub, @dirs);

    Debug("&find returning: @find_data\n");
    return \@find_data;
}

sub find_sub {
    # Don't process directories and links, and don't recurse down
    # "special" directories
    if ( -l $_ ) { return; }
    if ( -d $_ ) { 
        if ((/\.svn/) || (/\.deps/) || (/\.libs/) || (/autom4te\.cache/)) {
            $File::Find::prune = 1;
        }
        return;
    }

    # $File::Find::name is the path relative to the starting point.
    # $_ contains the file's basename.  The code automatically changes
    # to the processed directory, so we want to examine $_.
    push(@find_data, $File::Find::name)
        if ($File::Find::name =~ $find_regexp);
}

#--------------------------------------------------------------------------

sub pwd_mtt
{
    my $t_var = $0;
    $t_var =~ s/\/[^\/]+$//;
    return $t_var;
}

# return File::Basename::dirname()
sub dirname {
    my($str) = @_;
    return File::Basename::dirname($str);
}

# return cwd()
sub cwd {
    return MTT::DoCommand::cwd();
}

# return cwd()
sub pwd {
    return MTT::Functions::cwd();
}

# Just like the "which" shell command
sub which {
    my ($str) = @_;
    my @arr = split(/ /, $str);
    return FindProgram(@arr);
}

# return File::Basename::basename()
sub basename {
    my($str) = @_;
    return File::Basename::basename($str);
}

# return Sys::Hostname::hostname()
sub hostname {
    return Sys::Hostname::hostname();
}

#--------------------------------------------------------------------------

# Deprecated name for env_max_procs
sub rm_max_procs {
    Warning("You are using a deprecated funclet name in your INI file: &rm_max_procs().  Please update to use the new functlet name: &env_max_procs().  This old name will disappear someday.\n");
    return env_max_procs();
}

#--------------------------------------------------------------------------

# Return the name of the run-time enviornment that we're using.  The
# only difference between rm_name() and env_name() is that env_name()
# may also return "hostlist" or "hostfile", whereas rm_name() will
# return "none" for those cases (because there is no resource
# manager).
sub rm_name {
    Debug("&rm_name\n");

    my $ret = env_name();
    return "none"
        if ("hostlist" eq $ret || "hostfile" eq $ret);

    return $ret;
}

#--------------------------------------------------------------------------

# Return the name of the run-time enviornment that we're using
sub env_name {
    Debug("&env_name\n");

    # Resource managers
    return "SLURM"
        if slurm_job();
    return "ALPS"
        if alps_job();
    return "TM"
        if pbs_job();
    return "SGE"
        if n1ge_job();
    return "loadleveler"
        if loadleveler_job();

    # Hostfile
    return "hostfile"
        if have_hostfile();

    # Hostlist
    return "hostlist"
        if have_hostlist();

    # No clue, Jack...
    return "unknown";
}

#--------------------------------------------------------------------------

# Find the max procs that we can run with.  Check several things in
# order:
#
# - Various resource managers
# - if a global hostfile was specified
# - if a global hostlist was specified
# - if a global max_np was specified
#
# If none of those things are found, return "2".
sub env_max_procs {
    Debug("&env_max_procs\n");

    # Manual specification of max_np
    return ini_max_procs()
        if have_ini_max_procs();

    # Resource managers
    return slurm_max_procs()
        if slurm_job();
    return alps_max_procs()
        if alps_job();
    return pbs_max_procs()
        if pbs_job();
    return n1ge_max_procs()
        if n1ge_job();
    return loadleveler_max_procs()
        if loadleveler_job();

    # Hostfile
    return hostfile_max_procs()
        if have_hostfile();

    # Hostlist
    return hostlist_max_procs()
        if have_hostlist();

    # Not running under anything; just return 2.
    return "2";
}

#--------------------------------------------------------------------------

# Find the max number of hosts that we can run with. 
sub env_max_hosts {
    Debug("&env_max_hosts\n");

    my $hosts = env_hosts(1);
    my @hosts = split(/,/, $hosts);
    Debug("&env_max_hosts: returning " . $#hosts + 1 . "\n");
    return $#hosts + 1;
}

#--------------------------------------------------------------------------

# Find the hosts that we can run with
# env_hosts(1) - returns uniq host list
# env_hosts(2) - returns uniq host list, keeps order of list items
# env_hosts(3) - returns uniq host list, group by hosts with number of cpu: host1:8,host2:8 and etc
#
sub env_hosts {
    my ($want_unique, $sep) = @_;
    Debug("&env_hosts: want_unique=$want_unique\n");

    # Resource managers
    my $ret;
    if (slurm_job()) {
        $ret = slurm_hosts();
    } elsif (alps_job()) {
        $ret = alps_hosts();
    } elsif (pbs_job()) {
        $ret = pbs_hosts();
    } elsif (n1ge_job()) {
        $ret = n1ge_hosts();
    } elsif (loadleveler_job()) {
        $ret = loadleveler_hosts();
    }

    # Hostfile
    elsif (have_hostfile()) {
        $ret = hostfile_hosts();
    }

    # Hostlist
    elsif (have_hostlist()) {
        $ret = hostlist_hosts();
    }

    # Not running under anything; just return the localhost name
    else {
        my $ret = `hostname`;
        chomp($ret);
    }

    # Do we need to uniq-ify the list?
    if ($want_unique) {
        my @h = split(/,/, $ret);
        my %hmap;
        my @hlist;
        foreach my $h (@h) {
            push( @hlist, $h ) if (!defined($hmap{$h}));
            $hmap{$h} = 0 unless defined($hmap{$h});
            $hmap{$h} = $hmap{$h} + 1;
        }

        # Do we want to keep order of result?
        if ( $want_unique == 3 ) {
            my @hlist_with_cpu;
            foreach my $h (@hlist) {
                push ( @hlist_with_cpu, $h.":".$hmap{$h} );
            }
            $ret = join(',', @hlist_with_cpu);
        }
        elsif ( $want_unique == 2 ) {
            $ret = join(',', @hlist);
        } else {
            $ret = join(',', keys(%hmap));
        }
    }

    if ($sep) {
        $ret =~ s/,/$sep/g;
    }

    Debug("&env_hosts returning: $ret\n");
    return "$ret";
}


#--------------------------------------------------------------------------

# Return "1" if we have a hostfile; "0" otherwise
sub have_hostfile {
    my $ret = (defined $MTT::Globals::Values->{hostfile}) ? "1" : "0";
    Debug("&have_hostfile returning $ret\n");
    return $ret;
}

#--------------------------------------------------------------------------

# If we have a hostfile, return it.  Otherwise, return the empty string.
sub hostfile {
    Debug("&hostfile: $MTT::Globals::Values->{hostfile}\n");

    if (have_hostfile) {
        return $MTT::Globals::Values->{hostfile};
    } else {
        return "";
    }
}

#--------------------------------------------------------------------------

# If we have a hostfile, return its max procs count
sub hostfile_max_procs {
    Debug("&hostfile_max_procs\n");

    return "0"
        if (!have_hostfile());

    Debug("&hostfile_max_procs returning $MTT::Globals::Values->{hostfile_max_np}\n");
    return $MTT::Globals::Values->{hostfile_max_np};
}

#--------------------------------------------------------------------------

# If we have a hostfile, return its hosts
sub hostfile_hosts {
    Debug("&hostfile_hosts\n");

    return ""
        if (!have_hostfile());

    # Return the uniq'ed contents of the hostfile

    open (FILE, $MTT::Globals::Values->{hostfile}) || return "";
    my $lines;
    while (<FILE>) {
        chomp;
        $lines->{$_} = 1;
    }

    my @hosts = sort(keys(%$lines));
    my $hosts = join(",", @hosts);
    Debug("&hostfile_hosts returning $hosts\n");
    return "$hosts";
}

#--------------------------------------------------------------------------

# Return "1" if we have a hostfile; "0" otherwise
sub have_hostlist {
    my $ret = 
        (defined $MTT::Globals::Values->{hostlist} &&
         $MTT::Globals::Values->{hostlist} ne "") ? "1" : "0";
    Debug("&have_hostlist: returning $ret\n");
    return $ret;
}

#--------------------------------------------------------------------------

# If we have a hostlist, return it.  Otherwise, return the empty string.
sub hostlist {
    Debug("&hostlist: $MTT::Globals::Values->{hostlist}\n");

    return hostlist_hosts(@_);
}

#--------------------------------------------------------------------------

# If we have a hostlist, return its max procs count
sub hostlist_max_procs {
    Debug("&hostlist_max_procs\n");

    return "0"
        if (!have_hostlist());

    Debug("&hostlist_max_procs returning $MTT::Globals::Values->{hostlist_max_np}\n");
    return $MTT::Globals::Values->{hostlist_max_np};
}

#--------------------------------------------------------------------------

# If we have a hostlist, return its hosts
sub hostlist_hosts {
    Debug("&hostlist_hosts\n");
    my $delimiter = shift;
    my $num = shift;

    return ""
        if (!have_hostlist());

    my $list;

    if (defined($num)) {
        my @hl = split(/,/, $MTT::Globals::Values->{hostlist});
        $list = join(",", splice(@hl, 0, $num));
    } else {
        $list = $MTT::Globals::Values->{hostlist};
    }
    
    if (defined($delimiter)) {
        my @hosts = split(/,/, $list);
        my $ret = join($delimiter, @hosts);
        Debug("&hostlist_hosts (delimiter=$delimiter) returning $ret\n");
        return $ret;
    } else {
        Debug("&hostlist_hosts returning $list\n");
        return $list;
    }
}

#--------------------------------------------------------------------------

# Return "1" if we have an "max_procs" setting in the globals in the
# INI file; "0" otherwise
sub have_ini_max_procs {
    Debug("&have_ini_max_procs\n");

    return (defined($MTT::Globals::Values->{max_np}) &&
            int($MTT::Globals::Values->{max_np}) > 0 &&
            exists($MTT::Globals::Values->{max_np})) ? "1" : "0";
}

#--------------------------------------------------------------------------

# If we have a hostlist, return its max procs count
sub ini_max_procs {
    Debug("&ini_max_procs\n");

    return "0"
        if (!have_ini_max_procs());

    Debug("&ini_max_procs returning $MTT::Globals::Values->{max_np}\n");
    return $MTT::Globals::Values->{max_np};
}

#--------------------------------------------------------------------------

# Return "1" if we're running in a SLURM job; "0" otherwise.
sub slurm_job {
    Debug("&slurm_job\n");

    return ((exists($ENV{SLURM_JOBID}) &&
             exists($ENV{SLURM_TASKS_PER_NODE})) ? "1" : "0");
}

#--------------------------------------------------------------------------

# If in a SLURM job, return the max number of processes we can run.
# Otherwise, return 0.
sub slurm_max_procs {
    Debug("&slurm_max_procs\n");

    return "0"
        if (!slurm_job());

    # The SLURM env variable SLURM_TASKS_PER_NODE is a comma-delimited
    # list of strings.  Each string is of the form:
    # <tasks>[(x<nodes>)].  If the "(x<nodes>)" portion is not
    # specified, the <nodes> value is 1.

    my $max_procs = 0;
    my @tpn = split(/,/, $ENV{SLURM_TASKS_PER_NODE});
    my $tasks;
    my $nodes;
    foreach my $t (@tpn) {
        if ($t =~ m/(\d+)\(x(\d+)\)/) {
            $tasks = $1;
            $nodes = $2;
        } elsif ($t =~ m/(\d+)/) {
            $tasks = $1;
            $nodes = 1;
        } else {
            Warning("Unparsable SLURM_TASKS_PER_NODE: $ENV{SLURM_TASKS_PER_NODE}\n");
            return "0";
        }

        $max_procs += $tasks * $nodes;
    }

    Debug("&slurm_max_procs returning: $max_procs\n");
    return "$max_procs";
}

#--------------------------------------------------------------------------

# If in a SLURM job, return the hosts we can run on.  Otherwise,
# return "".
sub slurm_hosts {
    Debug("&slurm_hosts\n");

    return ""
        if (!slurm_job());

    # The SLURM env variable SLURM_NODELIST is a regexp of the hosts
    # we can run on.  Need to convert it to a comma-delimited list of
    # hosts; each host repeated as many times as dictated by the
    # corresponding entry in SLURM_TASKS_PER_NODE (see description of
    # SLURM_TASKS_PER_NODE in slurm_max_procs()).
    #
    # SLURM_NODELIST is a comma-delimited list of regular expressions.
    # Each entry will be of the form: base[ranges] (square brackets
    # are literal), where ranges is, itself, a comma-delimtied list of
    # ranges.  Each entry in ranges will be of the form: N[-M], where
    # N and M are integers, and the brackets are not literal (i.e.,
    # it'll be "N" or "N-M").

    # First, build a fully expanded list of task counts per node (see
    # slurm_max_procs() for a description of the format of
    # ENV{SLURM_TASKS_PER_NDOE}).

    my @tasks_per_node;
    my @tpn = split(/,/, $ENV{SLURM_TASKS_PER_NODE});
    foreach my $t (@tpn) {
        my $tasks;
        my $nodes;
        if ($t =~ m/(\d+)\(x(\d+)\)/) {
            $tasks = $1;
            $nodes = $2;
        } elsif ($t =~ m/(\d+)/) {
            $tasks = $1;
            $nodes = 1;
        } else {
            Warning("Unparsable SLURM_TASKS_PER_NODE: $ENV{SLURM_TASKS_PER_NODE}\n");
            return "";
        }

        while ($nodes > 0) {
            push(@tasks_per_node, $tasks);
            --$nodes;
        }
    }

    # Next, built a list of all nodes

    my @nodes;
    my $str = $ENV{SLURM_NODELIST};
    Debug("Parsing SLURM_NODELIST: $ENV{SLURM_NODELIST}\n");
    while ($str) {
        my $next_str;

        # See if we've got a "foo[ranges]" at the head of the string.
        # Be sure to be non-greedy in this regexp to grab only the
        # *first* part of the strgin!
        if ($str =~ m/^(.+?)\[([0-9\,\-]+?)\](.*)$/) {
            $next_str = $3;
            my $base = $1;
            Debug("Range: $1 - $2\n");
            # Parse the ranges
            my @ranges = split(/,/, $2);
            foreach my $r (@ranges) {
                if ($r =~ m/(\d+)-(\d+)/) {
                    # Got a start-finish range
                    my $str_len = length($1);
                    my $i = int($1);
                    my $end = int($2);
                    while ($i <= $end) {
                        my $num = $i;
                        $num = "0" . $num
                            while (length($num) < $str_len);
                        push(@nodes, "$base$num");
                        ++$i;
                    }
                } elsif ($r =~ m/^(\d+)$/) {
                    # Got a single number
                    push(@nodes, "$base$1");
                } else {
                    # Got an unexpected string
                    Warning("Unparsable SLURM_NODELIST: $ENV{SLURM_NODELIST}\n");
                    return "";
                }
            }
        } elsif ($str =~ m/^([^,]+)(.*)$/) {
            $next_str = $2;
            # No range; just a naked host -- save it and move on
            Debug("Naked host: ($str) $1\n");
            push(@nodes, $1);
        } else {
            Warning("Unparsable SLURM_NODELIST: $ENV{SLURM_NODELIST}\n");
            return "";
        }

        # Chop off the front of the string that we've already
        # processed and continue on.  Ensure that it starts with a ,
        # and then chop that off, too.
        $str = $next_str;
        Debug("Almost next: $str\n");
        if ($str && $str !~ s/^,(.+)/\1/) {
            Warning("Unparsable SLURM_NODELIST: $ENV{SLURM_NODELIST}\n");
            return "";
        }

        Debug("Next item: $str\n");
    }

    # Now combine the two lists -- they should be exactly the same
    # length.  Repeat each host as many times at it has tasks.

    my $ret;
    my $i = 0;
    while ($i <= $#tasks_per_node) {
        my $j = $tasks_per_node[$i];
        while ($j > 0) {
            $ret .= ","
                if ($ret);
            $ret .= $nodes[$i];
            --$j;
        }
        ++$i;
    }

    Debug("&slurm_max_procs returning: $ret\n");
    return $ret;
}


# Extract PPN from slurm allocation
#
sub slurm_ppn {

    my @tpn = split(/,/, $ENV{SLURM_TASKS_PER_NODE});
    foreach my $t (@tpn) {
        my $tasks;
        my $nodes;
        if ($t =~ m/(\d+)\(x(\d+)\)/) {
            $tasks = $1;
            $nodes = $2;
        } elsif ($t =~ m/(\d+)/) {
            $tasks = $1;
            $nodes = 1;
        } else {
            Warning("Unparsable SLURM_TASKS_PER_NODE: $ENV{SLURM_TASKS_PER_NODE}\n");
            return "";
        }
        return $tasks;
    }
    Warning("Unable extract ppn\n");
    return "";
}

sub slurm_np_from_nnodes {
    my ($nnodes) = @_;

    return slurm_ppn() * $nnodes;
}

#--------------------------------------------------------------------------

# Return "1" if we're running in an ALPS job; "0" otherwise.
sub alps_job {
    Debug("&alps_job\n");

#   It is true that ALPS can be run in an interactive access mode; however,
#   this would not be a true managed environment.  Such only can be
#   achieved under a batch scheduler.
#   Since cray changed the CLE2.1, BATCH_PARTITION_ID is not valid anymore, therefore
#   check for anything, that ALPS' aprun may take...
    return (((exists($ENV{BATCH_PARTITION_ID}) &&
              exists($ENV{PBS_NNODES})) ||
              exists($ENV{APRUN_XFER_LIMITS})) ? "1" : "0");
}

#--------------------------------------------------------------------------

# If in an ALPS job, return the max number of processes we can run.
# Otherwise, return 0.
sub alps_max_procs {
    Debug("&alps_max_procs\n");

    return "0"
        if (!alps_job());

#   If we were not running under PBS or some other batch system, we would
#   not have the foggiest idea of how many processes mpirun could spawn.
    my $ret;
    $ret=$ENV{PBS_NNODES};

    Debug("&alps_max_procs returning: $ret\n");
    return "$ret";
}

#--------------------------------------------------------------------------

# If in an ALPS job, return the hosts we can run on.  Otherwise, return
# "".
sub alps_hosts {
    Debug("&alps_hosts\n");

    return ""
        if (!alps_job());

#   Again, we need a batch system to achieve management; return the uniq'ed
#   contents of $PBS_HOSTFILE.  Actually, on the Cray XT, we can return the
#   NIDS allocated by ALPS; but, without launching servers to other service
#   nodes, all communication is via the launching node and NIDS actually
#   have no persistent resource allocated to the user.  That is, all file
#   resources accessible from a NID are shared with the launching node.  
#   And, since ALPS is managed by the batch system, only the launching node
#   can initiate communication with a NID.  In effect, the Cray XT model is
#   of a single service node with a varying number of compute processors.
    open (FILE, $ENV{PBS_NODEFILE}) || return "";
    my $lines;
    while (<FILE>) {
        chomp;
        $lines->{$_} = 1;
    }

    my @hosts = sort(keys(%$lines));
    my $hosts = join(",", @hosts);
    Debug("&alps_hosts returning: $hosts\n");
    return "$hosts";
}

#--------------------------------------------------------------------------

# Return "1" if we're running in a PBS job; "0" otherwise.
sub pbs_job {
    Debug("&pbs_job\n");

    return ((exists($ENV{PBS_JOBID}) &&
             exists($ENV{PBS_ENVIRONMENT})) ? "1" : "0");
}

#--------------------------------------------------------------------------

# If in a PBS job, return the max number of processes we can run.
# Otherwise, return 0.
sub pbs_max_procs {
    Debug("&pbs_max_procs\n");

    return "0"
        if (!pbs_job());

    # Just count the number of lines in the $PBS_NODEFILE

    open (FILE, $ENV{PBS_NODEFILE}) || return "0";
    my $lines = 0;
    while (<FILE>) {
        ++$lines;
    }

    Debug("&pbs_max_procs returning: $lines\n");
    return "$lines";
}

#--------------------------------------------------------------------------

# If in a PBS job, return the hosts we can run on.  Otherwise, return
# "".
sub pbs_hosts {
    Debug("&pbs_hosts\n");

    return ""
        if (!pbs_job());

    # Return the uniq'ed contents of $PBS_HOSTFILE

    open (FILE, $ENV{PBS_NODEFILE}) || return "";
    my $lines;
    while (<FILE>) {
        chomp;
        $lines->{$_} = 1;
    }

    my @hosts = sort(keys(%$lines));
    my $hosts = join(",", @hosts);
    Debug("&pbs_hosts returning: $hosts\n");
    return "$hosts";
}

#--------------------------------------------------------------------------

# Return "1" if we're running in a N1GE job; "0" otherwise.
sub n1ge_job {
    Debug("&n1ge_job\n");

    return (exists($ENV{JOB_ID}) ? "1" : "0");
}

#--------------------------------------------------------------------------

# If in a N1GE job, return the max number of processes we can run.
# Otherwise, return 0.
sub n1ge_max_procs {
    Debug("&n1ge_max_procs\n");

    return "0"
        if (!n1ge_job());

    # Just count the number of lines in the $PE_HOSTFILE

    open (FILE, $ENV{PE_HOSTFILE}) || return "0";
    my $lines = 0;
    while (<FILE>) {
        ++$lines;
    }

    Debug("&n1ge_max_procs returning: $lines\n");
    return "$lines";
}

#--------------------------------------------------------------------------

# If in a N1GE job, return the hosts we can run on.
# Otherwise, return "".
sub n1ge_hosts {
    Debug("&n1ge_hosts\n");

    return ""
        if (!n1ge_job());

    # Return the uniq'ed contents of $PE_HOSTFILE

    open (FILE, $ENV{PE_HOSTFILE}) || return "";
    my $lines;
    while (<FILE>) {
        chomp;
        $lines->{$_} = 1;
    }

    my @hosts = sort(keys(%$lines));
    my $hosts = join(",", @hosts);
    Debug("&n1ge_hosts returning: $hosts\n");
    return "$hosts";
}

#--------------------------------------------------------------------------

# SGE and N1GE are the same package
sub sge_job {
    return n1ge_job(@_);
}
sub sge_max_procs {
    return n1ge_max_procs(@_);
}
sub sge_hosts {
    return n1ge_hosts(@_);
}

#--------------------------------------------------------------------------

# Return "1" if we're running in a Load Leveler job; "0" otherwise.
sub loadleveler_job {
    Debug("&loadleveler_job\n");

    return (exists($ENV{LOADLBATCH}) ? "1" : "0");
}

#--------------------------------------------------------------------------

# If in a Load Leveler job, return the max number of processes we can
# run.  Otherwise, return 0.
sub loadleveler_max_procs {
    Debug("&loadleveler_max_procs\n");

    return "0"
        if (!loadleveler_job());

    # Just count the number of tokens in $LOADL_PROCESSOR_LIST

    my $ret = 2;
    if (exists($ENV{LOADL_PROCESSOR_LIST}) && 
        $ENV{LOADL_PROCESSOR_LIST} ne "") {
      my @hosts = split(/ /, $ENV{LOADL_PROCESSOR_LIST});
      $ret = $#hosts + 1;
    }

    Debug("&loadleveler_max_procs returning: $ret\n");
    return $ret;
}


#--------------------------------------------------------------------------

# If in a Load Leveler job, return the hosts we can run on.
# Otherwise, return "".
sub loadleveler_hosts {
    Debug("&loadleveler_hosts\n");

    return ""
        if (!loadleveler_job());
    return ""
        if (!exists($ENV{LOADL_PROCESSOR_LIST}) ||
            "" eq $ENV{LOADL_PROCESSOR_LIST});

    # Just uniq the tokens in $LOADL_PROCESSOR_LIST

    my @tokens = split(/ /, $ENV{LOADL_PROCESSOR_LIST});
    my $tokens;
    foreach my $t (@tokens) {
        $tokens->{$t} = 1;
    }

    my @hosts = sort(keys(%$tokens));
    my $hosts = join(",", @hosts);
    Debug("&loadleveler_hosts returning: $hosts\n");
    return "$hosts";
}


#--------------------------------------------------------------------------

# Return the version of the GNU C compiler
sub get_gcc_version {
    Debug("&get_gcc_version\n");
    my $gcc = shift;
    my $ret = "unknown";

    $gcc = "gcc"
        if (!defined($gcc));
    if (open GCC, "$gcc --version|") {
        my $str = <GCC>;
        close(GCC);
        chomp($str);

        my @vals = split(" ", $str);
        $ret = $vals[2];
    }
    
    Debug("&get_gcc_version returning: $ret\n");
    return $ret;
}

#--------------------------------------------------------------------------

# Return the version of the Clang compiler
sub get_clang_version {
    Debug("&get_clang_version\n");
    my $clang = shift;
    my $ret = "unknown";

    $clang = "clang"
        if (!defined($clang));
    if (open CLANG, "$clang --version|") {
        my $str = <CLANG>;
        close(CLANG);
        chomp($str);

        my @vals = split(" ", $str);
        $ret = $vals[2];
    }
    
    Debug("&get_clang_version returning: $ret\n");
    return $ret;
}

#--------------------------------------------------------------------------

# Return the version of the Intel C compiler
sub get_icc_version {
    Debug("&get_icc_version\n");
    my $icc = shift;
    my $ret = "unknown";

    $icc = "icc"
        if (!defined($icc));
    if (open ICC, "$icc --version|") {
        my $str = <ICC>;
        close(ICC);
        chomp($str);

        my @vals = split(" ", $str);
        $ret = "$vals[2] $vals[3]";
    }
    
    Debug("&get_icc_version returning: $ret\n");
    return $ret;
}

#--------------------------------------------------------------------------

# Return the version of the PGI C compiler
sub get_pgcc_version {
    Debug("&get_pgcc_version\n");
    my $pgcc = shift;
    my $ret = "unknown";

    $pgcc = "pgcc"
        if (!defined($pgcc));
    if (open PGCC, "$pgcc -V|") {
        my $str = <PGCC>;
        $str = <PGCC>;
        close(PGCC);
        chomp($str);

        my @vals = split(" ", $str);
        $ret = "$vals[1] ($vals[2] $vals[5] $vals[6])";
    }
    
    Debug("&get_pgcc_version returning: $ret\n");
    return $ret;
}

#--------------------------------------------------------------------------

# Return the version of the Sun Studio C compiler
sub get_sun_cc_version {
    Debug("&get_sun_cc_version\n");
    my $cc = shift;
    $cc = "cc"
        if (!defined($cc));

    my $cc_v;
    my $version;
    my $date;

    $cc_v = `$cc -V 2>\&1 | head -1`;

    $cc_v =~ m/(\b5.\d+\b)/;
    $version = $1;

    $cc_v =~ m/(\d+\/\d+\/\d+)/;
    $date = $1;

    my $ret = "$version $date";

    Debug("&get_sun_cc_version returning: $ret\n");
    return $ret;
}

#--------------------------------------------------------------------------

# Return the version of the Pathscale C compiler
sub get_pathcc_version {
    Debug("&get_pathcc_version\n");
    my $pathcc = shift;
    my $ret = "unknown";

    $pathcc = "pathcc"
        if (!defined($pathcc));
    if (open PATHCC, "$pathcc -dumpversion|") {
        $ret = <PATHCC>;
        close(PATHCC);
        chomp($ret);
    }
    
    Debug("&get_pathcc_version returning: $ret\n");
    return $ret;
}

#--------------------------------------------------------------------------

# Return the version of the Absoft Fortran compiler
sub get_absoft_version {
    Debug("&get_absoft_version\n");
    my $ret = "unknown";

    if (defined($ENV{ABSOFT}) && -r "$ENV{ABSOFT}/absoft_release") {
        my $file = cat("$ENV{ABSOFT}/absoft_release");
        $ret = join(/ /, @$file);
    }
    
    Debug("&get_absoft_version returning: $ret\n");
    return $ret;
}

#--------------------------------------------------------------------------

# Return the source directory
sub get_mpi_srcdir {
    my $srcdir = $MTT::MPI::Install::src_dir;
    return $srcdir;
}

# Return the build directory
sub get_mpi_builddir {
    my $builddir = $MTT::MPI::Install::build_directory;
    return $builddir;
}

sub get_mpi_install_dir 
{
    my $builddir = $MTT::MPI::Install::install_dir;
    return $builddir;
}
# Detect the bitness of the MPI library in this order:
#   1) User overridden (CSV of 1 or more valid bitnesses)
#   2) Small test C program (using void*)
#   3) /usr/bin/file command output
#
# Return a database-ready bitmapped value
sub get_mpi_install_bitness {
    Debug("&get_mpi_install_bitness got @_\n");

    my $override    = shift;
    my $install_dir = $MTT::MPI::Install::install_dir;
    my $force       = 1;
    my $ret         = "0";

    # 1)
    # Users can override the automatic bitness detection
    # (useful in cases where the MPI has multiple bitnesses
    # e.g., Sun packages or Mac OSX universal binaries)
    if ($override) {
        $ret = _bitness_to_bitmapped($override);
        Debug("&get_mpi_install_bitness returning: $ret\n");
        return $ret;
    }

    # 2)
    # Write out a simple C program to output the bitness
    my $prog_name  = "get_bitness_c";
    my $executable = "$install_dir/$prog_name";
    my $mpicc      = "$install_dir/bin/mpicc";
    my $mpirun     = "$install_dir/bin/mpirun";

    # Make sure we have a valid mpicc and mpirun before attempting
    # this
    if (-x $mpicc && -x $mpirun) {
        my $x = MTT::Files::SafeWrite($force, "$executable.c", "/*
 * This program is automatically generated via the \"get_bitness\"
 * function of the MPI Testing Tool (MTT).  Any changes you make here may
 * get lost!
 *
 * Copyrights and licenses of this file are the same as for the MTT.
 */

#include <stdio.h>

int main(int argc, char* argv[]) {
    printf(\"%d\\n\", sizeof(void *) * 8);
    return 0;
}
");

        # Compile the program
        unlink($executable);
        $x = MTT::DoCommand::Cmd(1, "$mpicc $executable.c -o $executable");

        if (0 == $x->{exit_value} && -x $executable) {

            # It compiled ok, so now run it.  Use mpirun so that
            # various paths and whatnot are set properly.
            $x = MTT::DoCommand::Cmd(1, "$mpirun -np 1 $executable", 30);

            # Remove the get_bitness program and source
            unlink($executable);
            unlink("$executable.c");

            if (0 == $x->{exit_value}) {
                $ret = _extract_valid_bitness($x->{result_stdout});

                if (! $ret) {
                    Warning("&get_mpi_install_bitness(): Sample compiled program $prog_name did not execute properly.\n");
                    Warning("&get_mpi_install_bitness(): $prog_name output: " . $x->{result_stdout} . "\n");
                } else {
                    Debug("$prog_name executed properly.\n");
                    $ret = _bitness_to_bitmapped($ret);
                    Debug("&get_mpi_install_bitness returning: $ret\n");
                    return $ret;
                }
            } else {
                Warning("&get_mpi_install_bitness(): Couldn't execute sample compiled program: $prog_name.\n");
            }
        } else {
            Warning("&get_mpi_install_bitness(): Couldn't compile sample $prog_name.c.\n");
        }
    }

    # 3)
    # Try snarfing bitness using the /usr/bin/file command
    my $libmpi = _find_libmpi();
    if (! -f $libmpi) {
        Debug("Couldn't find libmpi!\n");
        return "0";
    }

    my $leader = "[^:]+:";
    my $bitnesses;

    # Split up file command's output
    my @file_out = split /\n/, `file $libmpi`;

    foreach my $line (@file_out) {

        # Mac OSX *implies* 32-bit for ppc and i386
        if ($line =~ /$leader.*\bmach-o\b.*\b(?:ppc|i386)\b/i) {
            $bitnesses->{32} = 1;

        # 64-bit
        } elsif ($line =~ /$leader.*\b64-bit\b/i) {
            $bitnesses->{64} = 1;

        # 32-bit
        } elsif ($line =~ /$leader.*\b32-bit\b/i) {
            $bitnesses->{32} = 1;
        }
    }

    # Compose CSV of bitness(es)
    my $str = join(',', keys %{$bitnesses});

    $ret = _extract_valid_bitness($str);

    if (! defined($ret)) {
        Warning("Could not get bitness using \"file\" command.\n");
    } else {
        Debug("Got bitness using \"file\" command.\n");
    }

    $ret = _bitness_to_bitmapped($ret);
    Debug("&get_mpi_install_bitness returning: $ret\n");

    return $ret;
}

# Make sure the bitness value makes sense
sub _extract_valid_bitness {

    my $str = shift;
    my $ret;

    Debug("Validating bitness string ($str)\n");

    # Valid bitnesses
    my $v = "8|16|32|64|128";

    # CSV of one or more bitnesses
    if ($str =~ /^((?:$v) (?:\s*,\s*(?:$v))*)$/x) {
        $ret = $1;
    } else {
        $ret = undef;
    }

    return $ret;
}

# Convert the human-readable CSV of bitness(es) to
# its representation in the MTT database.
sub _bitness_to_bitmapped {

    my $csv = shift;
    my $ret = 0;
    my $shift;

    Debug("Converting bitness string ($csv) to a bitmapped value\n");

    return $ret if (! $csv);

    my @bitnesses = split(/,/, $csv);

    # Smallest bitness possible
    my $smallest = 8;

    # Generate a bitmap of all bitnesses
    foreach my $bitness (@bitnesses) {
        $shift = log($bitness)/log(2) - log($smallest)/log(2);
        $ret |= (1 << $shift);
    }

    return $ret;
}

#--------------------------------------------------------------------------

# Return a database-ready bitmapped value for endian-ness
sub get_mpi_install_endian {
    Debug("&get_mpi_intall_endian\n");

    my $override = shift;
    my $ret      = "0";

    # 1)
    # Users can override the automatic endian detection
    # (useful in cases where the MPI has multiple endians
    # e.g., Mac OSX universal binaries)
    if ($override) {
        $ret = _endian_to_bitmapped($override);

        Debug("&get_mpi_install_endian returning: $ret\n");
        return $ret;
    }


    # 2)
    # Try snarfing endian(s) using the /usr/bin/file command
    my $libmpi          = _find_libmpi();
    if (! -f $libmpi) {
        # No need to Warning() -- the fact that the MPI failed to install
        # should be good enough...
        Debug("*** Could not find libmpi to calculate endian-ness\n");
        return "0";
    }

    my $leader          = "[^:]+:";
    my $hardware_little = 'i386|x86_64';
    my $hardware_big    = 'ppc|ppc64';
    my $endians;

    # Split up file command's output
    my @file_out = split /\n/, `file $libmpi`;

    foreach my $line (@file_out) {

        # Mac OSX
        if ($line =~ /$leader.*\bmach-o\b.*(?:$hardware_little)\b/i) {
            $endians->{little} = 1;

        # Mac OSX
        } elsif ($line =~ /$leader.*\bmach-o\b.*(?:$hardware_big)\b/i) {
            $endians->{big} = 1;

        # Look for 'MSB' (Most Significant Bit)
        } elsif ($line =~ /$leader.*\bMSB\b/i) {
            $endians->{big} = 1;

        # Look for 'LSB' (Least Significant Bit)
        } elsif ($line =~ /$leader.*\bLSB\b/i) {
            $endians->{little} = 1;
        }
    }

    # Compose CSV of endian(s)
    my $str = join(',', keys %{$endians});

    $ret = _endian_to_bitmapped($str);

    if (! $ret) {
        Debug("Could not get endian-ness from $libmpi using \"file\" command.\n");
    } else {
        Debug("Got endian-ness using \"file\" command on $libmpi.\n");
        return $ret;
    }

    # 3)
    # Auto-detect by casting an int to a char
    my $str = unpack('c2', pack('i', 1)) ? 'little' : 'big';
    $ret = _endian_to_bitmapped($str);

    Debug("&get_mpi_install_endianness returning: $ret\n");
    return $ret;
}

# Convert the human-readable CSV of endian(s) to
# its representation in the MTT database.
sub _endian_to_bitmapped {

    my $csv        = shift;
    my $ret        = 0;
    my $bit_little = 0;
    my $bit_big    = 1;

    Debug("Converting endian string ($csv) to a bitmapped value\n");

    return $ret if (! $csv);

    if ($csv =~ /little/i) {
        $ret |= $ret | (1 << $bit_little);
    }
    if ($csv =~ /big/i) {
        $ret |= $ret | (1 << $bit_big);
    }
    if ($csv =~ /both/i) {
        $ret |= $ret | (1 << $bit_little) | (1 << $bit_big);
    }

    Debug("&_endian_to_bitmapped returning: $ret\n");
    return $ret;
}

# Return the MPI library that will be passed to the file command
sub _find_libmpi {

    my $install_dir = $MTT::MPI::Install::install_dir;
    my $ret = undef;

    # Try to find a libmpi
    my @libmpis = (
        "$install_dir/lib/libmpi.dylib",
        "$install_dir/lib/libmpi.a",
        "$install_dir/lib/libmpi.so",
    );

    foreach my $libmpi (@libmpis) {
        if (-e $libmpi) {
            while (-l $libmpi) {
                $libmpi = readlink($libmpi);
                next if (-e $libmpi);
                $libmpi = "$install_dir/lib/$libmpi";
                next if (-e $libmpi);
                Warning("*** Got bogus sym link for libmpi -- points to nothing\n");
                return $ret;
            }

            $ret = $libmpi;
            last;
        }
    }

    Debug("&_find_libmpi returning: $ret\n");
    return $ret;
}

#--------------------------------------------------------------------------

# Determine the number of CPUs on the localhost
sub get_processor_count {

    my $psrinfo = "/usr/sbin/psrinfo";
    my $cpuinfo = "/proc/cpuinfo";
    my $count   = 0;
    my $ret;

    if (-x $psrinfo) {

        # Use the Solaris psrinfo command if it's there
        open(INFO, "$psrinfo -p|");
        $ret = <INFO>;
        chomp($ret);
        close(INFO);

    } elsif (-e $cpuinfo) {

        # $ cat /proc/cpuinfo
        # processor       : 0
        # vendor_id       : AuthenticAMD
        # cpu family      : 15
        # model           : 37
        # model name      : AMD Opteron(tm) Processor 252
        # stepping        : 1
        # cpu MHz         : 1000.000
        # cache size      : 1024 KB
        # fpu             : yes
        # fpu_exception   : yes
        # cpuid level     : 1
        # wp              : yes
        # flags           : fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca...
        # bogomips        : 1994.36
        # TLB size        : 1024 4K pages
        # clflush size    : 64
        # cache_alignment : 64
        # address sizes   : 40 bits physical, 48 bits virtual
        # power management: ts fid vid ttp
        # 
        # processor       : 1
        # vendor_id       : AuthenticAMD
        # cpu family      : 15
        # model           : 37
        # model name      : AMD Opteron(tm) Processor 252
        # stepping        : 1
        # cpu MHz         : 1000.000
        # cache size      : 1024 KB
        # fpu             : yes
        # fpu_exception   : yes
        # cpuid level     : 1
        # wp              : yes
        # flags           : fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca...
        # bogomips        : 1994.36
        # TLB size        : 1024 4K pages
        # clflush size    : 64
        # cache_alignment : 64
        # address sizes   : 40 bits physical, 48 bits virtual
        # power management: ts fid vid ttp

        open(INFO, $cpuinfo);

        while (<INFO>) {
            chomp;
            if (/^processor\s*\:\s*\d+\s*$/) {
                $count++;
            }
        }
        $ret = $count;

        close(INFO);

    } else {
        Debug("&get_processor_count could not determine the number of CPUs.\n");
        return undef;
    }

    Debug("&get_processor_count returning $ret.\n");
    return $ret;
}

#--------------------------------------------------------------------------

sub weekday_name {
    my @days = qw/sun mon tue wed thu fri sat/;
    Debug("&weekday_name returning: " . $days[weekday_index()] . "\n");
    return $days[weekday_index()];
}

# 0 = Sunday;
sub weekday_index {
    my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) =
        localtime(time);
    Debug("&weekday_index returning: $wday\n");
    return $wday;
}

#--------------------------------------------------------------------------

sub getenv {
    my $name = shift(@_);
    Debug("&getenv($name) returning: $ENV{$name}\n");
    return $ENV{$name};
}

#--------------------------------------------------------------------------

sub scratch_root {
    Debug("&scratch_root() returning: $MTT::Globals::Values->{scratch_root}\n");
    return $MTT::Globals::Values->{scratch_root};
}

#--------------------------------------------------------------------------

sub local_scratch_root {
    Debug("&local_scratch_root() returning: $MTT::Globals::Values->{local_scratch_root}\n");
    return $MTT::Globals::Values->{local_scratch_root};
}

#--------------------------------------------------------------------------

# Return something that will be snipped out of the final evaluation
sub null {
    Debug("&null returning: undef\n");
    return undef;
}

#--------------------------------------------------------------------------

sub mpi_get_name {
    Debug("&mpi_get_name returning: $MTT::Globals::Internals->{mpi_get_name}\n");
    return $MTT::Globals::Internals->{mpi_get_name};
}

sub _get_hash_keys {
    my ($pattern, $hash) = @_;

    my @ret;
    
    # Match everything if no pattern is supplied
    if (! defined($pattern)) {
        return keys %$hash;
    }

    my @ret;
    foreach my $key (keys %$hash) {
        if ($key =~ /$pattern/i) {
            push(@ret, $key);
        }
    }

    Debug("&_get_hash_keys returning: @ret\n");
    return \@ret;
}

# The below get INI section name command are especially useful in the case
# where a user is not concerned about multiplying "MPI Installs" times "MPI
# gets". In other words, it allows one to simplify this command:
#
#   $ client/mtt --section "install-foo" mpi_get=install-foo
# 
# Instead, leave out the mpi_get command-line override, and set 
# mpi_get like this in the INI:
#
#   mpi_get = &get_mpi_get_names()
#
sub get_mpi_get_names {
    my ($pattern) = @_;
    my @arr = _get_hash_keys($pattern, $MTT::MPI::sources);
    @arr = delete_duplicates_from_array(@arr);
    return join(",", @arr);
}

sub get_mpi_install_names {
    my ($pattern) = @_;

    my @arr;
    foreach my $mpi_get_key (keys %$MTT::MPI::installs) {

        my $mpi_get = $MTT::MPI::sources->{$mpi_get_key};
        foreach my $version_key (keys %{$mpi_get}) {
            push(@arr, _get_hash_keys($pattern, $mpi_get->{$version_key}));
        }
    }

    @arr = delete_duplicates_from_array(@arr);
    my $ret = join(",", @arr);
    return $ret;
}

sub get_test_get_names {
    my ($pattern) = @_;
    return _get_hash_keys($pattern, $MTT::Test::sources);
}

sub get_test_build_names {
    my ($pattern) = @_;

    my @arr;
    foreach my $mpi_get_key (keys %$MTT::Test::builds) {

        my $mpi_get = $MTT::MPI::sources->{$mpi_get_key};
        foreach my $mpi_get_key (keys %{$mpi_get}) {

            my $version = %{$mpi_get};
            foreach my $version_key (keys %{$version}) {

                my $mpi_install = $mpi_get->{$version_key};
                foreach my $build_key (keys %{$mpi_install}) {
                    push(@arr, _get_hash_keys($pattern, $mpi_install->{$build_key}));
                }
            }
        }
    }

    @arr = delete_duplicates_from_array(@arr);
    my $ret = join(",", @arr);
    return $ret;
}

sub get_test_run_names {
    my ($pattern) = @_;

    my @arr;
    foreach my $mpi_get_key (keys %$MTT::Test::builds) {

        my $mpi_get = $MTT::MPI::sources->{$mpi_get_key};
        foreach my $mpi_get_key (keys %{$mpi_get}) {

            my $version = %{$mpi_get};
            foreach my $version_key (keys %{$version}) {

                my $mpi_install = $mpi_get->{$version_key};
                foreach my $build_key (keys %{$mpi_install}) {

                    my $test_build = $mpi_get->{$version_key};
                    foreach my $build_key (keys %{$test_build}) {
                        push(@arr, _get_hash_keys($pattern, $test_build->{$build_key}));
                    }
                }
            }
        }
    }

    @arr = delete_duplicates_from_array(@arr);
    my $ret = join(",", @arr);
    return $ret;
}

#--------------------------------------------------------------------------

sub mpi_install_name {
    Debug("&mpi_install_name returning: $MTT::Globals::Internals->{mpi_install_name}\n");
    return $MTT::Globals::Internals->{mpi_install_name};
}

#--------------------------------------------------------------------------

sub test_get_name {
    Debug("&test_get_name returning: $MTT::Globals::Internals->{test_get_name}\n");
    return $MTT::Globals::Internals->{test_get_name};
}

#--------------------------------------------------------------------------

sub test_build_name {
    Debug("&test_build_name returning: $MTT::Globals::Internals->{test_build_name}\n");
    return $MTT::Globals::Internals->{test_build_name};
}

#--------------------------------------------------------------------------

sub test_run_name {
    Debug("&test_run_name returning: $MTT::Globals::Internals->{test_run_name}\n");
    return $MTT::Globals::Internals->{test_run_name};
}

#--------------------------------------------------------------------------

sub mpi_details_name {
    Debug("&mpi_details_name returning: $MTT::Globals::Internals->{mpi_details_name}\n");
    return $MTT::Globals::Internals->{mpi_details_name};
}

sub mpi_details_simple_name {
    Debug("&mpi_details_simple_name returning: $MTT::Globals::Internals->{mpi_details_simple_name}\n");
    return $MTT::Globals::Internals->{mpi_details_simple_name};
}

#--------------------------------------------------------------------------
#--------------------------------------------------------------------------
#--------------------------------------------------------------------------

sub current_phase {
    return $MTT::Globals::Values->{active_phase};
}

sub current_section {
    return $MTT::Globals::Values->{active_section};
}

sub current_simple_section {
    return GetSimpleSection($MTT::Globals::Values->{active_section});
}

# Perform a search and replace operation on a file
sub search_and_replace {
    my ($pattern, $replacement, $file) = @_;

    # Read in the file
    my $contents = MTT::Files::Slurp($file);

    # Search and replace. Use eval here in case there is 
    # a back-reference in the $replacement (e.g., $1, $2, ...)
    eval "\$contents =~ s/$pattern/$replacement/gi;";

    # Write out changed file
    my $x = MTT::Files::SafeWrite(1, $file, $contents);

    if (1 == $x->{success}) {
        return 1;
    } else {
        return 0;
    }
}

# Return true if there are some .z VampirTrace files in
# the cwd
sub vampir_trace_files_exist {
    my @exts = ("*.events.z", "*.def.z");

    my @files;
    foreach my $ext (@exts) {
        @files = glob $ext;

        if (scalar @files) {
            Verbose("Found at least one file with $ext extension.\n");
        } else {
            Verbose("Could not find at least one file with $ext extension.\n");
            return 0;
        }
    }
    return 1;
}

# Pass in a string length 
sub random_string {
    return MTT::Values::RandomString(@_);
}

sub temp_filename {
    my ($x, $filename) = tempfile(@_);
    return $filename;
}

# Thanks to http://predef.sourceforge.net/precomp.html for the list of
# defines to check. This subroutine is pulled directly from the below
# Open MPI M4 file:
#
#   http://svn.open-mpi.org/trac/ompi/browser/trunk/config/ompi_check_vendor.m4
#
sub get_compiler_vendor {
    Debug("get_compiler_vendor got @_\n");
    my ($compiler) = @_;
    my $ret = "unknown";

    # Default to using mpicc
    $compiler = "mpicc -c" if (! defined($compiler));

    # GNU is probably the most common, so check that one as soon as
    # possible.  Intel pretends to be GNU, so need to check Intel
    # before checking for GNU.

    # Intel
    if (_check_c_if("defined(__INTEL_COMPILER) || defined(__ICC)", $compiler)) {
        $ret = "intel";
    }
    # Pathscale
    elsif (_check_c_ifdef("__PATHSCALE__", $compiler)) {
        $ret = "pathscale";
    }
    # GNU
    elsif (_check_c_ifdef("__GNUC__", $compiler)) {
        $ret = "gnu";
    }
    # Borland Turbo C
    elsif (_check_c_ifdef("__TURBOC__", $compiler)) {
        $ret = "borland";
    }
    # Borland C++
    elsif (_check_c_ifdef("__BORLANDC__", $compiler)) {
        $ret = "borland";
    }
    # Comeau C++
    elsif (_check_c_ifdef("__COMO__", $compiler)) {
        $ret = "comeau";
    }
    # Compaq C/C++
    elsif (_check_c_if("defined(__DECC) || defined(VAXC) || defined(__VAXC)", $compiler)) {
        $ret = "compaq";
        if (_check_c_if("defined(__osf__) && defined(__LANGUAGE_C__)", $compiler)) {
            $ret = "compaq";
            if (_check_c_ifdef("__DECCXX", $compiler)) {
                $ret = "compaq";
            }
        }
    }
    # Cray C/C++
    elsif (_check_c_ifdef("_CRAYC", $compiler)) {
        $ret = "cray";
    }
    # Diab C/C++
    elsif (_check_c_ifdef("__DCC__", $compiler)) {
        $ret = "diab";
    }
    # Digital Mars
    elsif (_check_c_if("defined(__DMC__) || defined(__SC__) || defined(__ZTC__)", $compiler)) {
        $ret = "digital mars";
    }
    # HP ANSI C / aC++
    elsif (_check_c_if("defined(__HP_cc) || defined(__HP_aCC)", $compiler)) {
        $ret = "hp";
    }
    # IBM XL C/C++
    elsif (_check_c_if("defined(__xlC__) || defined(__IBMC__) || defined(__IBMCPP__)", $compiler)) {
        $ret = "ibm";
        if (_check_c_if("defined(_AIX) && defined(__GNUC__)", $compiler)) {
            $ret = "ibm";
        }
    }
    # KAI C++ (rest in peace)
    elsif (_check_c_ifdef("__KCC", $compiler)) {
        $ret = "kai";
    }
    # LCC
    elsif (_check_c_ifdef("__LCC__", $compiler)) {
        $ret = "lcc";
    }
    # MetaWare High C/C++
    elsif (_check_c_ifdef("__HIGHC__", $compiler)) {
        $ret = "metaware high";
    }
    # Metrowerks Codewarrior
    elsif (_check_c_ifdef("__MWERKS__", $compiler)) {
        $ret = "metrowerks";
    }
    # MIPSpro (SGI)
    elsif (_check_c_if("defined(sgi) || defined(__sgi)", $compiler)) {
        $ret = "sgi";
    }
    # MPW C++
    elsif (_check_c_if("defined(__MRC__) || defined(MPW_C) || defined(MPW_CPLUS)", $compiler)) {
        $ret = "mpw";
    }
    # Microsoft
    # (Always use C compiler when checking for Microsoft, as
    # Visual C++ doesn't recognize .cc as a C++ file.)
    elsif (_check_c_if("defined(_MSC_VER) || defined(__MSC_VER)", $compiler)) {
        $ret = "microsoft";
    }
    # Norcroft C
    elsif (_check_c_ifdef("__CC_NORCROFT", $compiler)) {
        $ret = "norcroft";
    }
    # Pelles C
    elsif (_check_c_ifdef("__POCC__", $compiler)) {
        $ret = "pelles";
    }
    # Portland Group
    elsif (_check_c_ifdef("__PGI", $compiler)) {
        $ret = "pgi";
    }
    # SAS/C
    elsif (_check_c_if("defined(SASC) || defined(__SASC) || defined(__SASC__)", $compiler)) {
        $ret = "sas";
    }
    # Sun Workshop C/C++
    elsif (_check_c_if("defined(__SUNPRO_C) || defined(__SUNPRO_CC)", $compiler)) {
        $ret = "sun";
    }
    # TenDRA C/C++
    elsif (_check_c_ifdef("__TenDRA__", $compiler)) {
        $ret = "tendra";
    }
    # Tiny C
    elsif (_check_c_ifdef("__TINYC__", $compiler)) {
        $ret = "tiny";
    }
    # USL C
    elsif (_check_c_ifdef("__USLC__", $compiler)) {
        $ret = "usl";
    }
    # Watcom C++
    elsif (_check_c_ifdef("__WATCOMC__", $compiler)) {
        $ret = "watcom";
    }

    Debug("get_compiler_vendor returning $ret\n");
    return $ret;
}

sub _check_compile {
    Debug("_check_compile got @_\n");
    my ($macro, $c_code, $compiler) = @_;

    # Default to using mpicc
    $compiler = "mpicc" if (! defined($compiler));

    # Suffix for the tempfile
    my $filename_suffix = "-check_compile.c";

    # Write out a little test program
    my ($fh, $filename) = tempfile(DIR => "/tmp", SUFFIX => $filename_suffix);
    MTT::Files::SafeWrite(1, $filename, $c_code);

    # Compile the little test
    my $ret;
    my $cmd = "$compiler $filename";
    my $x = MTT::DoCommand::Cmd(1, $cmd);

    # Clean up the test
    unlink($filename);

    if (!MTT::DoCommand::wsuccess($x->{exit_status})) {
        Debug("_check_compile: $compiler does not predefine \"$macro\"\n");
        $ret = 0;
    } else {
        Debug("_check_compile: $compiler predefines \"$macro\"\n");
        $ret = 1;
    }

    Debug("_check_compile returning $ret\n");
    return $ret;
}

sub _check_c_ifdef {
    my ($macro, $compiler) = @_;

    my $c_code = "/*
 * This program is automatically generated by Functions.pm
 * of MPI Testing Tool (MTT).  Any changes you make here may
 * get lost!
 *
 * Copyrights and licenses of this file are the same as for the MTT.
 *
 */

#ifndef $macro
#error \"symbol $macro not defined\"
choke me
#endif
";

    return _check_compile($macro, $c_code, $compiler);
}

sub _check_c_if {
    my ($macro, $compiler) = @_;

    my $c_code = "/*
 * This program is automatically generated by Functions.pm
 * of MPI Testing Tool (MTT).  Any changes you make here may
 * get lost!
 *
 * Copyrights and licenses of this file are the same as for the MTT.
 *
 */

#if !( $macro )
#error \"condition $macro not met\"
choke me
#endif";

    return _check_compile($macro, $c_code, $compiler);
}

sub get_ini_val {
    my($section,$param) = @_;
    my $ini = $MTT::Globals::Internals->{ini};
    if (!defined($ini)) {
       die "MTT::Globals::Internals->{ini} undefined";
    }
    return MTT::Values::Value($ini, $section, $param);
}

our $current_report;

# returns a value from report object
sub get_report_data {
    my($param) = @_;
    if (!defined($current_report)) {
        return undef;
    }
    my $val = $current_report->{$param};
    return $val;
}

# generates hostlist for mtt
# Example: &create_hostlist("node[1-3],node7", 16)
# Result: node1:16 node2:16 node3:16 node7:16

sub create_hostlist {
    my ($host_list, $cpu_per_node) = @_;

    my @hosts = split(/,/,$host_list);

    my @expanded_hosts = ();
    for (my $x=0; $x < $#hosts + 1; $x++) {
        my $h = $hosts[$x];
        $h=~s/[\[\]]//g;
        if ($h =~ /^([^\d]+)(\d+)-(\d+)$/) {
            my $n = $1;
            for (my $i=$2; $i<=$3;$i++) {
                push @expanded_hosts, $n . $i . ":" . $cpu_per_node;
            }
        } else {
            push @expanded_hosts, $h . ":" . $cpu_per_node;
        }
    }
    my $ret = join(" ", @expanded_hosts);
    $ret;
}

# Generate a hash value from function parameters
sub generate_md5_hash {
    eval {
        require Digest::MD5;
        import Digest::MD5 'md5_hex'
    };
    if ($@) { # ups, no Digest::MD5
        require Digest::Perl::MD5;
        import Digest::Perl::MD5 'md5_hex'
    }

    my $str = shift @_;

    for my $attr (@_) {
        $str .= "_" . $attr;
    }

    Debug("generate_md5_hash string is $str\n");

    return md5_hex($str);
}

my $enumerate_ex_context = {};

# enumerate_ex funclet
# Allow to substitute parameters/variables multiple times.
#
# Examples:
#
# 1)
# argv=&enumerate_ex("&val(p1) &val(p1)", "p1"=>[1,2,3])
# Total results count is 3 (not 3^2=9)
#
# 2)
# argv=&enumerate_ex("&val(p1) &val(p1)", "p1"=>&enumerate(1,2,3))
# Total results count is 3.
#
# 3)
# argv=&enumerate_ex("-param &val(param1) -param2 &val(param1) &val(param2) &val(param3)", "param1"=>@param1@, "param2"=>"@!param2@", "param3"=>"&eq(&val(param1),&val(param2))" )
# param1=&enumerate(1,2,3,4,5)
# param2=&if(&ge(&val(param1),4),&val(param1),10)
#
# param1 variable has 5 values and param1 is used twice.
# param2 is an expression. It is passed via @!param2@ substitution (w/o evaluating)
# Total results count is 5.
#                   
sub enumerate_ex {
    my $cmd = shift;

    my $key = shift;
    my $value = shift;

    my @other_params = @_;

    my $key2 = shift @other_params;
    my $value2 = shift @other_params;

    my @result = ();

    if (ref($value) eq "") {
        $value = MTT::Values::EvaluateString($value, $MTT::Values::evaluate_string_ini, $MTT::Values::evaluate_string_section);
        if (ref($value) eq "") {
            $value = [$value];
        }
    }
    foreach my $cur_value (@$value) {
        $enumerate_ex_context->{$key} = $cur_value;
        my $res;
        if (defined($key2)) {
            $res = enumerate_ex($cmd, $key2, $value2, @other_params);
        } else {
            $res = MTT::Values::EvaluateString($cmd, $MTT::Values::evaluate_string_ini, $MTT::Values::evaluate_string_section);
        }
        if (ref($res) eq "") {
            push(@result, $res);
        } else {
            foreach (@$res) {
                push(@result, $_);
            }
        }
        delete $enumerate_ex_context->{$key}
    }
    return [@result];
}

# get value from enumerate_ex context hash
sub val {
    my($param) = @_;
    if (!exists($enumerate_ex_context->{$param})) {
        Warning("val=$param is not exist\n");
        return undef;
    }
    my $value = $enumerate_ex_context->{$param};
    return $value;
}

# call Evaluate string for parameter
sub evaluate {
    my($param) = @_;
    my $value = MTT::Values::EvaluateString($param, $MTT::Values::evaluate_string_ini, $MTT::Values::evaluate_string_section);
    return $value;
}


# Run shell commands as a script, i.e
#
# [mtt]
# myscript=<<EOT
# #!/bin/sh
# pwd
# ls
# EOT
# on_stop=&shell_script("mtt",myscript)
# 
#

sub executable {
    my ($cmd_section, $cmd_param) = @_;
    my $cmd = &get_ini_val($cmd_section, $cmd_param);
    my $x = MTT::DoCommand::CmdScript(1, $cmd);
    return $x->{result_stdout};
}

#
# Poor man switch statement
# Example: mtt_switch(@np@, 9, "return1", 100, return2", "default", 0);
#

sub mtt_switch
{
    my ($var, %cases) = @_;

    if (defined($cases{$var})) {
        Debug("mtt_switch: $var case " . $cases{$var});
        return $cases{$var};
    }

    if ($cases{'default'}) {
        Debug("mtt_switch: $var default case " . $cases{$var});
        return $cases{'default'};
    }

    Debug("ERROR: Not found case for $var\n");
}

sub create_file
{
    my ($filename, $body) = @_;
    MTT::Files::SafeWrite(1, $filename, $body);
}

sub cluster_name
{
    my $clust_name;

    if (slurm_job()) {
        $clust_name = `squeue -h -j $ENV{SLURM_JOB_ID} -o %P`;
    } else {
        $clust_name = `hostname`;
        $clust_name =~ m/\D+/;
    }
    chomp($clust_name);
    return $clust_name;
}

# Round-up and find next power of two
sub next_pwr {
    my ($x,$p) = (@_,2);  # default to next_pwr(X,2)
    my $log = log($x)/log($p);
    $log = int($log+1) if $log != int($log);
    return $p**$log;
}

# Calculate available memory can specify percentage out of total and for how many cores
#
sub calc_free_memory
{
    my ($percent, $nproc) = @_;

    open MEMINFO, '<', '/proc/meminfo' or die "Unable to open /proc/meminfo to find available memory\n";
    my $mem = <MEMINFO>;

    if ( $mem =~ /^MemTotal:\s+(\d+)\s.*$/ )  {
        $mem = $1;
    } else {
        die "Unable to find the available memory\n";
    }

    if ($percent) {
        $mem = ( $mem / 100 ) * $percent;
    }

    if ($nproc) {
        $mem = ($mem/$nproc);
    }

    my $mb = int($mem / 1024);
    return $mb;
}

sub test_ini_param {
    my ($param) = @_;
    my $sect = $MTT::Globals::Values->{active_section} ;
    my $val = get_ini_val($sect, $param);
    Debug("&test_param returning $val for $sect\n");
    return $val;
}

# Return random number from specified range:
#
sub random_range {
    my ($from, $to) = @_;
    $to++;
    my $x = $from + int(rand($to - $from));
    $x;
}

# Return random array element
#
sub random_array_element {
    my (@array) = @_;

    my $randomelement = $array[rand @array];
    $randomelement;
}


1;
