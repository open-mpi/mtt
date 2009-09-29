#!/usr/bin/env python

#
# Copyright (c) 2009 Voltaire
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

# Python Standart modules
import os
import sys
import datetime
import types
import string
import logging
import cStringIO
import mimetypes
import re
import urllib

# Python Google AppEngine SDK modules
import yaml
from google.appengine.api import users
from google.appengine.api import datastore
from google.appengine.api import datastore_errors
from google.appengine.api import datastore_types

from google.appengine.ext import db
from google.appengine.ext import webapp
from google.appengine.ext.webapp.util import run_wsgi_app
from google.appengine.ext.webapp import template

from google.appengine.runtime import DeadlineExceededError

# Private modules
import conf
import models
import pager
import auth


class MainPage(webapp.RequestHandler):
    "Output data collection view"

    user = None

    def get(self):
        
        if not users.is_current_user_admin():
            greeting = ("<a href=\"%s\">Sign in or register</a>." %
                  users.create_login_url("/"))
            self.response.set_status(401) # Unauthorized
            self.response.out.write("<html><body>%s</body></html>" % greeting)
            return 0
        
        logging.debug('%s: get as a user %s=> %s' % (self.__class__.__name__, str(self.user), self.request.GET))
        status = 0
        
        query_str = self.request.get('querytext')
        result_count = 0
        result_set = None
        try:
            if (query_str == ''):
                bookmark = self.request.get('bookmark')
                query_collection = pager.PagerQuery(models.TestRunPhase)
                prev, result_set, next = query_collection.fetch(15, bookmark)
#                result_count = query_collection._get_query().count()

                # query.count() is not used because of count() ignores the LIMIT clause on GQL queries.
                for result in query_collection._get_query():
                    result_count += 1
            else:
                temp_query_str = query_str
                (temp_query_str, status) = gql_ex(temp_query_str)
                
                query_collection = db.GqlQuery(temp_query_str)
                result_set = query_collection
                prev = ''
                next = ''
    
                # query.count() is not used because of count() ignores the LIMIT clause on GQL queries.
                for result in result_set:
                    result_count += 1
                
        except datastore_errors.BadQueryError:
            result_set = None
            result_count = 0
            prev = ''
            next = ''
            query_str == ''

        if os.environ.has_key('APPLICATION_ID'):
               app_id=os.environ['APPLICATION_ID']

        template_context = {
            'query_collection': result_set,
            'query_count': result_count,
            'prev': prev,
            'next': next,
            'app_id': app_id,
            'query_str': query_str
            }

        path = os.path.join(os.path.dirname(__file__), os.path.join('templates', 'index.html'))
        self.response.out.write(template.render(path, template_context, debug=conf.DEBUG))


class LoginHandler(webapp.RequestHandler):
    def get(self):
        """ It displays a login form that POSTs to the same URL.
    
        """
        
        logging.debug('%s: get=> %s' % (self.__class__.__name__, self.request.GET))
        status = 0
        
        template_context = {
            'action': self.request.uri,
            'next': self.request.get('next')
            }
        
        path = os.path.join(os.path.dirname(__file__), os.path.join('templates', 'login.html'))
        self.response.out.write(template.render(path, template_context, debug=conf.DEBUG))

        if (status == 0): status = 200    
        self.response.set_status(status)

        return status

    def post(self):
        """ It tries to log the user in. If login is successful, 
            the view redirects to the URL specified in ``next``. If
            ``next`` isn't provided, it redirects to ```` (which is
            currently hard-coded). If login isn't successful, it redisplays the login form.
    
        """

        logging.debug('%s: post=> %s' % (self.__class__.__name__, self.request.POST))
        status = 0

        credential = [self.request.get('username_'), self.request.get('password_')]
        user = auth.authenticate(credential)
        
        url = ''
        if user is None:
            url = self.request.uri
            status = 401    # Unauthorized
            
        else:
            query = {}
            query['username'] = user.username
            query['password'] = user.password
            url = '%s?%s' % (self.request.get('next') , 
                             '&'.join('%s=%s' % (urllib.quote_plus(k.encode('utf8')),
                                                 urllib.quote_plus(v.encode('utf8')))
                             for k, v in query.iteritems()))
            status = 302    # Found
        
        self.response.set_status(status)        
        self.redirect(url)

        return status
    
      
class DownloadHandler(webapp.RequestHandler):
    def get(self):
        logging.debug('%s: get=> %s' % (self.__class__.__name__, self.request.GET))
        status = 0

        id = self.request.get('data_file')
        data_file = models.TestRunPhase.get_by_id(int(id)).data_file
        if data_file:
            self.response.headers['Content-Type'] = 'application/zip'
            self.response.out.write(data_file)
        else:
            status = 404    # Not found

        if (status == 0): status = 200    
        self.response.set_status(status)

        return status 


