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
import datetime
import re

# Python Google AppEngine SDK modules
from google.appengine.ext import db

# Private modules


class User(db.Model):
    username     = db.StringProperty(required=True)
    is_superuser = db.BooleanProperty(default=False)
    is_active    = db.BooleanProperty(default=True)
    last_login   = db.DateTimeProperty()
    created      = db.DateTimeProperty(auto_now_add=True)
    modified     = db.DateTimeProperty(auto_now=True)
           
    def __str__(self):
        return str(self.username)

    def __unicode__(self):
        return unicode(self.username)

    def get_full_name(self):
        "Returns the first_name plus the last_name, with a space in between."
        full_name = '%s %s' % (self.first_name, self.last_name)
        return full_name.strip()
       
    def check_password(self, raw_password):
        import urllib
        import logging
        from google.appengine.api import urlfetch 
        
        request_body = urllib.urlencode({'Email': self.username,
                                         'Passwd': raw_password,
                                         'accountType': 'HOSTED_OR_GOOGLE',
                                         'service': 'ah',
                                         'source': 'test'})
        auth_response = urlfetch.fetch('https://www.google.com/accounts/ClientLogin',
                                       method=urlfetch.POST,
                                       headers={'Content-type':'application/x-www-form-urlencoded',
                                                'Content-Length':
                                                    str(len(request_body))},
                                       payload=request_body)
        auth_dict = dict(x.split("=") for x in auth_response.content.split("\n") if x)
        auth_token = auth_dict.has_key("Auth")

        return auth_token
