#!src/env/bin/python

"""Initialize and launch the MTT REST server."""

import logging
import os
import signal
import socket
import sys

import cherrypy
from cherrypy.process.plugins import Daemonizer, PIDFile
from configobj import ConfigObj
from validate import Validator

from webapp.dispatchers import Root, Submit

def _CORS():
    """Set HTTP Access Control Header to allow cross-site HTTP requests from
    any origin.
    """
    if cherrypy.request.method == 'OPTIONS':
        cherrypy.response.headers['Access-Control-Allow-Origin'] = '*'
        cherrypy.response.headers['Access-Control-Allow-Headers'] = 'Content-Type'
        cherrypy.response.headers['Access-Control-Allow-Methods'] = '*'
        return True
    else:
        cherrypy.response.headers['Access-Control-Allow-Origin'] = '*'

def _term_handler(signal, frame):
    """Gracefully shutdown the server and exit.

    This function is intended to be registered as a SIGTERM handler.
    """
    logger = logging.getLogger('mtt')
    logger.info('Shutting down server')

    cherrypy.engine.exit()
    logger.info('Exiting')
    sys.exit(0)

def _restart_handler(signal, frame):
    """Restart the server.

    This function is intended to be registered as a SIGHUP handler.
    """
    logger = logging.getLogger('mtt')
    logger.info('Restarting server')
    # FIXME: This needs to reload the config, including attrs in
    # mtt_config.cfg.
    cherrypy.engine.restart()
    logger.debug('Blocking cherrypy engine')
    cherrypy.engine.block()

if __name__ == '__main__':
    script_dir = os.path.dirname(os.path.realpath(__file__))

    # Default conf. Some of these can/will be overrided by attrs in
    # mtt_config.cfg.
    conf = {
        'global': {
            'server.socket_host': socket.gethostbyname(socket.gethostname()),
            'log.access_file': '../log/access.log',
            'log.error_file': '../log/cherrypy_error.log',
            'log.screen': False,
            'engine.autoreload.on': False,

            # Don't run CherryPy Checker on custom conf sections:
            # FIXME: This setting doesn't seem to be working...
            'checker.check_internal_config': False,
        },

        '/': {
            'tools.sessions.on': True,
            'tools.proxy.on': True,
            'tools.response_headers.on': True,
            'request.dispatch': cherrypy.dispatch.MethodDispatcher(),
            'tools.CORS.on': True
        },

        'internal': {
            'PIDfile': script_dir + '/.mtt_server.pid',
            'log_level': 'INFO',
            'mtt_log_file': '../log/mtt.log'
        }
    }

    #
    # Load mtt_config.cfg and integrate appropriate attrs into cherrpy conf.
    #
    cfg = ConfigObj('../bin/mtt_server.cfg',
                    configspec='mtt_server.cfgspec')
    cfg.validate(Validator())
    if 'server' in cfg.keys():
        for k in cfg['server']:
            conf['global']['server.' + k] = cfg['server'][k]
    
    if 'logging' in cfg.keys():
        if 'log_level' in cfg['logging'].keys():
            conf['internal']['log_level'] = cfg['logging']['log_level']
        if 'log_file' in cfg['logging'].keys():
            log_file = cfg['logging']['log_file']
            if not log_file.startswith('/'):
                # Path is relative to mtt_config.cfg location
                log_file = '../' + cfg['logging']['log_file']
            conf['internal']['mtt_log_file'] = log_file

    cfg['tmp_dir'] = os.getcwd() + "/../"

    cherrypy.config.update(conf)

    #
    # Set up logging.
    #
    log_levels = {
        'DEBUG': logging.DEBUG,
        'INFO': logging.INFO,
        'WARNING': logging.WARNING,
        'ERROR': logging.ERROR,
        'CRITICAL': logging.CRITICAL
    }
    logger = logging.getLogger('mtt')
    logger.setLevel(log_levels[conf['internal']['log_level']])
    handler = logging.FileHandler(conf['internal']['mtt_log_file'])
    handler.setFormatter(
        logging.Formatter('[%(asctime)s] %(levelname)s %(message)s'))
    logger.addHandler(handler)
    logger.info('Logging at %s to %s' % (conf['internal']['log_level'],
                                         conf['internal']['mtt_log_file']))

    # Log the PID
    PIDFile(cherrypy.engine, conf['internal']['PIDfile']).subscribe()

    #
    # Setup the service
    #
    Daemonizer(cherrypy.engine).subscribe()
    cherrypy.tools.CORS = cherrypy._cptools.HandlerTool( _CORS )

    cherrypy.tree.mount(Root(cfg),       '/',           conf)
    cherrypy.tree.mount(Submit(cfg),     '/submit',     conf)

    logger.info('Starting cherrypy engine')
    cherrypy.engine.start()
    logger.debug('Registering signal handlers')
    signal.signal(signal.SIGTERM, _term_handler)
    signal.signal(signal.SIGHUP, _restart_handler)
    logger.debug('Blocking cherrypy engine')
    cherrypy.engine.block()

