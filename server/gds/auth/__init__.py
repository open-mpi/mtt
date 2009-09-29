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
import re
import base64
import urllib

# Python Google AppEngine SDK modules
from google.appengine.api import users
from google.appengine.ext import db

# Private modules
from models import User
import logging


def check_login(handler_method):
    """
    A decorator to require that a user be logged in to access a handler.
    """
    def check(self, *args):
        logging.debug('check_login %s: <%s> admin = %s user = %s' % 
                      (self.__class__.__name__, self.request.method, str(users.is_current_user_admin()), str(self.user)))

        if not users.is_current_user_admin() and self.user is None:
            if self.request.method == 'GET':
                credential = [self.request.get('username'), self.request.get('password')]
                self.user = authenticate(credential)
                if self.user is None:
                    self.redirect('%s?%s=%s' % ('/login/', 'next', urllib.quote(self.request.uri)))
                    return
            elif self.request.method == 'POST':
                self.user = authenticate(get_credential())
                if self.user is None:
                    self.response.set_status(401) # Unauthorized
                    return

        handler_method(self, *args)
    
    return check
            

def get_credential():
    """
    Get credentials from http request.
    """
    credential = None
    if os.environ.has_key('HTTP_AUTHORIZATION'):
       http_authorization=os.environ['HTTP_AUTHORIZATION']
       if http_authorization[:6].lower() == 'basic ':
           try: decoded=base64.decodestring(http_authorization[6:])
           except base64.binascii.Error: decoded=''
           credential = decoded.split(':')
       else:
           credential = ['', '']

    logging.debug('get_credential: %s' % credential)
    
    return credential


def authenticate(credential):
    """
    If the given credentials are valid, return a User object.
    """
    if credential is None:
        return None
        
    query = db.Query(User)
    users = query.filter('username =', credential[0])

    if users.count()>1:
        logging.error("There are several users with username = '%s' " % credential[0])
        return None
    
    users = query.filter('is_active =', True)
    user = users.get()

    if user:
        if ((not user.check_password(raw_password = credential[1], password = user.password)) and
            (user.password != credential[1])): 
            user = None

    logging.debug('authenticate: %s' % str(user))
    
    return user


def add_user(**credential):
    """
    Create new User objects using passed credentials and return a User object.
    """
    logging.debug('add_user: %s' % str(credential))

    user = None
    email_re = re.compile(r'[\w\d\.\-\+]+@[\w\d\.\-\+]+\.[\w\d\.\-\+]+')
    if (not credential.has_key('email') or 
        not email_re.match(credential['email'])):
        logging.error("Invalid email = '%s'" % (credential['email']))
        return user
        
    query = db.Query(User)
    query_users = query.filter('username =', credential['username'])
    if query_users.count()>1:
        logging.error("There are several users with username = '%s' and email = '%s'" % (credential['username'], credential['email']))
        user = query_users.get()   
    elif (credential.has_key('username') and 
          credential.has_key('password')):
        user = User(username = credential['username'],
                    email = credential['email']
                    )
        user.set_password(credential['password'])
        if (credential.has_key('first_name')): user.first_name = credential['first_name']
        if (credential.has_key('last_name')): user.last_name = credential['last_name']
        if (credential.has_key('is_superuser') and
            credential['is_superuser'].lower() in ('yes', 'true')): user.is_superuser = True
        else:
            user.is_superuser = False
        user.is_active = True

        user.put()
    
    return user
