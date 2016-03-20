"""
Dispatchers implementing the MTT Server API.

Exports:
    Root: Root directoy
"""

#
# https://cherrypy.readthedocs.org/en/3.3.0/tutorial/REST.html
#

import os
import pprint
import copy
import glob
import logging
import json
import random
import string
import datetime
import re
import base64

from subprocess import call

import cherrypy
from configobj import ConfigObj
from validate import Validator

from webapp.db_pgv3 import DatabaseV3

#
# JSON serialization of datetime objects
#
class _JSONEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, datetime.date):
            return obj.isoformat()
        # timedelta does not have a isoformat
        elif isinstance(obj, datetime.timedelta):
            return str(obj).split('.',2)[0]
        return super().default(obj)

_json_encoder = _JSONEncoder()

def _json_handler(*args, **kwargs):
    # Adapted from cherrypy/lib/jsontools.py
    value = cherrypy.serving.request._json_inner_handler(*args, **kwargs)

    return _json_encoder.iterencode(value)


class _ServerResourceBase:
    """Provide functionality needed by all resource dispatchers.

    Class Attrs:
        exposed (bool): If True, resource is accessible via the Web.

    Instance Attrs
        conf (ConfigObj): Application config object.
        logger (logging.Logger): Pre-configured application logging instance.
        api_root (str): URL of application's api root.
        url_base (str): Base URL for the resource.

    Methods:
        ...
    """

    exposed = True

    _db = None

    def __init__(self, conf):
        """Instantiate Server Resource.

        Args:
            conf (ConfigObj): Application configuration object.
        """
        self.conf = conf
        self.logger = logging.getLogger('mtt')

        server = None
        if 'url_docroot' in conf['server'].keys():
            server = conf['server']['url_docroot']
        else:
            server = conf['server']['socket_host'] + ':' + str(conf['server']['socket_port'])

        self.url_base = (server + '/' + self.__class__.__name__.lower() + '/')
        self.api_root = (server + '/api/')

        #
        # Define the Database connection - JJH TODO
        #
        self.logger.debug("Setup database connection")
        _db_settings = conf["pg_v3"]
        self._db = DatabaseV3(self.logger, _db_settings)
        if self._db is None or self._db.is_available() is False:
            sys.exit(-1)
        self._db.connect()
        self.logger.debug("Conected to the database!")

    def __del__(self):
        self._db.disconnect()

    def _extract_http_username(self, auth):
        tmp = auth
        try:
            tmp = base64.b64decode(tmp[6:len(tmp)])
            return tmp.split(':')[0]
        except:
            return "(unknown)"

    def _not_implemented(self, prefix):
        self.logger.debug(prefix + " Not implemented")
        rtn = {}
        rtn['status'] = -1
        rtn['status_message'] = prefix + " Please implement this method..."
        return rtn

    def _return_error(self, prefix, code, msg):
        self.logger.debug(prefix + " Error ("+str(code)+") = " + msg)
        rtn = {}
        rtn['status'] = code
        rtn['status_message'] = msg
        return rtn

########################################################
 

########################################################
# Root
########################################################
class Root(_ServerResourceBase):

    #
    # GET / : Server status
    #
    @cherrypy.tools.json_out()
    def GET(self, **kwargs):
        prefix = '[GET /]'
        self.logger.debug(prefix)

        rtn = {}
        rtn['status'] = 0
        rtn['status_message'] = 'Success'

        return rtn

    #
    # POST /:cmd
    #
    @cherrypy.tools.json_out()
    @cherrypy.tools.json_in()
    def POST(self, cmd, **kwargs):
        prefix = '[POST /%s]' % str(cmd)
        self.logger.debug(prefix)

        rtn = {}
        rtn['status'] = 0
        rtn['status_message'] = 'Success'
    
        if cmd == "serial":
            self.logger.debug('%s reply with serial' % prefix)
            rtn['client_serial'] = self._db.get_client_serial()
            return rtn
        else:
            self.logger.error(prefix + " Invalid operation")
            raise cherrypy.HTTPError(400)

        return rtn


########################################################
# Submit
########################################################
class Submit(_ServerResourceBase):
    _phase_unknown     = -1
    _phase_mpi_install = 0
    _phase_test_build  = 1
    _phase_test_run    = 2

    #
    # POST /submit/
    #
    @cherrypy.tools.json_out()
    @cherrypy.tools.json_in()
    def POST(self, **kwargs):
        prefix = '[POST /submit/]'
        self.logger.debug(prefix)

        if not hasattr(cherrypy.request, "json"):
            self.logger.error(prefix + " No json data sent")
            raise cherrypy.HTTPError(400)

        data = cherrypy.request.json
        if 'metadata' not in data.keys():
            self.logger.error(prefix + " No 'metadata' in json data")
            raise cherrypy.HTTPError(400)

        if 'phase' not in data['metadata'].keys():
            self.logger.error(prefix + " No 'phase' in 'metadata' in json data")
            raise cherrypy.HTTPError(400)

        phase = self._convert_phase(data["metadata"]['phase'])
        self.logger.debug( "Phase: %2d = [%s]" % (phase, data["metadata"]['phase']) )

        if 'data' not in data.keys():
            self.logger.error(prefix + " No 'data' array in json data")
            raise cherrypy.HTTPError(400)

        data['metadata']['http_username'] = self._extract_http_username(cherrypy.request.headers['Authorization'])

        # self.logger.debug( json.dumps( data, \
        #                                sort_keys=True, \
        #                                indent=4, \
        #                                separators=(',', ': ') ) )

        rtn = {}
        rtn['status'] = 0
        rtn['status_message'] = 'Success'

        #
        # Get the submission id
        # The client could be submitting one they want us to use,
        # otherwise create a new one.
        #
        submit_info = {}
        if 'submit_id' in data['metadata'].keys() and data['metadata']['submit_id'] > 0:
            self.logger.debug( "************** submit_id: Existing %s" % (str(data['metadata']['submit_id'])) )
            submit_info = {'submit_id': data['metadata']['submit_id']}
        else:
            self.logger.debug( "************** submit_id: New...")
            submit_info = self._db.get_submit_id(data['metadata'])

        #
        # Submit each entry to the database
        #
        ids = []
        for entry in data['data']:
            value = None

            if phase is self._phase_mpi_install:
                value = self._db.insert_mpi_install(submit_info['submit_id'], data['metadata'], entry)
            elif phase is self._phase_test_build:
                value = self._db.insert_test_build(submit_info['submit_id'], data['metadata'], entry)
            elif phase is self._phase_test_run:
                value = self._db.insert_test_run(submit_info['submit_id'], data['metadata'], entry)
            else:
                self.logger.error( "Unkown phase...")

            if value is None:
                #ids.append( {'error':'failed to submit this run'} )
                return self._return_error(prefix, -1, "%s Failed to submit an entry (unknown reason)" % (prefix))
            elif 'error_msg' in value.keys():
                return self._return_error(prefix, -2, value['error_msg'])
            else:
                ids.append( value )

        #
        # Return the ids for each of those submissions
        #
        rtn['submit_id'] = submit_info['submit_id']
        rtn['ids'] = ids

        return rtn

    #
    # Convert phase name
    #
    def _convert_phase(self, phase_str):
        phase_str = phase_str.lower()
        phase_str = phase_str.replace(' ', '_')

        if re.match(r'mpi_install', phase_str):
            return self._phase_mpi_install
        elif re.match(r'test_build', phase_str):
            return self._phase_test_build
        elif re.match(r'test_run', phase_str):
            return self._phase_test_run
        else:
            return self._phase_unknown
