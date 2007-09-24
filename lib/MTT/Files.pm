#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006      Cisco Systems, Inc.  All rights reserved.
# Copyright (c) 2007      Sun Microsystems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Files;

use strict;
use Cwd;
use File::Basename;
use File::Find;
use MTT::Messages;
use MTT::DoCommand;
use MTT::FindProgram;
use MTT::Defaults;
use MTT::Values;
use MTT::Lock;
use Data::Dumper;

# How many old builds to keep
my $keep_builds = 3;

# the download program to use
my $http_agent;

#--------------------------------------------------------------------------

sub make_safe_filename {
    my ($filename) = @_;

    $filename =~ s/[ :\/\\\*\&\$\#\@\!\t]/_/g;
    return $filename;
}

#--------------------------------------------------------------------------

sub safe_mkdir {
    my ($dir) = @_;
    MTT::Files::mkdir($dir, 1);
}

#--------------------------------------------------------------------------

sub mkdir {
    my ($dir, $safe) = @_;

    my $c = cwd();
    Debug("Making dir: $dir (cwd: $c)\n");
    my @parts = split(/\//, $dir);

    my $str;
    if (substr($dir, 0, 1) eq "/") {
        $str = "/";
        shift(@parts);
    }

    # Test and make

    foreach my $p (@parts) {
        next if (! $p);

        $p = make_safe_filename($p)
            if ($safe);

        $str .= "$p";
        if (! -d $str) {
            Debug("$str does not exist -- creating\n");
            mkdir($str, 0777);
            if (! -d $str) {
                Abort("Could not make directory $p\n");
            }
        }
        $str .= "/";
    }

    # Return an absolute version of the created directory

    my $orig = cwd();
    MTT::DoCommand::Chdir($str);
    my $newdir = cwd();
    MTT::DoCommand::Chdir($orig);
    $newdir;
} 

#--------------------------------------------------------------------------

# unpack a tarball in the cwd and figure out what directory it
# unpacked into
sub unpack_tarball {
    my ($tarball, $delete_first) = @_;

    Debug("Unpacking tarball: $tarball\n");

    if (! -f $tarball) {
        Warning("Tarball does not exist: $tarball\n");
        return undef;
    }

    # Decide which unpacker to use

    my $unpacker;
    if ($tarball =~ /.*\.bz2$/) {
        $unpacker="bunzip2";
    } elsif ($tarball =~ /.*\.gz$/) {
        $unpacker="gunzip";
    } else {
        Warning("Unrecognized tarball extension ($tarball); don't know how to uncompress -- skipped\n");
        return undef;
    }

    # Examine the tarball and see what it puts in the cwd

    open(TAR, "$unpacker -c $tarball | tar tf - |");
    my @entries = <TAR>;
    close(TAR);
    my $dirs;
    my $files;
    foreach my $e (@entries) {
        chomp($e);
        # If no /'s, then it's possibly a file in the top-level dir --
        # save for later analysis.
        if ($e !~ /\//) {
            $files->{$e} = 1;
        } else {
            # If there's a / anywhere in the name, then save the
            # top-level dir name
            $e =~ s/(.+?)\/.*/\1/;
            $dirs->{$e} = 1;
        }
    }

    # Check all the "files" and ensure that they weren't just entries
    # in the tarball to make a directory (this shouldn't happen, but
    # just in case...)

    foreach my $f (keys(%$files)) {
        if (exists($dirs->{$f})) {
            delete $files->{$f};
        }
    }

    # Any top-level files left?

    my $tarball_dir;
    if (keys(%$files)) {
        my $b = basename($tarball);
        Debug("GOT FILES IN TARBALL\n");
        $tarball_dir = MTT::Files::mkdir("slimy_tarball_$b");
        MTT::DoCommand::Chdir($tarball_dir);
    } else {
        my @k = keys(%$dirs);
        if ($#k != 0) {
            my $b = basename($tarball);
            Debug("GOT MULTI DIRS IN TARBALL\n");
            print Dumper($dirs);
            $tarball_dir = MTT::Files::mkdir("slimy_tarball_$b");
            MTT::DoCommand::Chdir($tarball_dir);
        } else {
            $tarball_dir = $k[0];
        }
    }
    Debug("Tarball dir is: $tarball_dir\n");

    # Remove the tree first if requested
    MTT::DoCommand::Cmd(1, "rm -rf $tarball_dir")
        if ($delete_first);

    # Untar the tarball.  Do not use DoCommand here
    # because we don't want the result_stdout intercepted.

    system("$unpacker -c $tarball | tar xf -");
    my $ret = $? >> 8;
    if ($ret != 0) {
        Warning("Failed to unpack tarball successfully: $tarball: $@\n");
        return undef;
    }
    
    return $tarball_dir;
}

#--------------------------------------------------------------------------

# do a svn checkout
sub svn_checkout {
    my ($url, $rnum, $username, $pw, $pw_cache, $delete_first, $export, $svn_command) = @_;

    Debug("SVN checkout: $url\n");

    my $cwd = cwd();
    my $b = basename($url);
    MTT::DoCommand::Cmd(1, "rm -rf $b")
        if ($delete_first);

    my $str = "$svn_command " . ($export ? "export" : "co") . " ";
    $str .= "-r $rnum "
        if ($rnum);
    $str .= "--username $username "
        if ($username);
    $str .= "--password $pw "
        if ($pw);
    $str .= "--no-auth-cache "
        if ("0" eq $pw_cache);
    $str .= $url;
    $str .= " $cwd/$b";

    my $scheme;
    if ($url =~ /^http:\/\//) {
        $scheme = "http";
    } elsif ($url =~ /^https:\/\//) {
        $scheme = "https";
    }

    # The rest of this section must be serialized because only one
    # process can modify the $HOME/.subversion/servers file at a time.
    # Blah!
    MTT::Lock::Lock($ENV{HOME} . "/.subversion/servers");

    # Read in the original $HOME/.subversion/servers file
    my $svnfile = "$ENV{HOME}/.subversion/servers";
    my $file_contents;
    mkdir("$ENV{HOME}/.subversion")
        if (! -d "$ENV{HOME}/.subversion");
    if (-r $svnfile) {
        $file_contents = MTT::Files::Slurp($svnfile);
    } else {
        $file_contents = "[global]
http-proxy-host = bogus
http-proxy-port = bogus\n";
    }

    # Save the original proxy
    my $save_host;
    my $save_port;
    if ($file_contents =~ /\nhttp-proxy-host\s*\=\s*(.*)/i) {
        $save_host = $1;
    }
    if ($file_contents =~ /\nhttp-proxy-port\s*\=\s*(\d+)/i) {
        $save_port = $1;
    }

    # Loop over proxies
    my $proxies = \@{$MTT::Globals::Values->{proxies}->{$scheme}};
    my %ENV_SAVE = %ENV;

    # In case a proxy was not specified, try to svn without one
    if (! @{$proxies}) {
        push(@{$proxies}, undef);
    }

    foreach my $p (@{$proxies}) {

        # Skip "blank" proxies
        if (defined($p->{proxy}) and $p->{proxy} !~ /^\s*$/) {
            Debug("SVN checkout attempting proxy: $p->{proxy}\n");
            _substitute_proxy_in_servers_file($svnfile, $file_contents, $p->{host}, $p->{port});
        }

        my $ret = MTT::DoCommand::Cmd(1, $str);

        # If it failed, try again
        next
            if (!MTT::DoCommand::wsuccess($ret->{exit_status}));

        # Success!
        my $r = undef;

        # SVN
        if ($ret->{result_stdout} =~ m/Exported revision (\d+)\.\n$/) {
            $r = $1;
        # SVK
        } elsif ($ret->{result_stdout} =~ m/Syncing\s+\S+\s+in\s+\S+\s+to\s+(\d+)/i) {
            $r = $1;
        }

        MTT::Lock::Unlock($ENV{HOME} . "/.subversion/servers");
        return ($b, $r);
    }

    # Fall though means we didn't succeed.  Doh.

    # Restore the original proxy
    Debug("Restoring the proxy originally found in $svnfile: \"$save_host:$save_port\"\n");
    _substitute_proxy_in_servers_file($svnfile, $file_contents, $save_host, $save_port);

    # Reset the servers file to whatever it used to be (if it used to be!)
    MTT::Lock::Unlock($ENV{HOME} . "/.subversion/servers");
    return undef;
}

# Replace the proxy host and port in the ~/.subversion/servers file
sub _substitute_proxy_in_servers_file {
    my ($file, $contents, $host, $port) = @_;

    # Write a new $HOME/.subversion/servers file with the
    # right proxy info
    if ($host) {
        $host =~ m@^.+://(.+):([0-9]+)/@;
        $contents =~ s/^\s*http-proxy-host\s*=.*$/http-proxy-host = $host/m;
        $contents =~ s/^\s*http-proxy-port\s*=.*$/http-proxy-port = $port/m;
    } else {
        $contents =~ s/^\s*http-proxy-host\s*=.*$//m;
        $contents =~ s/^\s*http-proxy-port\s*=.*$//m;
    }
    open(FILE, ">$file");
    print FILE $contents;
    close(FILE);
}

# Do a (Sun) TeamWare bringover
sub teamware_bringover {
    my ($file_list_program, $parent, $child, $path) = @_;

    my $str;
    $str .= "bringover";
    $str .= " -f $file_list_program";
    $str .= " -p $parent";
    $str .= " -w $child";
    $str .= " $path\n";

    my $ret = MTT::DoCommand::Cmd(1, $str);

    return $ret;
}

#--------------------------------------------------------------------------

# Copy and entire file tree
sub copy_tree {
    my ($srcdir, $delete_first) = @_;

    Debug("Copying directory: $srcdir\n");

    if (! -d $srcdir) {
        Warning("Directory does not exist: $srcdir\n");
        return undef;
    }

    my $b = basename($srcdir);
    MTT::DoCommand::Cmd(1, "rm -rf $b")
        if ($delete_first);

    my $ret = MTT::DoCommand::Cmd(1, "cp -r $srcdir .");
    if (!MTT::DoCommand::wsuccess($ret->{exit_status})) {
        Warning("Could not copy file tree $srcdir: $!\n");
        return undef;
    }

    return $b;
}

#--------------------------------------------------------------------------

my $md5sum_path;
my $md5sum_searched;

sub _find_md5sum {
    # Search
    $md5sum_path = FindProgram(qw(md5sum gmd5sum));
    $md5sum_searched = 1;
    if (!$md5sum_path) {
        Warning("Could not find md5sum executable, so I will not be able to check the validity of downloaded executables against their known MD5 checksums.  Proceeding anyway...\n");
    }
}

sub md5sum {
    my ($file) = @_;

    _find_md5sum()
        if (!$md5sum_searched);
    # If we already searched and didn't find then, then just return undef
    return undef
        if (!$md5sum_path && $md5sum_searched);
    return undef
        if (! -f $file);

    my $x = MTT::DoCommand::Cmd(1, "$md5sum_path $file");
    if (!MTT::DoCommand::wsuccess($x->{exit_status})) {
        Warning("md5sum unable to run properly\n");
        return undef;
    }
    $x->{result_stdout} =~ m/^(\w{32})/;
    return $1;
}

#--------------------------------------------------------------------------

my $sha1sum_path;
my $sha1sum_searched;

sub sha1sum {
    my ($file) = @_;

    # Setup if we haven't already
    if (!$sha1sum_path) {
        # If we already searched and didn't find then, then just return undef
        return undef
            if ($sha1sum_searched);

        # Search
        $sha1sum_path = FindProgram(qw(sha1sum gsha1sum));
        $sha1sum_searched = 1;
        if (!$sha1sum_path) {
            Warning("Could not find sha1sum executable, so I will not be able to check the validity of downloaded executables against their known SHA1 checksums.  Proceeding anyway...\n");
            return undef;
        }
    }

    my $x = MTT::DoCommand::Cmd(1, "$sha1sum_path $file");
    if (!MTT::DoCommand::wsuccess($x->{exit_status})) {
        Warning("sha1sum unable to run properly\n");
        return undef;
    }
    $x->{result_stdout} =~ m/^(\w{40})/;
    return $1;
}

#--------------------------------------------------------------------------

my $mtime_max;

sub _do_mtime {
    # don't process special directories or links, and dont' recurse
    # down "special" directories
    if ( -l $_ ) { return; }
    if ( -d $_  && 
         ((/\.svn/) || (/\.deps/) || (/\.libs/))) {
        $File::Find::prune = 1;
        return;
    }

    # $File::Find::name is the path relative to the starting point.
    # $_ contains the file's basename.  The code automatically changes
    # to the processed directory, so we want to open / close $_.
    my @stat_info = stat($_);
    $mtime_max = $stat_info[9]
        if ($stat_info[9] > $mtime_max);
}

sub mtime_tree {
    my ($dir) = @_;

    $mtime_max = -1;
    find(\&_do_mtime, $dir);

    return $mtime_max;
}

#--------------------------------------------------------------------------

sub http_get {
    my ($url, $username, $password) = @_;

    my $scheme;
    if ($url =~ /^http:\/\//) {
        $scheme = "http";
    } elsif ($url =~ /^https:\/\//) {
        $scheme = "https";
    } elsif ($url =~ /^ftp:\/\//) {
        $scheme = "ftp";
    }

    # figure out what download command to use
    if (!$http_agent) {
        foreach my $agent (keys(%{$MTT::Defaults::System_config->{http_agents}})) {
            my $found = FindProgram($agent);
            if ($found) {
                $http_agent = $MTT::Defaults::System_config->{http_agents}->{$agent};
                last;
            }
        }
    }
    Abort("Cannot find downloading program -- aborting in despair\n")
        if (!defined($http_agent));
    my $outfile = basename($url);

    # Loop over proxies
    my $proxies = \@{$MTT::Globals::Values->{proxies}->{$scheme}};
    my %ENV_SAVE = %ENV;
    foreach my $p (@{$proxies}) {
        my $cmd;

        # Setup the proxy in the environment
        if ("" ne $p->{proxy}) {
            Debug("Using $scheme proxy: $p->{proxy}\n");
            $ENV{$scheme . "_proxy"} = $p->{proxy};
        }

        my $str = "\$cmd = \"" . $http_agent->{command};
        if (defined($username) && defined($password)) {
            $str .= " " . $http_agent->{auth};
        }
        $str .= "\"";
        eval $str;
        my $x = MTT::DoCommand::Cmd(1, $cmd);

        # Restore the environment
        %ENV = %ENV_SAVE;

        # If it succeeded, return happiness
        return 1
            if (MTT::DoCommand::wsuccess($x->{exit_status}));
    }

    # Failure
    return undef;
}

#--------------------------------------------------------------------------

# Copy infile or stdin to a unique file in /tmp
sub copyfile {

    my($infile) = @_;
    my($opener);
    my($outfile) = "/tmp/" . MTT::Values::RandomString(10) . ".ini";

    # stdin
    if (ref($infile) =~ /glob/i) {
        $infile = "stdin";
        $opener = "-";
    }
    # file
    else {
        $opener = "< $infile";
    }
    open(in, $opener);
    open(out, "> $outfile") or warn "Could not open $outfile for writing";

    Debug("Copying: $infile to $outfile\n");

    while (<in>) {
        print out;
    }
    close(in);
    close(out);

    return $outfile;
}

#--------------------------------------------------------------------------

sub load_dumpfile {
    my ($filename, $data) = @_;

    # Check that the file is there
    return
        if (! -r $filename);

    # Get the file size
    my ($dev, $ino, $mode, $nlink, $uid, $gid, $rdev, $size,
        $atime, $mtime, $ctime, $blksize, $blocks) = stat($filename);

    # Read it in
    open IN, $filename;
    my $tmp;
    read(IN, $tmp, $size);
    close IN;
    
    # It's in Dumper format.  How many $VARx's are there?
    return
        if (! $tmp =~ m/\$VAR[0-9]+/g);
    my $count = 0;
    ++$count
        while ($tmp =~ m/\$VAR[0-9]+/g);

    # We know how many $VARx's there are.  Build up a string to eval.
    my $str;
    my $var_num = 1;
    while ($var_num <= $count) {
        $str .= "my \$VAR$var_num;\n";
        ++$var_num;
    }
    $str .= "eval \$tmp;\n";
    my $var_num = 1;
    while ($var_num <= $count) {
        $str .= "\$\$data->{VAR$var_num} = \$VAR$var_num;\n";
        ++$var_num;
    }
    eval $str;
}

#--------------------------------------------------------------------------

sub save_dumpfile {
    my ($filename) = @_;
    shift;

    # Serialize
    my $d = new Data::Dumper([@_]);
    $d->Purity(1)->Indent(1);

    open FILE, ">$filename.new";
    print FILE $d->Dump;
    close FILE;

    # Atomically move it onto the old file
    rename("$filename.new", $filename);
}

# Write out a file
sub SafeWrite {
    my ($force, $filename, $body) = @_;
    my $ret;

    $ret->{success} = 0;

    # Does the file already exist?
    if (-r $filename && !$force) {
        return $ret;
    }

    # Write out the file
    if (!open FILE, ">$filename") {
        $ret->{result_message} = "Failed to write to file: $!";
        return $ret;
    }
    print FILE $body;
    close FILE;

    # All done
    $ret->{success} = 1;

    return $ret;
}

# Return the contents of a file as a scalar
sub Slurp {
    my ($file) = @_;

    my $contents;
    open (INPUT, $file) || warn "can't open $file: $!";
    while (<INPUT>) {
        $contents .= $_;
    }
    close(INPUT) || warn "can't close $file: $!";
    return $contents;
}

1;


