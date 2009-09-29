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
    password     = db.StringProperty()
    email        = db.EmailProperty(required=True)
    first_name   = db.StringProperty()
    last_name    = db.StringProperty()
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
       
    def set_password(self, raw_password):
        import sha, random
        
        algorithm = 'sha1'
        salt = sha.new(str(random.random())).hexdigest()[:5]
        hash = sha.new(salt+raw_password).hexdigest()
            
        self.password = '|'.join((algorithm, hash, salt))
       
    def check_password(self, raw_password, password):
        import sha
              
        (algorithm, hash, salt) = self.password.split('|')
        return hash == sha.new(salt + raw_password).hexdigest()
