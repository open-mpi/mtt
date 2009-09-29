#! /usr/bin/env python

#
# Copyright (c) 2009 Voltaire
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

# Python Standart modules

# Python Google AppEngine SDK modules
from google.appengine.ext import db

# Private modules

class SubmitInfo(db.Model):
    # mpiinstallphase_set(back-reference)
    # testbuildphase_set(back-reference)
    # testrunphase_set(back-reference)
    hostname                = db.StringProperty(default='unknown')
    local_username          = db.StringProperty(default='unknown')
    http_username           = db.StringProperty(default='unknown')
    mtt_version             = db.StringProperty(default='unknown')

class SuiteInfo(db.Model):
    # testbuildphase_set(back-reference)
    # testrunphase_set(back-reference)
    suite_name              = db.StringProperty(default='unknown')
    suite_version           = db.StringProperty(default='unknown')

class MpiInfo(db.Model):
    # mpiinstallphase_set(back-reference)
    # testbuildphase_set(back-reference)
    # testrunphase_set(back-reference)
    mpi_name                = db.StringProperty(default='unknown')
    mpi_version             = db.StringProperty(default='unknown')
    oma_version             = db.StringProperty(default='unknown')

class ClusterInfo(db.Model):
    # mpiinstallphase_set(back-reference)
    # testbuildphase_set(back-reference)
    # testrunphase_set(back-reference)
    cluster_name            = db.StringProperty(default='unknown')
    node_count              = db.IntegerProperty(default=0)
    node_hostname           = db.StringProperty(default='unknown')
    node_arch               = db.StringProperty(default='unknown')
    node_ncpu               = db.IntegerProperty(default=0)
    node_nsocket            = db.IntegerProperty(default=0)
    node_htt                = db.BooleanProperty(default=False)
    node_mem                = db.IntegerProperty(default=0)
    node_cache              = db.IntegerProperty(default=0)
    node_mhz                = db.IntegerProperty(default=0)
    node_os_kernel          = db.StringProperty(default='unknown')
    node_os_vendor          = db.StringProperty(default='unknown')
    node_os_release         = db.StringProperty(default='unknown')
    net_pci                 = db.TextProperty()
    net_conf                = db.TextProperty()
    net_eth100              = db.BooleanProperty(default=False)
    net_eth1000             = db.BooleanProperty(default=False)
    net_eth10k              = db.BooleanProperty(default=False)
    net_iwarp               = db.BooleanProperty(default=False)
    net_ibddr               = db.BooleanProperty(default=False)
    net_ibqdr               = db.BooleanProperty(default=False)

class CompilerInfo(db.Model):
    # mpiinstallphase_set(back-reference)
    # testbuildphase_set(back-reference)
    # testrunphase_set(back-reference)
    compiler_name           = db.StringProperty(default='unknown')
    compiler_version        = db.StringProperty(default='unknown')

class MpiInstallPhase(db.Expando):
    # testbuildphase_set(back-reference)
    # testrunphase_set(back-reference)
    submitinfo                              = db.ReferenceProperty(SubmitInfo, collection_name='mpiinstallphase_set')
    clusterinfo                             = db.ReferenceProperty(ClusterInfo, collection_name='mpiinstallphase_set')
    mpiinfo                                 = db.ReferenceProperty(MpiInfo, collection_name='mpiinstallphase_set')
    compilerinfo                            = db.ReferenceProperty(CompilerInfo, collection_name='mpiinstallphase_set')
    start_time                              = db.DateTimeProperty(auto_now_add=True)
    end_time                                = db.DateTimeProperty(auto_now_add=True)
    duration                                = db.IntegerProperty()
    status                                  = db.IntegerProperty(default=0)
    description                             = db.TextProperty()
    stdout                                  = db.TextProperty()
    stderr                                  = db.TextProperty()
    configuration                           = db.TextProperty()
    mpi_path                                = db.StringProperty(default='unknown')

class TestBuildPhase(db.Expando):
    # testrunphase_set(back-reference)
    submitinfo                              = db.ReferenceProperty(SubmitInfo, collection_name='testbuildphase_set')
    clusterinfo                             = db.ReferenceProperty(ClusterInfo, collection_name='testbuildphase_set')
    mpiinfo                                 = db.ReferenceProperty(MpiInfo, collection_name='testbuildphase_set')
    compilerinfo                            = db.ReferenceProperty(CompilerInfo, collection_name='testbuildphase_set')
    suiteinfo                               = db.ReferenceProperty(SuiteInfo, collection_name='testbuildphase_set')
    mpiinstallphase                         = db.ReferenceProperty(MpiInstallPhase, collection_name='testbuildphase_set')
    start_time                              = db.DateTimeProperty(auto_now_add=True)
    end_time                                = db.DateTimeProperty(auto_now_add=True)
    duration                                = db.IntegerProperty()
    status                                  = db.IntegerProperty(default=0)
    description                             = db.TextProperty()
    stdout                                  = db.TextProperty()
    stderr                                  = db.TextProperty()

