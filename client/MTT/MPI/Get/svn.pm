#!/usr/bin/env perl
#
# Copyright (c) 2004-2005 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2004-2005 The Trustees of the University of Tennessee.
#                         All rights reserved.
# Copyright (c) 2004-2005 High Performance Computing Center Stuttgart, 
#                         University of Stuttgart.  All rights reserved.
# Copyright (c) 2004-2005 The Regents of the University of California.
#                         All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::MPI::Get::svn;

use strict;
use Cwd;
use File::Basename;
use POSIX qw(strftime);
use MTT::Messages;
use MTT::Values;
use MTT::Files;
use MTT::MPI::Get;

#--------------------------------------------------------------------------

sub Get {
    my ($ini, $section, $unique_id, $force) = @_;

    my $ret;
    my $data;

    # See if we got a svn in the ini section
    $data->{url} = Value($ini, $section, "url");
    return undef if (!$data->{url});
    Debug(">> svn: got url $data->{url}\n");

    # Do we have a svn with the same URL already?
    my $found = 0;
    foreach my $mpi_section (keys(%{$MTT::MPI::sources})) {
        next
            if ($section ne $mpi_section);

        foreach my $mpi_unique (keys(%{$MTT::MPI::sources->{$section}})) {
            my $source = $MTT::MPI::sources->{$section}->{$mpi_unique};
            if ($source->{module_name} eq "MTT::MPI::Get::svn" &&
                $source->{module_data}->{url} eq $data->{url}) {

                # Found one with the same URL.  

                $found = 1;

                # If we're forcing, don't even both checking to see if
                # the repository has changed since we exported.

                if ($force) {
                    Debug(">> We have this svn already, but we're forcing, so unconditionally re-export\n");

                    $unique_id = $ret->{unique_id} = $source->{unique_id};
                    last;
                } else {

                    # Run "svn log -r <old r number>:HEAD $url" and
                    # see what comes up.  


                    my $x = MTT::DoCommand::Cmd(1, "svn log -r $source->{module_data}->{r}:HEAD $data->{url}");
                    if (0 != $x->{status}) {
                        Warning("Can't check repository properly; going to assume we need a new checkout\n");
                        $unique_id = $ret->{unique_id} = $source->{unique_id};
                        last;
                    } else {

                        # There are two possibilities:

                        # 1. one line of "-----", meaning that there
                        # have been no commits in this directory of
                        # the repository since the last R number.

                        # 2. one or more entries of log messages.  In
                        # this case, we need to look at the r number
                        # of the # first entry that comes along.  It
                        # may be the old # r number (i.e., it's still
                        # the HEAD), in which # case we don't need a
                        # new checkout.  Or it may be # a different r
                        # number, in which case we need a # new
                        # checkout.

                        my $need_new;
                        if ($x->{stdout} =~ /^-+\n$/) {
                            $need_new = 0;
                            Debug("Got one line of dashes -- no need\n");
                        } else {
                            $x->{stdout} =~ m/^-+\nr(\d+)\s/;
                            if ($1 eq $source->{module_data}->{r}) {
                                $need_new = 0;
                                print("Got old r number -- no need\n");
                            } else {
                                $need_new = 1;
                                print("Got new r number ($1) -- need\n");
                            }
                        }

                        if ($need_new) {
                            Debug(">> svn: we have this URL, but the repository has changed and we need a new checkout\n");
                        } else {
                            Debug(">> svn: we have this URL and the repository has not changed; skipping\n");
                            return undef;
                        }
                    }
                }
            }
        }

        # If we found one, bail
        last
            if ($found);
    }
    Debug(">> svn: this is a new svn\n")
        if (!$found);

    # Cache it
    Debug(">> svn: exporting\n");
    my $dir = MTT::Files::mkdir($unique_id);
    chdir($dir);
    ($dir, $data->{r}) = MTT::Files::svn_checkout($data->{url}, 1, 1);
    return undef
        if (!$dir);
    $data->{directory} = cwd() . "/$dir";

    # Set the function pointer -- note that we just re-use the
    # copytree module, since that's all we have to do (i.e., copy a
    # local tree)
    $ret->{prepare_for_install} = "MTT::MPI::Get::copytree::PrepareForInstall";

    # Get other values (set for copytree's PrepareForInstall)
    $data->{pre_copy} = Value($ini, $section, "pre_export");
    $data->{post_copy} = Value($ini, $section, "post_export");

    # Make a best attempt to get a version number
    # 1. Try looking for name-<number> in the directory basename
    if ($dir =~ m/[\w-]+(\d.+)/) {
        $ret->{version} = $1;
    } 
    # 2. Use the SVN r number
    elsif ($data->{r}) {
        $ret->{version} = "r$data->{r}";
    }
    # Give up
    else {
        $ret->{version} = "$dir-" . strftime("%m%d%Y-%H%M%S", localtime);
    }
    $ret->{module_data} = $data;

    # All done
    Debug(">> svn: returning successfully\n");
    return $ret;
} 

1;