class ClientHandler(webapp.RequestHandler):
    user = None
        
    def _ping(self):
        status = 0
        if 'PING' in self.request.arguments():
            self.response.headers['Content-Type'] = 'text/html'
            self.response.out.write("Ping is successful.\n")
        else:
            status = 400
            
        return status
    
    def _submit(self):
        status = 0
        respond = ''
        if 'SUBMIT' in self.request.arguments():
            req_data_file = yaml.load(self.request.get('data'))
            data_file = req_data_file['modules']
           
            if not status and data_file.has_key('SubmitInfo'):
                if (data_file['SubmitInfo'].has_key('hostname') and 
                   data_file['SubmitInfo'].has_key('local_username') and
                   data_file['SubmitInfo'].has_key('http_username') and
                   data_file['SubmitInfo'].has_key('mtt_version')):     
                   
                    submits = models.SubmitInfo.all()
                    if (data_file['SubmitInfo']['hostname'] is not None): submits.filter('hostname =', str(data_file['SubmitInfo']['hostname']))
                    if (data_file['SubmitInfo']['local_username'] is not None): submits.filter('local_username =', str(data_file['SubmitInfo']['local_username']))
                    if (data_file['SubmitInfo']['http_username'] is not None): submits.filter('http_username =', str(data_file['SubmitInfo']['http_username']))
                    if (data_file['SubmitInfo']['mtt_version'] is not None): submits.filter('mtt_version =', str(data_file['SubmitInfo']['mtt_version']))

                    logging.debug("SubmitInfo count = %d\n" % submits.count())
                    if submits.count() == 0:
                        submit = models.SubmitInfo()
                        self.__fill_entity(submit, data_file['SubmitInfo'])
                        submit.put()
                    else:
                        submit = submits[0]
                else:
                    logging.error("Incorrect format of 'SubmitInfo'")
                    respond = "Incorrect format of 'SubmitInfo'"
                    status = 400
        
            if not status and data_file.has_key('MpiInfo'):
                if (data_file['MpiInfo'].has_key('mpi_name') and 
                    data_file['MpiInfo'].has_key('mpi_version') and  
                    data_file['MpiInfo'].has_key('oma_version')):            
                    
                    mpis = models.MpiInfo.all()
                    if (data_file['MpiInfo']['mpi_name'] is not None): mpis.filter('mpi_name =', str(data_file['MpiInfo']['mpi_name']))
                    if (data_file['MpiInfo']['mpi_version'] is not None): mpis.filter('mpi_version =', str(data_file['MpiInfo']['mpi_version']))
                    if (data_file['MpiInfo']['oma_version'] is not None): mpis.filter('oma_version =', str(data_file['MpiInfo']['oma_version']))
                    
                    logging.debug("MpiInfo count = %d\n" % mpis.count())
                    if mpis.count() == 0:
                        mpi = models.MpiInfo()
                        self.__fill_entity(mpi, data_file['MpiInfo'])
                        mpi.put()
                    else:
                        mpi = mpis[0]
                else:
                    logging.error("Incorrect format of 'MpiInfo'")
                    respond = "Incorrect format of 'MpiInfo'"
                    status = 400
        
            if not status and data_file.has_key('ClusterInfo'):
                if (data_file['ClusterInfo'].has_key('cluster_name') and 
                    data_file['ClusterInfo'].has_key('node_count') and
                    data_file['ClusterInfo'].has_key('node_hostname') and
                    data_file['ClusterInfo'].has_key('node_arch') and
                    data_file['ClusterInfo'].has_key('node_ncpu') and
                    data_file['ClusterInfo'].has_key('node_nsocket') and
                    data_file['ClusterInfo'].has_key('node_htt') and
                    data_file['ClusterInfo'].has_key('node_mem') and
                    data_file['ClusterInfo'].has_key('node_cache') and
                    data_file['ClusterInfo'].has_key('node_mhz') and
                    data_file['ClusterInfo'].has_key('node_os_kernel') and
                    data_file['ClusterInfo'].has_key('node_os_vendor') and
                    data_file['ClusterInfo'].has_key('node_os_release') and
                    data_file['ClusterInfo'].has_key('net_pci') and
                    data_file['ClusterInfo'].has_key('net_conf') and
                    data_file['ClusterInfo'].has_key('net_eth100') and
                    data_file['ClusterInfo'].has_key('net_eth1000') and
                    data_file['ClusterInfo'].has_key('net_eth10k') and
                    data_file['ClusterInfo'].has_key('net_iwarp') and
                    data_file['ClusterInfo'].has_key('net_ibddr') and
                    data_file['ClusterInfo'].has_key('net_ibqdr')):
                           
                    clusters = models.ClusterInfo.all()
                    if (data_file['ClusterInfo']['cluster_name'] is not None): clusters.filter('cluster_name =', data_file['ClusterInfo']['cluster_name'])
                    if (data_file['ClusterInfo']['node_count'] is not None): clusters.filter('node_count =', data_file['ClusterInfo']['node_count'])
                    if (data_file['ClusterInfo']['node_hostname'] is not None): clusters.filter('node_hostname =', data_file['ClusterInfo']['node_hostname'])
                    if (data_file['ClusterInfo']['node_arch'] is not None): clusters.filter('node_arch =', data_file['ClusterInfo']['node_arch'])
                    if (data_file['ClusterInfo']['node_ncpu'] is not None): clusters.filter('node_ncpu =', data_file['ClusterInfo']['node_ncpu'])
                    if (data_file['ClusterInfo']['node_nsocket'] is not None): clusters.filter('node_nsocket =', data_file['ClusterInfo']['node_nsocket'])
                    if (data_file['ClusterInfo']['node_htt'] is not None): clusters.filter('node_htt =', data_file['ClusterInfo']['node_htt'])
                    if (data_file['ClusterInfo']['node_mem'] is not None): clusters.filter('node_mem =', data_file['ClusterInfo']['node_mem'])
                    if (data_file['ClusterInfo']['node_cache'] is not None): clusters.filter('node_cache =', data_file['ClusterInfo']['node_cache'])
                    if (data_file['ClusterInfo']['node_mhz'] is not None): clusters.filter('node_mhz =', data_file['ClusterInfo']['node_mhz'])
                    if (data_file['ClusterInfo']['node_os_kernel'] is not None): clusters.filter('node_os_kernel =', str(data_file['ClusterInfo']['node_os_kernel']))
                    if (data_file['ClusterInfo']['node_os_vendor'] is not None): clusters.filter('node_os_vendor =', str(data_file['ClusterInfo']['node_os_vendor']))
                    if (data_file['ClusterInfo']['node_os_release'] is not None): clusters.filter('node_os_release =', str(data_file['ClusterInfo']['node_os_release']))
                    if (data_file['ClusterInfo']['net_eth100'] is not None): clusters.filter('net_eth100 =', data_file['ClusterInfo']['net_eth100'])
                    if (data_file['ClusterInfo']['net_eth1000'] is not None): clusters.filter('net_eth1000 =', data_file['ClusterInfo']['net_eth1000'])
                    if (data_file['ClusterInfo']['net_eth10k'] is not None): clusters.filter('net_eth10k =', data_file['ClusterInfo']['net_eth10k'])
                    if (data_file['ClusterInfo']['net_iwarp'] is not None): clusters.filter('net_iwarp =', data_file['ClusterInfo']['net_iwarp'])
                    if (data_file['ClusterInfo']['net_ibddr'] is not None): clusters.filter('net_ibddr =', data_file['ClusterInfo']['net_ibddr'])
                    if (data_file['ClusterInfo']['net_ibqdr'] is not None): clusters.filter('net_ibqdr =', data_file['ClusterInfo']['net_ibqdr'])

                    logging.debug("ClusterInfo count = %d\n" % clusters.count())
                    if clusters.count() == 0:
                        cluster = models.ClusterInfo()
                        self.__fill_entity(cluster, data_file['ClusterInfo'])
                        cluster.put()
                    else:
                        cluster = clusters[0]
                else:
                    logging.error("Incorrect format of 'ClusterInfo'")
                    respond = "Incorrect format of 'ClusterInfo'"
                    status = 400
        
            if not status and data_file.has_key('CompilerInfo'):
                if (data_file['CompilerInfo'].has_key('compiler_name') and 
                   data_file['CompilerInfo'].has_key('compiler_version')):     
                   
                    compilers = models.CompilerInfo.all()
                    if (data_file['CompilerInfo']['compiler_name'] is not None): compilers.filter('compiler_name =', str(data_file['CompilerInfo']['compiler_name']))
                    if (data_file['CompilerInfo']['compiler_version'] is not None): compilers.filter('compiler_version =', str(data_file['CompilerInfo']['compiler_version']))
                   
                    logging.debug("CompilerInfo count = %d\n" % compilers.count())
                    if compilers.count() == 0:
                        compiler = models.CompilerInfo()
                        self.__fill_entity(compiler, data_file['CompilerInfo'])
                        compiler.put()
                    else:
                        compiler = compilers[0]
                else:
                    logging.error("Incorrect format of 'CompilerInfo'")
                    respond = "Incorrect format of 'CompilerInfo'"
                    status = 400
                
            if not status and data_file.has_key('SuiteInfo'):
                if (data_file['SuiteInfo'].has_key('suite_name') and 
                   data_file['SuiteInfo'].has_key('suite_version')):     
                   
                    suites = models.SuiteInfo.all()
                    if (data_file['SuiteInfo']['suite_name'] is not None): suites.filter('suite_name =', str(data_file['SuiteInfo']['suite_name']))
                    if (data_file['SuiteInfo']['suite_version'] is not None): suites.filter('suite_version =', str(data_file['SuiteInfo']['suite_version']))
                   
                    logging.debug("SuiteInfo count = %d\n" % suites.count())
                    if suites.count() == 0:
                        suite = models.SuiteInfo()                        
                        self.__fill_entity(suite, data_file['SuiteInfo'])                        
                        suite.put()
                    else:
                        suite = suites[0]       
                else:
                    logging.error("Incorrect format of 'SuiteInfo'")
                    respond = "Incorrect format of 'SuiteInfo'"
                    status = 400
                
            if not status and data_file.has_key('MpiInstallPhase'):                         
                try:
                    submit, cluster, mpi, compiler
                    
                    mpi_install_phases = models.MpiInstallPhase.all()
                    mpi_install_phases.filter('submitinfo =', submit)
                    mpi_install_phases.filter('clusterinfo =', cluster)
                    mpi_install_phases.filter('mpiinfo =', mpi)
                    mpi_install_phases.filter('compilerinfo =', compiler)
                       
                    logging.debug("MpiInstallPhase count = %d\n" % mpi_install_phases.count())
                    if mpi_install_phases.count() == 0:
                        mpi_install_phase = models.MpiInstallPhase()
                        mpi_install_phase.submitinfo        = submit
                        mpi_install_phase.clusterinfo       = cluster
                        mpi_install_phase.mpiinfo           = mpi
                        mpi_install_phase.compilerinfo      = compiler        
                    
                        excluded_list = [ 
                                         'submitinfo',
                                         'clusterinfo',
                                         'mpiinfo',
                                         'compilerinfo'
                                         ]
                        self.__fill_entity(mpi_install_phase, data_file['MpiInstallPhase'], excluded_list, True)
    
                        mpi_install_phase.put()
                    else:
                        mpi_install_phase = mpi_install_phases[0]       

                except (NameError), err:
                    logging.error("Fatal error: error='%s'\n" % (err))
                    respond = "Fatal error"
                    status = 500                
                    
            if not status and data_file.has_key('TestBuildPhase'):                         
                try:
                    submit, cluster, mpi, compiler, suite, mpi_install_phase                    
                    
                    test_build_phases = models.TestBuildPhase.all()
                    test_build_phases.filter('submitinfo =', submit)
                    test_build_phases.filter('clusterinfo =', cluster)
                    test_build_phases.filter('mpiinfo =', mpi)
                    test_build_phases.filter('compilerinfo =', compiler)
                    test_build_phases.filter('suiteinfo =', suite)
                    test_build_phases.filter('mpiinstallphase =', mpi_install_phase)
                    
                    logging.debug("TestBuildPhase count = %d\n" % test_build_phases.count())
                    if test_build_phases.count() == 0:
                        test_build_phase = models.TestBuildPhase()
                        test_build_phase.submitinfo        = submit
                        test_build_phase.clusterinfo       = cluster
                        test_build_phase.mpiinfo           = mpi
                        test_build_phase.compilerinfo      = compiler
                        test_build_phase.suiteinfo         = suite
                        test_build_phase.mpiinstallphase   = mpi_install_phase
                    
                        excluded_list = [ 
                                         'submitinfo',
                                         'clusterinfo',
                                         'mpiinfo',
                                         'compilerinfo',
                                         'suiteinfo',
                                         'mpiinstallphase'
                                         ]
                        self.__fill_entity(test_build_phase, data_file['TestBuildPhase'], excluded_list, True)
    
                        test_build_phase.put()
                    else:
                        test_build_phase = test_build_phases[0]       

                except (NameError), err:
                    logging.error("Fatal error: error='%s'\n" % (err))
                    respond = "Fatal error"
                    status = 500                
                
            if not status and data_file.has_key('TestRunPhase'):                         
                try:
                    submit, cluster, mpi, compiler, suite, mpi_install_phase, test_build_phase

                    test_run_phase = models.TestRunPhase()
                    test_run_phase.submitinfo        = submit
                    test_run_phase.clusterinfo       = cluster
                    test_run_phase.mpiinfo           = mpi
                    test_run_phase.compilerinfo      = compiler
                    test_run_phase.suiteinfo         = suite
                    test_run_phase.mpiinstallphase   = mpi_install_phase
                    test_run_phase.testbuildphase    = test_build_phase
                    
                    excluded_list = [ 
                                     'submitinfo',
                                     'clusterinfo',
                                     'mpiinfo',
                                     'compilerinfo',
                                     'suiteinfo',
                                     'mpiinstallphase',
                                     'testbuildphase',
                                     'data_file'
                                     ]
                    self.__fill_entity(test_run_phase, data_file['TestRunPhase'], excluded_list, True)
                    
                    if 'raw' in self.request.arguments() : test_run_phase.data_file = db.Blob(self.request.get('raw'))
    
                    test_run_phase.cached_submitinfo_hostname               = submit.hostname
                    test_run_phase.cached_submitinfo_local_username         = submit.local_username
                    test_run_phase.cached_submitinfo_http_username          = submit.http_username
                    test_run_phase.cached_submitinfo_mtt_version            = submit.mtt_version
            
                    test_run_phase.cached_clusterinfo_cluster_name          = cluster.cluster_name
                    test_run_phase.cached_clusterinfo_node_count            = cluster.node_count
                    test_run_phase.cached_clusterinfo_node_hostname         = cluster.node_hostname
                    test_run_phase.cached_clusterinfo_node_arch             = cluster.node_arch
                    test_run_phase.cached_clusterinfo_node_ncpu             = cluster.node_ncpu
                    test_run_phase.cached_clusterinfo_node_nsocket          = cluster.node_nsocket
                    test_run_phase.cached_clusterinfo_node_htt              = cluster.node_htt
                    test_run_phase.cached_clusterinfo_node_mem              = cluster.node_mem
                    test_run_phase.cached_clusterinfo_node_cache            = cluster.node_cache
                    test_run_phase.cached_clusterinfo_node_mhz              = cluster.node_mhz
                    test_run_phase.cached_clusterinfo_node_os_kernel        = cluster.node_os_kernel
                    test_run_phase.cached_clusterinfo_node_os_vendor        = cluster.node_os_vendor
                    test_run_phase.cached_clusterinfo_node_os_release       = cluster.node_os_release
                    test_run_phase.cached_clusterinfo_net_eth100            = cluster.net_eth100
                    test_run_phase.cached_clusterinfo_net_eth1000           = cluster.net_eth1000
                    test_run_phase.cached_clusterinfo_net_eth10k            = cluster.net_eth10k
                    test_run_phase.cached_clusterinfo_net_iwarp             = cluster.net_iwarp
                    test_run_phase.cached_clusterinfo_net_ibddr             = cluster.net_ibddr
                    test_run_phase.cached_clusterinfo_net_ibqdr             = cluster.net_ibqdr
                    test_run_phase.cached_mpiinfo_mpi_name                  = mpi.mpi_name
                    test_run_phase.cached_mpiinfo_mpi_version               = mpi.mpi_version
                    test_run_phase.cached_mpiinfo_oma_version               = mpi.oma_version
                    test_run_phase.cached_compilerinfo_compiler_name        = compiler.compiler_name
                    test_run_phase.cached_compilerinfo_compiler_version     = compiler.compiler_version
                    test_run_phase.cached_suiteinfo_suite_name              = suite.suite_name
                    test_run_phase.cached_suiteinfo_suite_version           = suite.suite_version
                    test_run_phase.cached_mpiinstallphase_mpi_path          = mpi_install_phase.mpi_path
    
                    test_run_phase.put()
                    
                except (NameError), err:
                    logging.error("Fatal error: error='%s'\n" % (err))
                    respond = "Fatal error"
                    status = 500                
            
            self.response.headers['Content-Type'] = 'text/html'
            self.response.out.write("Data is submitted.\n" )        
        else:
             status = 400
             
        return status
    
    def _query(self):
        status = 0
        respond = ''
        if 'QUERY' in self.request.arguments():
            query_str = ''
            if ('gql' in self.request.arguments()):
                query_str = self.request.get('gql')
                if (not query_str):
                    status = 400
                    
                if (not status):
                    match = re.search(r"\s+[Ff][Rr][Oo][Mm]\s+([\w]+)\s*", query_str)
                    available_set = [ 'TestRunPhase', 'TestBuildPhase', 'MpiInstallPhase' ]
                    if (not match is None and 
                        not match.group(1) in available_set): 
                        query_str = ''
                        status = 400   

                if (not status):
                    try:
                        (query_str, status) = gql_ex(query_str)
                        
                        if (not status and query_str):
                            query = db.GqlQuery(query_str)
                            result_set = query
                            result_count = 0
                            # query.count() is not used because of count() ignores the LIMIT clause on GQL queries.
                            for result in result_set:
                                result_count += 1
                    except (datastore_errors.BadQueryError, datastore_errors.BadFilterError, db.KindError), err:
                        logging.error("Incorrect GQL line: <_query> GQL='%s' error='%s'\n" % 
                                          (query_str, err))
                        respond = str(err)
                        status = 400                
                    except (datastore_errors.NeedIndexError), err:
                        logging.error("No matching index found: <_query> GQL='%s' error='%s'\n" % 
                                          (query_str, err))
                        respond = str(err)
                        status = 400                
            
            if not status and result_set:
                data_file = {}
                data_file['count'] = result_count
                data_file['data'] = []
                for entity in result_set:
                    raw = None
                    data_entity = {}
                    data_entity['key'] = "key_%s" % str(entity.key().id())
                    data_entity['modules'] = {}
                    entities_list = [ entity ]
                    
                    if 'no-ref' not in self.request.arguments():
                        for prop in entity.properties().values():
                            if (datastore.typename(prop) in ['ReferenceProperty']):
                                val = prop.get_value_for_datastore(entity)
                                if val is not None:
                                    query_entity = db.GqlQuery("select * from %s where __key__=key('%s')" % (val.kind(), val))
                                    entities_list.append(query_entity.get())
                    
                    for temp_entity in entities_list:
                        key_dict = {}
                        for prop in temp_entity.properties().values():
                            if (datastore.typename(prop) not in ['BlobProperty', 'ReferenceProperty']):
                                val = prop.get_value_for_datastore(temp_entity)
                    
                                if (datastore.typename(prop) in ['EmailProperty', 'BooleanProperty']):
                                    val = str(val)
                                elif (datastore.typename(prop) in ['TextProperty']):
                                    val = unicode(val)
                                    
                                if val is None or val == 'unknown':
                                    val = ''
                    
                                key_dict[prop.name] = val
    
                            if ( prop.name == 'data_file' and
                                 'no-raw' not in self.request.arguments() and 
                                 datastore.typename(prop) in ['BlobProperty']):
                                raw = str(prop.get_value_for_datastore(temp_entity))
                                if (raw is not None): data_entity['raw'] = raw
        
                        for prop in temp_entity.dynamic_properties():
                            val = temp_entity.__getattr__(prop)
    
                            if (type(val).__name__ not in ['Blob', 'Key']):                
                                if (type(val).__name__ in ['Email', 'BooleanProperty']):
                                    val = str(val)
                                elif (type(val).__name__ in ['Text']):
                                    val = unicode(val)
                                    
                                if val is None or val == 'unknown':
                                    val = ''
                    
                                key_dict[prop] = val
                        
                        data_entity['modules'][temp_entity.kind()] = key_dict

                    data_file['data'].append(data_entity)
                
                respond = yaml.safe_dump(data_file, default_flow_style=False, canonical=False)
                
            self.response.headers['Content-Type'] = 'text/yaml'
            self.response.out.write(respond)        
        else:
            status = 400
            
        return status
    

    def _view(self):
        status = 0
        respond = ''
        if 'VIEW' in self.request.arguments():
            
            data = []
            query_str = ''
            if ('gql' in self.request.arguments()):
                query_str = self.request.get('gql')
                if (not query_str):
                    status = 400
                    
                if (not status and not self.user.is_superuser):
                    match = re.search(r"\s+[Ff][Rr][Oo][Mm]\s+([\w]+)\s*", query_str)
                    exception_set = [ 'User' ]
                    if (not match is None and match.group(1) in exception_set):
                        query_str = ''
                        status = 400   
                    
            elif (self.request.get('kind') == 'all'):
                key_values = {}
                model_set = [   
                             models.MpiInstallPhase,
                             models.TestBuildPhase,
                             models.TestRunPhase,
                             models.SubmitInfo,
                             models.SuiteInfo,
                             models.MpiInfo,
                             models.ClusterInfo,
                             models.CompilerInfo
                             ]
                for model in model_set:
                    key_values = self.__get_info(model)                        
                    data.append({'tag': str(model.kind()), 'data': key_values})
                    
            elif (self.request.get('kind') == 'suite'):
                query_str = 'select * from SuiteInfo'
                
            elif (self.request.get('kind') == 'mpi'):
                query_str = 'select * from MpiInfo'
                
            elif (self.request.get('kind') == 'compiler'):
                query_str = 'select * from CompilerInfo'
                
            elif (self.request.get('kind') == 'cluster'):
                query_str = 'select * from ClusterInfo'
                
            else :
                query_str = ''
            
            try:
                (query_str, status) = gql_ex(query_str)
                
                if (not status and query_str):
                    if (re.search(r"\s*[Ss][Ee][Ll][Ee][Cc][Tt]\s+([Cc][Oo][Uu][Nn][Tt]\s*\(\s*\*\s*\)\s+)", query_str)):
                        query_str = re.sub(r"\s*[Ss][Ee][Ll][Ee][Cc][Tt]\s+([Cc][Oo][Uu][Nn][Tt]\s*\(\s*\*\s*\)\s+)", "select * ", query_str)
                        query = db.GqlQuery(query_str)
                        result_set = query
                        # query.count() is not used because of count() ignores the LIMIT clause on GQL queries.
                        result_count = 0
                        for result in result_set:
                            result_count += 1
                            
                        key_values = {'count': [str(result_count)]}
                        data.append({'tag': '', 'data': key_values})
                        
                    elif (re.search(r"\s*[Ss][Ee][Ll][Ee][Cc][Tt]\s+([\w\,\s]+)\s+[Ff][Rr][Oo][Mm]", query_str)):
                        match = re.search(r"\s*[Ss][Ee][Ll][Ee][Cc][Tt]\s+([\w\,\s]+)\s+[Ff][Rr][Oo][Mm]", query_str)
                        query_str = re.sub(r"\s*[Ss][Ee][Ll][Ee][Cc][Tt]\s+([\w\,\s]+)\s+[Ff][Rr][Oo][Mm]", "select * from", query_str)
                        fields = []
                        fields = re.split('\W+', match.group(1))
                        
                        query = db.GqlQuery(query_str)
                        result_set = query
        
                        key_values = {}
                        key_values = get_table_data(result_set)
                        
                        data.append({'tag': '', 'data': {}})
                        for key in fields:
                            if key_values.has_key(key):
                                data[0]['data'][key] = key_values[key]
        
                    elif (query_str):    
                        query = db.GqlQuery(query_str)
                        result_set = query
            
                        key_values = {}
                        key_values = get_table_data(result_set)
                        if key_values.has_key('_key_'): 
                            del key_values['_key_']
                            
                        data.append({'tag': '', 'data': key_values})
                        
            except (datastore_errors.BadQueryError, datastore_errors.BadFilterError, db.KindError), err:
                logging.error("Incorrect GQL line: <_view> GQL='%s' error='%s'\n" % 
                                    (query_str, err))
                respond = str(err)
                status = 400                
            except (datastore_errors.NeedIndexError), err:
                logging.error("No matching index found: <_query> GQL='%s' error='%s'\n" % 
                                    (query_str, err))
                respond = str(err)
                status = 400                
                
            if (not status and 
                'format' in self.request.arguments()):
                if (self.request.get('format') == 'txt'):
                    respond += self.__do_txt(data, len(data))
                elif (self.request.get('format') == 'html'):
                    respond += self.__do_html(data, len(data))
                elif (self.request.get('format') == 'yaml'):
                    respond += self.__do_yaml(data, len(data))
                elif (self.request.get('format') == 'raw'):
                    respond += str(data)
                respond += '\n'
                    
            self.response.headers['Content-Type'] = 'text/html'
            self.response.out.write(respond)
        else:
            status = 400
            
        return status 

    def __fill_entity(self, entity, data, excluded_list = None, dynamic = False):
        """Fill entity with values from data.

        """
        if (excluded_list is None): 
            excluded_list = []
        
        for key, value in data.iteritems():
            # Set field values that are defined in model
            if (key in entity.properties() and 
                value is not None and
                key not in excluded_list):
                try:
                    prop = entity.properties()[key]
                    if (datastore.typename(prop) in ['FloatProperty']):
                        entity.__setattr__(key, prop.validate(float(value)))
                    elif (datastore.typename(prop) in ['IntegerProperty']):
                        entity.__setattr__(key, prop.validate(int(value)))
                    elif (datastore.typename(prop) in ['StringProperty']):
                        entity.__setattr__(key, prop.validate(str(value)))
                    elif (datastore.typename(prop) in ['TextProperty']):
                        entity.__setattr__(key, prop.validate(unicode(value)))
                    else:
                        entity.__setattr__(key, prop.validate(value))
                except (datastore_errors.BadValueError, TypeError), err:
                    logging.error("Incorrect value: <__fill_entity> entity=%s field=%s value=%s %s error='%s'\n" % 
                                  (entity.kind(), key, value, value.__class__, err))

            # Dynamically set field values that are not defined
            elif (dynamic == True and
                  key not in entity.properties() and
                  value is not None):
                # This code gives possibility to limit adding dynamic fields by prefix
                is_field_added = False
                for field_prefix in ['data_', 'custom_']:
                    if (string.find(key, field_prefix) == 0):                    
                        entity.__setattr__(key, value)
                        is_field_added = True
                        logging.debug("Added dynamic field: <__fill_entity> entity=%s field=%s value=%s %s\n" % 
                                          (entity.kind(), key, value, value.__class__))
                        break
                if (is_field_added == False):
                    logging.error("Incorrect dynamic field: <__fill_entity> entity=%s field=%s value=%s %s\n" % 
                                    (entity.kind(), key, value, value.__class__))
            
            # Undefined field - value pair
            elif (value is not None):
                logging.error("Invalid field: <__fill_entity> entity=%s field=%s value=%s %s\n" % 
                                (entity.kind(), key, value, value.__class__))
                    

    def __get_info(self, model):
        """Returns the union of model names used by the given list of models.

        We return the union as a dictionary mapping the model names to a property
        information.
        """
        key_dict = {'name': [], 'type': []}
        for key, prop in sorted(model.properties().iteritems()):
            key_dict['name'].append(str(key))
            key_dict['type'].append(str(datastore.typename(prop)))
            
        return key_dict

    def __do_html(self, dataset, count):
        """Returns the html-formated respond.

        """
        form = ''
        # set head
        form += """
<head>
    <title>MTT-VIEW</title>
    <style type="text/css">
        h3 { 
            font-size: 90%;
            font-family: Verdana, Arial, Helvetica, sans-serif;
            color: #333366 
            }
        p, td, th { 
            font-size: 80%;
            font-family: Verdana, Arial, Helvetica, sans-serif;
            color: #000000 
            }
       }
    </style>
</head>"""
        for j in range(count):
    
            data = dataset[j]['data']
            row_count = 0;
            i = 0;
            width = {};
    
            # calculate size of data
            for key, values in sorted(data.iteritems()):
                if  (len(data[key]) > row_count): row_count = len(values)
                width[key] = len(key);
                for i in range(len(values)):
                    if  (len(data[key][i]) > width[key]): width[key] = len(data[key][i]) 
            
            if (dataset[j].has_key('tag') and dataset[j]['tag']):
                form += "<h3>" + str(dataset[j]['tag']) + "</h3>"
            
            # set table
            form += "<table unit='EN' border='0' cellspacing='0' cellpadding='0'>"
    
            # dispaly names of columns
            form += "<tr>"
            for key in sorted(data.keys()):
                form += "<th width=" + str(width[key] + 3) + ">" + str(key) + "</th>"
            form += "</tr>"
            
            form += "<tr><th colspan='" + str(len(data.keys())) + "'><hr noshade size='2' align='left' color='#C0C0C0'></th></tr>"
            
            # show data 
            for i in range(row_count):
                if i % 2: 
                    form += "<tr bgcolor='#F0F0F0'>"
                else:
                    form += "<tr bgcolor='#FFFFFF'>"
                for key, values in sorted(data.iteritems()):
                    form += "<td>"
                    if ( i < len(data[key]) and data[key][i] != ''):
                        form += data[key][i];
                    else:
                        form += ''
                    form += "</td>"
                form += "</tr>"
    
            form += "<tr><th colspan='" + str(len(data.keys())) + "'><hr noshade size='2' align='left' color='#C0C0C0'></th></tr>"
    
            form += "</table>"
            form += "<p>total: " + str(row_count) + "</p>"
            form += "<br>"

        return form

    def __do_txt(self, dataset, count):
        """Returns the txt-formated respond.

        """        
        form = ''
        for j in range(count):
    
            data = dataset[j]['data']
            row_count = 0
            format = ''
            i = 0
            width = {}
    
            # calculate size of data
            for key, values in sorted(data.iteritems()):
                if  (len(data[key]) > row_count): row_count = len(values)
                width[key] = len(key);
                for i in range(len(values)):
                    if  (len(data[key][i]) > width[key]): width[key] = len(data[key][i]) 
            
            if (dataset[j].has_key('tag') and dataset[j]['tag']):
                form += str(dataset[j]['tag'])
            
            # dispaly names of columns
            form += "\n"
            for key in sorted(data.keys()):
                format = "%-" + str(width[key]) + "s   "
                form += format % key
                
            form += "\n"
            for key in sorted(data.keys()):
                form += "-" * width[key]
                form += "   "
                    
            # show data 
            form += "\n"
            for i in range(row_count):
                for key, values in sorted(data.iteritems()):
                    if ( i < len(data[key]) and data[key][i] != ''):
                        format = "%-" + str(width[key]) + "s   "
                        form += format % str(data[key][i])
                    else:
                        format = "%-" + str(width[key]) + "s   "
                        form += format % ''
                form += "\n"
    
            form += "\n"
            form += "total: " + str(row_count)
            form += "\n"

        return form

    def __do_yaml(self, dataset, count):
        """Returns the yaml-formated respond.

        """
        form = yaml.safe_dump(dataset, default_flow_style=False, canonical=False);

        return form

    def _admin(self):
        status = 0
        if 'ADMIN' in self.request.arguments():
            if ('_NEWUSER_' in self.request.arguments()):                
                user = auth.add_user(username = self.request.get('username'),
                                     password = self.request.get('password'),
                                     email = self.request.get('email'),
                                     first_name = self.request.get('first_name'),
                                     last_name = self.request.get('last_name'))
                if user is None:
                    status = 400
                else:                   
                    self.response.headers['Content-Type'] = 'text/html'
                    self.response.out.write("Operation has been completed successfully.\n")
        else:
            status = 400
            
        return status
    
    def post(self):
        logging.debug('%s: post=> %s' % (self.__class__.__name__, self.request.POST))
        status = 0
        respond = ''

        self.user = auth.authenticate(auth.get_credential())
        if self.user is None:
            status = 401    # Unauthorized
        try:
            if not status and 'PING' in self.request.arguments():
                status = self._ping();
            elif not status and 'SUBMIT' in self.request.arguments():
                status = self._submit();
            elif not status and 'QUERY' in self.request.arguments():
                status = self._query();
            elif not status and 'VIEW' in self.request.arguments():
                status = self._view();
            elif not status and 'ADMIN' in self.request.arguments():
                if self.user.is_superuser:
                    status = self._admin()
                else:
                    status = 403    # Forbidden
            elif not status:
                status = 400    # Bad Request
        
        except (datastore_errors.Timeout, DeadlineExceededError), err:
            logging.error("The timeout exception handling: error='%s'\n" % (err))
            respond = "Response time deadline has been reached\n" + str(err) 
            self.response.out.write(respond)
            status = 500                
        
        if (status == 0): status = 200    
        self.response.set_status(status)

        return status 
           