class TestRunPhase(db.Expando):
    # id_testbuild(back-reference)
    submitinfo                              = db.ReferenceProperty(SubmitInfo, collection_name='runtestphase_set')
    clusterinfo                             = db.ReferenceProperty(ClusterInfo, collection_name='runtestphase_set')
    mpiinfo                                 = db.ReferenceProperty(MpiInfo, collection_name='runtestphase_set')
    compilerinfo                            = db.ReferenceProperty(CompilerInfo, collection_name='runtestphase_set')
    suiteinfo                               = db.ReferenceProperty(SuiteInfo, collection_name='runtestphase_set')
    mpiinstallphase                         = db.ReferenceProperty(MpiInstallPhase, collection_name='runtestphase_set')
    testbuildphase                          = db.ReferenceProperty(TestBuildPhase, collection_name='runtestphase_set')

    start_time                              = db.DateTimeProperty(auto_now_add=True)
    end_time                                = db.DateTimeProperty(auto_now_add=True)
    duration                                = db.IntegerProperty()
    status                                  = db.IntegerProperty(default=0)
    description                             = db.TextProperty()
    stdout                                  = db.TextProperty()
    stderr                                  = db.TextProperty()
    test_name                               = db.StringProperty()
    test_case                               = db.StringProperty()
    cmdline                                 = db.TextProperty()
    mpi_nproc                               = db.IntegerProperty()
    mpi_hlist                               = db.StringProperty()
    mpi_rlist                               = db.StringProperty()
    mpi_mca                                 = db.StringProperty()
    mpi_btl                                 = db.StringListProperty()
    net_note                                = db.StringProperty()
    tag                                     = db.StringListProperty()

    data_file                               = db.BlobProperty(default=None)

    cached_submitinfo_hostname              = db.StringProperty()
    cached_submitinfo_local_username        = db.StringProperty()
    cached_submitinfo_http_username         = db.StringProperty()
    cached_submitinfo_mtt_version           = db.StringProperty()
    cached_clusterinfo_cluster_name         = db.StringProperty()
    cached_clusterinfo_node_count           = db.IntegerProperty()
    cached_clusterinfo_node_hostname        = db.StringProperty()
    cached_clusterinfo_node_arch            = db.StringProperty()
    cached_clusterinfo_node_ncpu            = db.IntegerProperty()
    cached_clusterinfo_node_nsocket         = db.IntegerProperty()
    cached_clusterinfo_node_htt             = db.BooleanProperty(default=False)
    cached_clusterinfo_node_mem             = db.IntegerProperty()
    cached_clusterinfo_node_cache           = db.IntegerProperty()
    cached_clusterinfo_node_mhz             = db.IntegerProperty()
    cached_clusterinfo_node_os_kernel       = db.StringProperty()
    cached_clusterinfo_node_os_vendor       = db.StringProperty()
    cached_clusterinfo_node_os_release      = db.StringProperty()
    cached_clusterinfo_net_eth100           = db.BooleanProperty(default=False)
    cached_clusterinfo_net_eth1000          = db.BooleanProperty(default=False)
    cached_clusterinfo_net_eth10k           = db.BooleanProperty(default=False)
    cached_clusterinfo_net_iwarp            = db.BooleanProperty(default=False)
    cached_clusterinfo_net_ibddr            = db.BooleanProperty(default=False)
    cached_clusterinfo_net_ibqdr            = db.BooleanProperty(default=False)
    cached_mpiinfo_mpi_name                 = db.StringProperty()
    cached_mpiinfo_mpi_version              = db.StringProperty()
    cached_mpiinfo_oma_version              = db.StringProperty()
    cached_compilerinfo_compiler_name       = db.StringProperty()
    cached_compilerinfo_compiler_version    = db.StringProperty()
    cached_suiteinfo_suite_name             = db.StringProperty()
    cached_suiteinfo_suite_version          = db.StringProperty()
    cached_mpiinstallphase_mpi_path         = db.StringProperty()
