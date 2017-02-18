from django.shortcuts import render
from django.http import HttpResponse
from django.template import RequestContext
from django.views.decorators.csrf import csrf_protect

import requests
from requests.auth import HTTPBasicAuth
import json
import pwd
import os

# Communicate with MTT Database

MTT_USERNAME = "mtt"
MTT_PWFILE = None
MTT_PASSWORD = "mttuser"
MTT_URL = "http://localhost:9080"

def get_mtt_data(phase, fields, search={}):

    password = None
    if MTT_PWFILE is not None and os.path.exists(MTT_PWFILE):
        f = open(MTT_PWFILE, 'r')
        password = f.readline().strip()
        f.close()
    elif MTT_PASSWORD is not None:
        password = MTT_PASSWORD

    url = MTT_URL + "/summary"
    www_auth = HTTPBasicAuth(MTT_USERNAME, password)

    headers = {}
    headers['content-type'] = 'application/json'

    metadata = {}
    metadata['http_username'] = MTT_USERNAME

    query = {}
    query['columns'] = fields
    query['search'] = search
    query['phase'] = phase

    payload = {}
    payload['metadata'] = metadata
#    payload['query'] = query
    payload['columns'] = fields
    payload['search'] = search
    payload['phase'] = phase

    s = requests.Session()
    r = s.post(url,
               data=json.dumps(payload),
               headers=headers,
               auth=www_auth,
               verify=False)

    if r.status_code != 200:
        print "ERROR: html status code is not successful"
        return None
    if 'query_data' not in r.json():
        print "ERROR: RESTful return json not in correct format."
        return None
    return r.json()['query_data']

# Main view

import webapp.dispatchers
from configobj import ConfigObj

@csrf_protect
def index(request):

    # Initialize Output Variables
    display_content_type = ""
    display_content_data = []
    display_content_fields = []

    # Check for input
    if request.method == "POST":

        o = webapp.dispatchers._ServerResourceBase(\
                ConfigObj('/pluto_home/rtbarell/mtt_rtb/server/php/cherrypy/bin/mtt_server.cfg',
                          configspec='/pluto_home/rtbarell/mtt_rtb/server/php/cherrypy/src/mtt_server.cfgspec'))
        db = o._db

        if "view_test_run_results" in request.POST and \
                request.POST["view_test_run_results"] == "View Test Run Results":
            display_content_type = "Test Run Results"
            display_content_data = get_mtt_data("test_run", ["start_timestamp", "test_result", "submit_timestamp", "duration", "exit_value", "exit_signal", "test_name"])

        if "view_mpi_install_results" in request.POST and \
                request.POST["view_mpi_install_results"] == "View MPI Install Results":
            display_content_type = "MPI Install Results"
            display_content_data = get_mtt_data("install", ["start_timestamp", "test_result", "submit_timestamp", "duration", "exit_value", "exit_signal", "test_name"])

        if "view_test_build_results" in request.POST and \
                request.POST["view_test_build_results"] == "View Test Build Results":
            display_content_type = "Test Build Results"
            display_content_data = get_mtt_data("test_build", ["start_timestamp", "test_result", "submit_timestamp", "duration", "exit_value", "exit_signal", "test_name"])

        if display_content_data:
            display_content_fields = display_content_data[0].keys()
        else:
            display_content_fields = []
        display_content_data = [[row[f] for f in display_content_fields] for row in display_content_data]

    # Return output
    return render(request, "main_template.html",
                  {"display_content_type": display_content_type,
                   "display_content_data": display_content_data,
                   "display_content_fields": display_content_fields}) 