def gql_ex(query_str):
    """GQL extended implementation.

    """
    status = 0
        
    # The LIKE operator is used in a WHERE clause to search for a part of string value in a column.
    # Example: select * from T where F like ''
    (query_str, status) = re.subn(r"\s+(?P<filter>(?P<field>\w+)\s+[Ll][Ii][Kk][Ee]\s+[\'](?P<value>[^']+)[\'])\s*", 
                                    " \g<field> >= \'\g<value>\' and \g<field> < \'\g<value>" +"\xEF\xBF\xBD".decode('utf-8') + "\' ", query_str)
        
    # The usage of SELECT clause inside IN operation
    # Example: select * from T where F in (select * from T1)
    if (status == 0):
        match = re.search(r"\s+((\w+)\s+[Ii][Nn]\s*\(\s*\"(\s*[Ss][Ee][Ll][Ee][Cc][Tt]\s+[^\"]+)\"\s*\))\s*", query_str)            
        if (match is not None):
            status = 1 
            try:
                query = db.GqlQuery(match.group(3))
                result_set = query
            except (datastore_errors.BadQueryError, datastore_errors.BadFilterError, db.KindError), err:
                logging.error("Incorrect GQL line: <gql_ex> GQL='%s' error='%s'\n" % 
                                (match.group(3), err))
                return (query_str, 400)

            key_values = {}
            key_values = get_table_data(result_set)
            # We use only one entity because it is not supported by GQL F in (key()[,key()]) construction
            # so we should do F=key() only for single entity
            if key_values.has_key('_key_'):
                replace_str = ' ' + match.group(2) + '='
                for value in key_values['_key_']:
                    replace_str += "KEY('" + str(value) + "') "
                    break
                replace_str += ''
                query_str = query_str.replace(match.group(1), replace_str)
            else:
                return (query_str, 501) # Not Implemented
        
    if status: 
        (query_str, status) = gql_ex(query_str)
    else :
        logging.debug("GQL query: <gql_ex> \'%s\' status = %d\n" % (query_str, status))
        
    return (query_str, status)


