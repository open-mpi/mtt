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
import logging
import cStringIO
import mimetypes
import re

# Python Google AppEngine SDK modules
import yaml
from google.appengine.api import users
from google.appengine.api import datastore
from google.appengine.api import datastore_errors
from google.appengine.api import datastore_types

from google.appengine.ext import db
from google.appengine.ext import webapp
from google.appengine.ext.webapp.util import login_required
from google.appengine.ext.webapp.util import run_wsgi_app
from google.appengine.ext.webapp import template

# Private modules
import conf
import auth


class AdminPage(webapp.RequestHandler):
    "Admin place"
    @login_required
    def get(self):
        logging.debug('%s: get=> %s' % (self.__class__.__name__, self.request.GET))
        status = 0
        
        if not users.is_current_user_admin():
            status = 401
        else:
            template_context = {
                'current_user': users.get_current_user()
                }
        
            path = os.path.join(os.path.dirname(__file__), os.path.join('../templates', 'admin.html'))
            self.response.out.write(template.render(path, template_context, debug=conf.DEBUG))

        if (status == 0): status = 200    
        self.response.set_status(status)

        return status


class AddUserHandler(webapp.RequestHandler):
    def post(self):
        logging.debug('%s: post=> %s' % (self.__class__.__name__, self.request.POST))
        status = 0

        if not users.is_current_user_admin():
            status = 401
        else:
            user = auth.add_user(username = self.request.get('username_'),
                                 password = self.request.get('password_'),
                                 email = self.request.get('email_'),
                                 first_name = self.request.get('first_name_'),
                                 last_name = self.request.get('last_name_'),
                                 is_superuser = self.request.get('is_superuser_')
                                 )
            
        if (status == 0): status = 200    
        self.response.set_status(status)
        
        self.redirect('/admin/')

        return status


application = webapp.WSGIApplication(
                                     [('/admin/', AdminPage),
                                      ('/admin/adduser', AddUserHandler)
                                     ], debug=True)

def main():
    if conf.DEBUG:
        logging.getLogger().setLevel(logging.DEBUG)
    run_wsgi_app(application)

if __name__ == "__main__":
    main()