def get_table_data(entities):
    """Returns the union of key names used by the given list of entities.

    We return the union as a dictionary mapping the key names to a sample
    value from one of the entities for the key name.
    """
    key_dict = {}
    for entity in entities:
        if key_dict.has_key('_key_'):
            key_dict['_id_'].append(str(entity.key().id()))
            key_dict['_key_'].append(str(entity.key()))
        else:
            key_dict['_id_'] = [str(entity.key().id())]
            key_dict['_key_'] = [str(entity.key())]
        for prop in entity.properties().values():
            val = prop.get_value_for_datastore(entity)

            if (datastore.typename(prop) in ['BlobProperty']):
                val = 'blob'
            elif (datastore.typename(prop) in ['ReferenceProperty']):
                val = str(val)
            elif (datastore.typename(prop) in ['EmailProperty', 'BooleanProperty']):
                val = str(val)
            elif (datastore.typename(prop) in ['TextProperty']):
                val = unicode(val)
                
            if val is None or val == 'unknown':
                val = ''

            if key_dict.has_key(prop.name):
                key_dict[prop.name].append(str(val))
            else:
                key_dict[prop.name] = [str(val)]

        for prop in entity.dynamic_properties():
            val = entity.__getattr__(prop)

            if (type(val).__name__ in ['Blob']):
                val = 'blob'
            elif (type(val).__name__ in ['Key']):
                val = str(val)
            elif (type(val).__name__ in ['Email', 'bool']):
                val = str(val)
            elif (type(val).__name__ in ['Text']):
                val = unicode(val)

            if val is None or val == 'unknown':
                val = ''

            if key_dict.has_key(prop):
                key_dict[prop].append(str(val))
            else:
                key_dict[prop] = [str(val)]

    return key_dict


application = webapp.WSGIApplication(
                                     [('/', MainPage),
#                                      ('/login/*', LoginHandler),
                                      ('/get', DownloadHandler),
                                      ('/client', ClientHandler)
                                     ], debug=True)

def main():
    if conf.DEBUG:
        logging.getLogger().setLevel(logging.DEBUG)
    run_wsgi_app(application)

if __name__ == "__main__":
    main()

