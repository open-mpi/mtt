"""
Postgresql v3 database interface
"""

import os
import pprint
import psycopg2
import string
import re
import json
from threading import Lock
import sys
import datetime

VALID_FIELD_TYPES = ["str", "bool", "int", "float", "str_list", "bool_list", "int_list", "float_list"]
FIELD_INFO = {
"platform_name":          {"type": "str", 
                           "desc": "Custom name of the platform (e.g., \"my-cluster\")",
                           "disp": "platform_name",
                           "table": "compute_cluster"},
"platform_hardware":      {"type": "str",
                           "desc": "String representation of the hardware (e.g., \"x86_64\")",
                           "disp": "platform_hardware",
                           "table": "compute_cluster"},
"platform_type":          {"type": "str",
                           "desc": "String representation of the platform type (e.g., \"linux-rhel6.7-x86_64\")",
                           "disp": "platform_type",
                           "table": "compute_cluster"},
"os_name":                {"type": "str",
                           "desc": "Common name for the OS (e.g., \"Linux\")",
                           "disp": "os_name",
                           "table": "compute_cluster"},
"os_version":             {"type": "str",
                           "desc": "Version information for the OS (e.g., \"Linux 2.6.32-573.12.1.e16.x86_64\")",
                           "disp": "os_version",
                           "table": "compute_cluster"},
"hostname":               {"type": "str",
                           "desc": "The hostname where the test ras run",
                           "disp": "hostname",
                           "table": "submit"},
"local_username":         {"type": "str",
                           "desc": "The local username of the host",
                           "disp": "local_username",
                           "table": "submit"},
"http_username":          {"type": "str",
                           "desc": "TODO",
                           "disp": "http_username",
                           "table": "submit"},
"mtt_client_version":     {"type": "str",
                           "desc": "Version of the client you are running",
                           "disp": "mtt_client_version",
                           "table": "submit"},
"compiler_name":          {"type": "str",
                           "desc": "Common name for the compiler (e.g., \"gnu\")",
                           "disp": "compiler_name",
                           "table": "compiler"},
"compiler_version":       {"type": "str",
                           "desc": "Version string for the compiler (e.g., \"4.4.7\")",
                           "disp": "compiler_version",
                           "table": "compiler"},
"mpi_name":               {"type": "str",
                           "desc": "A name for the MPI version (e.g., \"ompi-nightly-v1.10\")",
                           "disp": "mpi_name",
                           "table": "mpi_get"},
"mpi_version":            {"type": "str",
                           "desc": "Version strin reported by MPI (e.g., \"v1.10.2-114-gf3bad94\")",
                           "disp": "mpi_version",
                           "table": "mpi_get"},
"description":            {"type": "str",
                           "desc": "Text description of this test",
                           "disp": "description",
                           "table": "description"},
"result_message":         {"type": "str",
                           "desc": "A string representation of the test result (e.g., \"Success\" or \"Failed; timeout expired (00:10 DD:HH:MM:SS)\")",
                           "disp": "result_message",
                           "table": "result_message"},
"environment":            {"type": "str",
                           "desc": "Any environment variables of note (usually this is blank)",
                           "disp": "environment",
                           "table": "environment"},
"vpath_mode":             {"type": "int",
                           "desc": "If the code was compiled using a VPATH build: 1 = relative path, 2 = absolute path, 0 = unknown (default)",
                           "disp": "vpath_mode",
                           "table": "mpi_install_configure_args"},
"bitness":                {"type": "int",
                           "desc": "The bitness of the machine: 1 = 8 bit, 2 = 16 bit, 4 = 32 bit, 6 = 32/64 bit, 8 = 64 bit, 16 = 128 bit, \"unknown\" = unknown bitness",
                           "disp": "bitness",
                           "table": "mpi_install_configure_args"},
"configure_arguments":    {"type": "str",
                           "desc": "TODO",
                           "disp": "configure_arguments",
                           "table": "mpi_install_configure_args"},
"start_timestamp":        {"type": "str",
                           "desc": "Timestamp when the test started",
                           "disp": "start_timestamp",
                           "table": "results_fields"},
"test_result":            {"type": "int",
                           "desc": "A numerical classification of the test result: 0 = failed, 1 = passed, 2 = skipped, 3 = timed out, -1 = unknown",
                           "disp": "test_result",
                           "table": "results_fields"},
"trial":                  {"type": "bool",
                           "desc": "Whether this is a trial run: 0 = false, 1 = true",
                           "disp": "trial",
                           "table": "results_fields"},
"submit_timestamp":       {"type": "str",
                           "desc": "TODO",
                           "disp": "submit_timestamp",
                           "table": "results_fields"},
"duration":               {"type": "str",
                           "desc": "Time taken interval (e.g. \"322 seconds\", default \"0 seconds\")",
                           "disp": "duration",
                           "table": "results_fields"},
"result_stdout":          {"type": "str",
                           "desc": "stdout of the process",
                           "disp": "result_stdout",
                           "table": "results_fields"},
"result_stderr":          {"type": "str",
                           "desc": "stderr of the process",
                           "disp": "result_stderr",
                           "table": "results_fields"},
"merge_stdout_stderr":    {"type": "bool",
                           "desc": "If the output was merged: 0 = false, 1 = true",
                           "disp": "merge_stdout_stderr",
                           "table": "results_fields"},
"exit_value":             {"type": "int",
                           "desc": "The return code of the process (e.g., \"0\")",
                           "disp": "exit_value",
                           "table": "results_fields"},
"exit_signal":            {"type": "int",
                           "desc": "TODO",
                           "disp": "exit_signal",
                           "table": "results_fields"},
"client_serial":          {"type": "int",
                           "desc": "A valid integer from a previous call to /serial",
                           "disp": "client_serial",
                           "table": "results_fields"},
"suite_name":             {"type": "str",
                           "desc": "A name for the test suite (e.g., \"trivial\")",
                           "disp": "suite_name",
                           "table": "test_suites"},
"test_suite_description": {"type": "str",
                           "desc": "A description for the test suite",
                           "disp": "test_suite_description",
                           "table": "test_suites"},
"test_name":              {"type": "str",
                           "desc": "A name for the test - usually the binary name (e.g., \"hello_c\")",
                           "disp": "test_name",
                           "table": "test_name"},
"test_name_description":  {"type": "str",
                           "desc": "A description for the test",
                           "disp": "test_description",
                           "table": "test_name"},
"message_size":           {"type": "int_list",
                           "desc": "TODO",
                           "disp": "message_size",
                           "table": "latency_bandwidth"},
"bandwidth_min":          {"type": "float_list",
                           "desc": "TODO",
                           "disp": "bandwidth_min",
                           "table": "latency_bandwidth"},
"bandwidth_max":          {"type": "float_list",
                           "desc": "TODO",
                           "disp": "bandwidth_max",
                           "table": "latency_bandwidth"},
"bandwidth_avg":          {"type": "float_list",
                           "desc": "TODO",
                           "disp": "bandwidth_avg",
                           "table": "latency_bandwidth"},
"latency_min":            {"type": "float_list",
                           "desc": "TODO",
                           "disp": "latency_min",
                           "table": "latency_bandwidth"},
"latency_max":            {"type": "float_list",
                           "desc": "TODO",
                           "disp": "latency_max",
                           "table": "latency_bandwidth"},
"latency_avg":            {"type": "float_list",
                           "desc": "TODO",
                           "disp": "latency_avg",
                           "table": "latency_bandwidth"},
"interconnect_name":      {"type": "str",
                           "desc": "TODO",
                           "disp": "interconnect_name",
                           "table": "interconnects"},
"launcher":               {"type": "str",
                           "desc": "Binary name of what was used to launch the process (e.g., \"mpirun\")",
                           "disp": "launcher",
                           "table": "test_run_command"},
"resource_mgr":           {"type": "str",
                           "desc": "String representation of the resource manager used (e.g. \"slurm\")",
                           "disp": "resource_manager",
                           "table": "test_run_command"},
"parameters":             {"type": "str",
                           "desc": "Breakdown the command line parameters (often we just send \"\", server will try to discover from command)",
                           "disp": "parameters",
                           "table": "test_run_command"},
"network":                {"type": "str",
                           "desc": "String representation of the network (often we just send \"\", server will try to discover from command)",
                           "disp": "network",
                           "table": "test_run_command"},
"np":                     {"type": "int",
                           "desc": "Number of processes used (input to mpirun command)",
                           "disp": "np",
                           "table": "test_run"},
"full_command":           {"type": "str",
                           "desc": "The full command line string used",
                           "disp": "command",
                           "table": "test_run"},
"test_name":              {"type": "str",
                           "desc": "Name of the test",
                           "disp": "test_name",
                           "table": "test_names"},
"test_name_description":  {"type": "str",
                           "desc": "Description of the test",
                           "disp": "test_description",
                           "table": "test_names"},
}

FIELD_TYPES = {f:d["type"] for f,d in FIELD_INFO.items()}
assert(sum([0 if t in VALID_FIELD_TYPES else 1 for t in FIELD_TYPES.values()]) == 0)

FIELD_NAMES_MAPPING = {d["disp"]:f for f,d in FIELD_INFO.items()}

COMMON_FIELDS = [f for f,d in FIELD_INFO.items() if d["table"] == "results_fields"]

TABLE_TREE = {
"environment":                 {"parents": ["mpi_install", "test_build", "test_run"], "key": "environment_id",           "foreign_key": "environment_id"},
"result_message":              {"parents": ["mpi_install", "test_build", "test_run"], "key": "result_message_id",        "foreign_key": "result_message_id"},
"description":                 {"parents": ["mpi_install", "test_build", "test_run"], "key": "description_id",           "foreign_key": "description_id"},
"compute_cluster":             {"parents": ["mpi_install", "test_build", "test_run"], "key": "compute_cluster_id",       "foreign_key": "compute_cluster_id"},
"compiler":                    {"parents": ["mpi_install", "test_build", "test_run"], "key": "compiler_id",              "foreign_key": "mpi_install_compiler_id"},
"mpi_get":                     {"parents": ["mpi_install", "test_build", "test_run"], "key": "mpi_get_id",               "foreign_key": "mpi_get_id"},
"mpi_install_configure_args":  {"parents": ["mpi_install", "test_build", "test_run"], "key": "mpi_install_configure_id", "foreign_key": "mpi_install_configure_id"},
"submit":                      {"parents": ["mpi_install", "test_build", "test_run"], "key": "submit_id",                "foreign_key": "submit_id"},
"test_names":                  {"parents": ["test_run"],                              "key": "test_name_id",             "foreign_key": "test_name_id"},
"test_suites":                 {"parents": ["test_build", "test_run", "test_names"],  "key": "test_suite_id",            "foreign_key": "test_suite_id"},
"performance":                 {"parents": ["test_run"],                              "key": "performance_id",           "foreign_key": "performance_id"},
"test_run_command":            {"parents": ["test_run"],                              "key": "test_run_command_id",      "foreign_key": "test_run_command_id"},
"test_run_networks":           {"parents": ["test_run_command"],                      "key": "test_run_network_id",      "foreign_key": "test_run_network_id"},
"interconnects":               {"parents": ["test_run_networks"],                     "key": "interconnect_id",          "foreign_key": "interconnect_id"},
"latency_bandwidth":           {"parents": ["performance"],                           "key": "latency_bandwidth_id",     "foreign_key": "latency_bandwidth_id"},
}

TABLE_ORDER = ["environment", "result_message", "description", "compute_cluster", "compiler", "mpi_get", "mpi_install_configure_args", "submit", "test_names", "test_suites", "performance", "test_run_command", "test_run_networks", "interconnects", "latency_bandwidth"]

FIELDS_TABLE = {f:d["table"] for f,d in FIELD_INFO.items()}

TABLE_TREE_TABLES = TABLE_TREE.keys()
FIELD_INFO_TABLES = set([v["table"] for v in FIELD_INFO.values()])

for t in TABLE_ORDER:
    assert t in TABLE_TREE_TABLES, "%s in TABLE_ORDER not in TABLE_TREE_TABLES" % (t)
for t in TABLE_TREE_TABLES:
    assert t in TABLE_ORDER, "%s in TABLE_TREE_TABLES not in TABLE_ORDER" % (t)
for t in FIELD_INFO_TABLES:
    if t == "results_fields" or t == "mpi_install" or t == "test_build" or t == "test_run":
        continue
    assert t in TABLE_ORDER, "%s in FIELD_INFO_TABLES not in TABLE_ORDER" % (t)

class DatabaseV3():
    _name = '[DB PG V3]'

    _force_trial = True
    
    def __init__(self, logger, auth):
        self._auth = auth
        self._logger = logger

        self._connection = None

    ##########################################################
    def is_available(self):
        if None == self._auth.get("type") or None == self._auth["type"]:
            self._logger.error(self._name + "Error: Configuration settings missing the \"type\" field")
            return False
        if None == self._auth.get("dbname") or None == self._auth["dbname"]:
            self._logger.error(self._name + "Error: Configuration settings missing the \"dbname\" field")
            return False
        if None == self._auth.get("username") or None == self._auth["username"]:
            self._logger.error(self._name + "Error: Configuration settings missing the \"username\" field")
            return False
        if None == self._auth.get("password") or None == self._auth["password"]:
            self._logger.error(self._name + "Error: Configuration settings missing the \"password\" field")
            return False
        return True

    ##########################################################
    def is_connected(self):
        if self._connection is not None:
            return True
        else:
            return False

    def connect(self):
        conn_str = ("dbname=" +   str(self._auth["dbname"]) +
                    " user=" +    str(self._auth["username"]) +
                    " password="+ str(self._auth["password"]) +
                    " host="+     str(self._auth["server"]) +
                    " port="+     str(self._auth["port"]) )
        self._connection = psycopg2.connect( conn_str )

    def get_cursor(self):
        # Don't forget to: _cursor.close()
        return self._connection.cursor()

    def disconnect(self):
        self._connection.commit()
        self._connection.close()
        self._connection = None

    ##########################################################
    def _fields(self, table_name):
        cursor = self.get_cursor()
        select_stmt = "SELECT column_name FROM information_schema.columns WHERE table_name='" + table_name + "';"
        self._logger.debug("%s _column_names() %s" % (self._name, select_stmt) )

        cursor.execute( select_stmt, [] )
        row = cursor.fetchone()
        result = []
        while row is not None:
            result.append(row[0])
            row = cursor.fetchone()

        cursor.close()
        return result

    ##########################################################
    def __find_last_occurence(self, lst, itemlst):
        for item in reversed(lst):
            if item in itemlst:
                return item
        return None

    ##########################################################
    def _is_a_parent(self, parent_names, table_name):
        """Recursive check if a table has at least one table in the parent list in its ancestery
        parent_names is a list
        table_name is a string
        returns boolean
        """
        if table_name not in TABLE_TREE:
            return False
        for table in TABLE_TREE[table_name]['parents']:
            if table in parent_names:
                return True
        for table in TABLE_TREE[table_name]['parents']:
            if self._is_a_parent(parent_names, table):
                return True
        return False

    def _is_a_parent_of_any(self, parent_names, table_names):
        for t in table_names:
            if self._is_a_parent(parent_names, t):
                return True
        return False

    def _summary_compare(self, row1, row2):
        """row1 is from combiner and row2 is from result
        """
        for k,v in row2.items():
            if v != row1[k]:
                return False
        return True

    def _summary_find_in_combiner(self, combiner, row):
        for i,r in enumerate(combiner):
            if self._summary_compare(r,row):
                return i
        return -1

    def _summary(self, phase, columns, search, options=[]):
        self._logger.debug("%s _summary()" % (self._name))

        data = self._detail(phase, list(set(columns + ["test_result"])), search, options=options)

        combiner = []
        for row in data:
            combiner_ind = self._summary_find_in_combiner(combiner, row)
            if combiner_ind == -1:
                newrow = row.copy()
                newrow["test_result_failed"]   = 0
                newrow["test_result_passed"]   = 0
                newrow["test_result_skipped"]  = 0
                newrow["test_result_timed_out"] = 0
                newrow["test_result_unknown"]  = 0
                combiner.append(newrow)
            if combiner[combiner_ind]["test_result"] == 0:
                combiner[combiner_ind]["test_result_failed"] += 1 
            elif combiner[combiner_ind]["test_result"] == 1:
                combiner[combiner_ind]["test_result_passed"] += 1
            elif combiner[combiner_ind]["test_result"] == 2:
                combiner[combiner_ind]["test_result_skipped"] += 1
            elif combiner[combiner_ind]["test_result"] == 3:
                combiner[combiner_ind]["test_result_timed_out"] += 1
            else:
                combiner[combiner_ind]["test_result_unknown"] += 1

        if "test_result" not in columns:
            for row in combiner:
                del row["test_result"]

        return combiner
        
    def _select_item_in(self, selection, lst):
        for item in selection:
            if item in lst:
                return item
        return None

    def _detail(self, phase, columns, search, options=[]):
        self._logger.debug("%s _detail()" % (self._name))

        if "install" in phase:
            phase_name = "mpi_install"
        elif "test_build" in phase:
            phase_name = "test_build"
        elif "test_run" in phase:
            phase_name = "test_run"
        else:
            self._logger.debug("%s _summary() -- Invalid phase input" % (self._name))
            return None

        legal_columns = set([f for f in columns if f in COMMON_FIELDS \
                             or FIELDS_TABLE[FIELD_NAMES_MAPPING[f]] == phase_name \
                             or self._is_a_parent([phase_name], FIELDS_TABLE[FIELD_NAMES_MAPPING[f]])])

        legal_search = {k:v for k,v in search.items() if k in COMMON_FIELDS \
                             or FIELDS_TABLE[FIELD_NAMES_MAPPING[k]] == phase_name \
                             or self._is_a_parent([phase_name], FIELDS_TABLE[FIELD_NAMES_MAPPING[k]])}
        legal_search_columnnames = {"%s.%s" % (phase_name if k in COMMON_FIELDS else FIELDS_TABLE[FIELD_NAMES_MAPPING[k]],k):v for k,v in legal_search.items()}
        legal_search_keys = set(legal_search.keys())

        tables = set([FIELDS_TABLE[FIELD_NAMES_MAPPING[f]] for f in list(legal_columns) if f not in COMMON_FIELDS] + \
                     [FIELDS_TABLE[FIELD_NAMES_MAPPING[k]] for k in legal_search_keys if k not in COMMON_FIELDS])

        self._logger.debug("DEBUG (tables): %s" % (str(tables)))

        table_order = [t for t in TABLE_ORDER if t in tables or (t not in ["mpi_install", "test_build", "test_run"] and self._is_a_parent_of_any([t], tables))]

        self._logger.debug("DEBUG (table_order): %s" % (str(table_order)))

        select_stmt =  "SELECT %s " % (", ".join(legal_columns))
        select_stmt += "FROM %s " % (phase_name)
        select_stmt += "%s " % (" ".join(["INNER JOIN %s ON %s.%s = %s.%s " % (t,t,TABLE_TREE[t]["key"], self._select_item_in(TABLE_TREE[t]["parents"], [phase_name] + table_order[:i]), TABLE_TREE[t]["foreign_key"]) for i,t in enumerate(table_order)]))

        where_clause = " AND ".join(["%s = '%s'" % (k,v) for k,v in legal_search_columnnames.items()])
        if where_clause:
            select_stmt += "WHERE %s " % (where_clause)

        self._logger.debug("DEBUG (select_stmt): %s" % (select_stmt))

        cursor = self.get_cursor()
        cursor.execute( select_stmt )
        row = cursor.fetchone()

        result = []
        while row is not None:
            row = [str(v) if isinstance(v, datetime.date) or isinstance(v, datetime.timedelta) else v for v in row]
            result.append({field:val for field,val in zip(legal_columns,row)})
            row = cursor.fetchone()
        cursor.close()

        return result


    def _info_testsuite(self, search):
        self._logger.debug("%s _info_testsuite()" % (self._name))
        #TODO
        return None

    def _info_runtime(self, phase, search):
        self._logger.debug("%s _info_runtime()" % (self._name))
        #TODO
        return None
        
    ##########################################################
    def _find_value(self, metadata, data, field, aliases=None):
        for (key, value) in metadata.iteritems():
            if key == field:
                return value
            if aliases is not None:
                for alias in aliases:
                    if key == alias:
                        return value

        for (key, value) in data.iteritems():
            if key == field:
                return value
            if aliases is not None:
                for alias in aliases:
                    if key == alias:
                        return value

        return None
    
    ##########################################################
    def _convert_boolean(self, value):
        if value == 1:
            return 'true'
        else:
            return 'false'

    def _convert_vpath_mode(self, vpath):
        if vpath == "relative" or vpath == 1:
            return "01";
        elif vpath == "absolute" or vpath == 2:
            return "10";
        else:
            # unknown
            return "00";

    def _convert_endian(self, endian):
        if endian == "little" or endian == 1:
            return "01";
        elif endian == "big" or endian == 2:
            return "10";
        else:
            # unknown
            return "00";

    def _convert_bitness(self, bitness):
        # 8 bit
        if bitness == 1:
            return "000001";
        # 16 bit
        elif bitness == 2:
            return "000010";
        # 32/64 bit
        elif bitness == 4:
            return "001100";
        # 32 bit
        elif bitness == 6:
            return "000100";
        # 64 bit
        elif bitness == 8:
            return "001000";
        # 128 bit
        elif bitness == 16:
            return "010000";
        elif bitness == "unknown":
            return "000000";
        else:
            # unknown
            return "000000";

    ##########################################################
    def _get_nextval(self, seq_name):
        select_stmt = "SELECT nextval(%s) LIMIT 1"
        cursor = self.get_cursor()
        cursor.execute(select_stmt, (seq_name, ) )
        value = cursor.fetchone()[0]
        cursor.close()

        self._logger.debug("%s _get_nextval(%s) = %s " % (self._name, str(seq_name), str(value)) )

        return value

    ##########################################################
    def _select_insert(self, table, table_id, stmt_fields, stmt_values):
        found_id = -1

        #
        # Build the SELECT and INSERT statements
        #
        select_stmt = "\nSELECT %s FROM %s \n"  % (table_id, table)
        insert_stmt = "\nINSERT INTO %s \n (%s" % (table, table_id)

        count = 0
        for field in stmt_fields:
            insert_stmt = insert_stmt + ", " + field

            if count == 0:
                select_stmt = select_stmt + " WHERE "
            else:
                select_stmt = select_stmt + " AND "
            select_stmt = select_stmt + field + " = %s"
            count += 1

        select_stmt = select_stmt + "\n ORDER BY " + table_id + " ASC LIMIT 1"

        insert_stmt = insert_stmt + ") \nVALUES ("
        insert_stmt = insert_stmt + " %s"
        for value in stmt_values:
            insert_stmt = insert_stmt + ", %s"
        insert_stmt = insert_stmt + ")"

        #
        # Try the select to see if we need to insert
        #
        #self._logger.debug(select_stmt)

        cursor = self.get_cursor()

        values = tuple(stmt_values)
        cursor.execute( select_stmt, values )
        rows = cursor.fetchone()
        if rows is not None:
            found_id = rows[0]
            self._logger.debug("%s _select_insert(%s, %s) = [Found] %s" % (self._name, table, table_id, str(found_id)) )
            cursor.close()
            return found_id

        #
        # Insert this value
        #
        self._logger.debug(insert_stmt)
        self._logger.debug( ", ".join(str(x) for x in values) )
        found_id = self._get_nextval( "%s_%s_seq" % (table, table_id))

        stmt_values.insert(0, found_id)
        values = tuple(stmt_values)
        cursor.execute( insert_stmt, values )
        # Make sure to commit after every INSERT
        self._connection.commit()

        self._logger.debug("%s _select_insert(%s, %s) = [Insert] %s" % (self._name, table, table_id, str(found_id)) )

        cursor.close()

        return found_id

    ##########################################################
    def get_client_serial(self):
        return self._get_nextval( "client_serial" )

    ##########################################################
    def get_fields_for_submit(self):
        fields = ["hostname",
                  "local_username",
                  "http_username",
                  "mtt_client_version"]
        return {'required':fields, 'optional':[]}

    def get_submit_id(self, metadata):
        self._logger.debug( "************** Submit ****************" )

        
        fields = self.get_fields_for_submit()['required']
        values = []
        for field in fields:
            if field not in metadata.keys():
                return {"error_msg": "%s Missing field: %s" % ("submit_id", field)}
            elif metadata[field] is None:
                return {"error_msg": "%s Empty field: %s" % ("submit_id", field)}
            values.append(metadata[field])

        submit_id = self._select_insert("submit", "submit_id", fields, values)

        return {'submit_id': submit_id}

    ##########################################################
    def _find_mpi_install_id(self, submit_id, metadata, entry):
        cursor = self.get_cursor()

        # First look to see if it was sent from the client
        mpi_install_id = self._find_value(metadata, entry, 'mpi_install_id')

        # If it was then verify that it is valid
        if mpi_install_id is not None:
            self._logger.debug("%s _find_mpi_install_id() [Specified] %s" % (self._name, str(mpi_install_id)) )
            select_stmt = "SELECT mpi_install_id FROM mpi_install WHERE mpi_install_id = %s"
            cursor.execute( select_stmt, (mpi_install_id, ) )
            row = cursor.fetchone()
            if row is not None:
                self._logger.debug("%s _find_mpi_install_id() [Specified] %s (Valid)" % (self._name, str(mpi_install_id)) )
                cursor.close()
                return mpi_install_id
            else:
                self._logger.debug("%s _find_mpi_install_id() [Specified] %s (invalid)" % (self._name, str(mpi_install_id)) )

        # If not sent or invalid, then try to lookup (don't have enough information)
        # If cannot find then reference the 'dummy' row
        cursor.close()
        return 0

    ##########################################################
    def _get_mpi_install_info(self, mpi_install_id):
        cursor = self.get_cursor()
        fields = ["mpi_install_id",
                  "compute_cluster_id",
                  "mpi_install_compiler_id",
                  "mpi_get_id",
                  "mpi_install_configure_id"]
        select_stmt = "SELECT " + ", ".join(fields) + " FROM mpi_install WHERE mpi_install_id = %s"
        self._logger.debug("%s _get_mpi_install_info() %s [%s]" % (self._name, select_stmt, str(mpi_install_id)) )

        cursor.execute( select_stmt, (mpi_install_id, ) )
        row = cursor.fetchone()
        if row is None:
            cursor.close()
            return None

        count = 0
        result = {}
        for field in fields:
            result[field] = row[count]
            #self._logger.debug("%s _get_mpi_install_info() (%d) [%s]=[%s]" %(self._name, count, field, row[count]) )
            count += 1

        cursor.close()
        return result

    ##########################################################
    def _find_test_build_id(self, submit_id, metadata, entry):
        cursor = self.get_cursor()

        # First look to see if it was sent from the client
        test_build_id = self._find_value(metadata, entry, 'test_build_id')

        # If it was then verify that it is valid
        if test_build_id is not None:
            self._logger.debug("%s _find_test_build_id() [Specified] %s" % (self._name, str(test_build_id)) )
            select_stmt = "SELECT test_build_id FROM test_build WHERE test_build_id = %s"
            cursor.execute( select_stmt, (test_build_id, ) )
            row = cursor.fetchone()
            if row is not None:
                self._logger.debug("%s _find_test_build_id() [Specified] %s (Valid)" % (self._name, str(test_build_id)) )
                cursor.close()
                return test_build_id
            else:
                self._logger.debug("%s _find_test_build_id() [Specified] %s (invalid)" % (self._name, str(test_build_id)) )

        # If not sent or invalid, then try to lookup (don't have enough information)
        # If cannot find then reference the 'dummy' row
        cursor.close()
        return 0

    ##########################################################
    def _get_test_build_info(self, test_build_id):
        cursor = self.get_cursor()
        fields = ["test_build_id",
                  "mpi_install_id",
                  "compute_cluster_id",
                  "mpi_install_compiler_id",
                  "mpi_get_id",
                  "mpi_install_configure_id",
                  "test_suite_id",
                  "test_build_compiler_id"]

        select_stmt = "SELECT " + ", ".join(fields) + " FROM test_build WHERE test_build_id = %s"
        self._logger.debug("%s _get_test_build_info() %s [%s]" % (self._name, select_stmt, str(test_build_id)) )

        cursor.execute( select_stmt, (test_build_id, ) )
        row = cursor.fetchone()
        if row is None:
            cursor.close()
            return None

        count = 0
        result = {}
        for field in fields:
            result[field] = row[count]
            #self._logger.debug("%s _get_test_build_info() (%d) [%s]=[%s]" %(self._name, count, field, row[count]) )
            count += 1

        cursor.close()
        return result

    ##########################################################
    def _process_networks(self, network):
        test_run_network_id = 0

        #
        # Split network CSV
        #

        #
        # Generate an interconnect_id for each value in the CSV
        #

        #
        # Determine if we have established this notwork combination yet
        #

        #
        # If not then obtain a new test_run_network_id and insert it
        #

        # JJH TODO finish this function
        return test_run_network_id

    ##########################################################
    def get_fields_for_mpi_install(self):
        fields = ["platform_name",
                  "platform_hardware",
                  "platform_type",
                  "os_name",
                  "os_version",
                  "compiler_name",
                  "compiler_version",
                  "mpi_name",
                  "mpi_version",
                  "start_timestamp",
                  "result_message",
                  "test_result",
                  "trial",
                  "exit_value",
                  "client_serial"]

        optional = ["description",
                    "environment",
                    "duration",
                    "vpath_mode",
                    "bitness",
                    "endian",
                    "configure_arguments",
                    "exit_signal",
                    "merge_stdout_stderr",
                    "result_stdout",
                    "result_stderr"]

        return {'required':fields, 'optional':optional}

    def insert_mpi_install(self, submit_id, metadata, entry):
        prefix = self._name + " (mpi_install) "

        # self._logger.debug( "************** MPI Install ****************" )
        # self._logger.debug( json.dumps( entry, \
        #                                 sort_keys=True, \
        #                                 indent=4, \
        #                                 separators=(',', ': ') ) )
        # self._logger.debug( "************** Metadata ****************" )
        # self._logger.debug( json.dumps( metadata, \
        #                                 sort_keys=True, \
        #                                 indent=4, \
        #                                 separators=(',', ': ') ) )

        #
        # Process: compute_cluster
        #
        self._logger.debug("%s --- Processing: compute_cluster" % (prefix) )

        fields = ["platform_name",
                  "platform_hardware",
                  "platform_type",
                  "os_name",
                  "os_version"]
        values = []
        for field in fields:
            value = self._find_value(metadata, entry, field)
            if value is None:
                return {"error_msg": "%s Missing field: %s" % (prefix, field)} 
            values.append( value )

        compute_cluster_id = self._select_insert("compute_cluster", "compute_cluster_id", fields, values)

        self._logger.debug("%s --- Processing: compute_cluster = %s" % (prefix, str(compute_cluster_id)) )

        #
        # Process: mpi_install_compiler
        #
        self._logger.debug("%s --- Processing: mpi_install_compiler" % (prefix) )

        fields = ["compiler_name",
                  "compiler_version"]
        values = []
        for field in fields:
            value = self._find_value(metadata, entry, field)
            if value is None:
                return {"error_msg": "%s Missing field: %s" % (prefix, field)} 
            values.append( value )

        mpi_install_compiler_id = self._select_insert("compiler", "compiler_id", fields, values)

        self._logger.debug("%s --- Processing: mpi_install_compiler = %s" % (prefix, str(mpi_install_compiler_id)) )

        #
        # Process: mpi_get
        #
        self._logger.debug("%s --- Processing: mpi_get" % (prefix) )

        fields = ["mpi_name",
                  "mpi_version"]
        values = []
        for field in fields:
            value = self._find_value(metadata, entry, field)
            if value is None:
                return {"error_msg": "%s Missing field: %s" % (prefix, field)} 
            values.append( value )

        mpi_get_id = self._select_insert("mpi_get",
                                         "mpi_get_id",
                                         fields, values)

        self._logger.debug("%s --- Processing: mpi_get = %s" % (prefix, str(mpi_get_id)) )

        #
        # Process: mpi_install_configure
        #
        self._logger.debug("%s --- Processing: mpi_install_configure" % (prefix) )

        fields = ["vpath_mode",
                  "bitness",
                  "endian",
                  "configure_arguments"]
        values = []
        for field in fields:
            value = self._find_value(metadata, entry, field)
            if value is None:
                if field == "vpath_mode":
                    value = "unknown"
                elif field == "bitness":
                    value = "unknown"
                elif field == "endian":
                    value = "unknown"
                elif field == "configure_arguments":
                    value = "unknown"
                else:
                    return {"error_msg": "%s Missing field: %s" % (prefix, field)} 

            if field == "vpath_mode":
                value = self._convert_vpath_mode(value)
            elif field == "bitness":
                value = self._convert_bitness(value)
            elif field == "endian":
                value = self._convert_endian(value)

            values.append( value )

        mpi_install_configure_id = self._select_insert("mpi_install_configure_args",
                                                       "mpi_install_configure_id",
                                                       fields, values)

        self._logger.debug("%s --- Processing: mpi_install_configure = %s" % (prefix, str(mpi_install_configure_id)) )

        #
        # Process: description
        #
        self._logger.debug("%s --- Processing: description" % (prefix) )

        description_id = 0
        if 'description' not in entry.keys():
            self._logger.debug("%s --- Processing: description -- Skip" % (prefix) )
        else:
            fields = ["description"]
            values = []
            for field in fields:
                value = self._find_value(metadata, entry, field)
                if value is None:
                    return {"error_msg": "%s Missing field: %s" % (prefix, field)} 
                values.append( value )

            description_id = self._select_insert("description",
                                                 "description_id",
                                                 fields, values)

            self._logger.debug("%s --- Processing: description = %s" % (prefix, str(description_id)) )

        #
        # Process: result_message
        #
        self._logger.debug("%s --- Processing: result_message" % (prefix) )

        fields = ["result_message"]
        values = []
        for field in fields:
            value = self._find_value(metadata, entry, field)
            if value is None:
                return {"error_msg": "%s Missing field: %s" % (prefix, field)} 
            values.append( value )

        result_message_id = self._select_insert("result_message",
                                                "result_message_id",
                                                fields, values)

        self._logger.debug("%s --- Processing: result_message = %s" % (prefix, str(result_message_id)) )

        #
        # Process: environment
        #
        self._logger.debug("%s --- Processing: environment" % (prefix) )

        environment_id = 0
        if 'environment' not in entry.keys():
            self._logger.debug("%s --- Processing: environment -- Skip" % (prefix) )
        else:
            fields = ["environment"]
            values = []
            for field in fields:
                value = self._find_value(metadata, entry, field)
                if value is None:
                    return {"error_msg": "%s Missing field: %s" % (prefix, field)} 
                values.append( value )

            environment_id = self._select_insert("environment",
                                                 "environment_id",
                                                 fields, values)

            self._logger.debug("%s --- Processing: environment = %s" % (prefix, str(environment_id)) )

        #
        # Process: mpi_install
        #
        self._logger.debug("%s --- Processing: mpi_install" % (prefix) )

        # "submit_timestamp" = DEFAULT
        fields = ["submit_id",
                  "compute_cluster_id",
                  "mpi_install_compiler_id",
                  "mpi_get_id",
                  "mpi_install_configure_id",
                  "description_id",
                  "environment_id",
                  "result_message_id"]
        non_id_fields = ["start_timestamp",
                         "test_result",
                         "trial",
                         "duration",
                         "exit_value",
                         "exit_signal",
                         "client_serial"]
        optional_fields = ["merge_stdout_stderr",
                           "result_stdout",
                           "result_stderr"]

        values = [submit_id,
                  compute_cluster_id,
                  mpi_install_compiler_id,
                  mpi_get_id,
                  mpi_install_configure_id,
                  description_id,
                  environment_id,
                  result_message_id]

        for field in non_id_fields:
            value = self._find_value(metadata, entry, field)

            if value is None:
                if field == "exit_signal":
                    value = -1
                elif field == "duration":
                    value = "0 seconds"
                else:
                    return {"error_msg": "%s Missing field: %s" % (prefix, field)}
            
            if field == 'trial':
                value = self._convert_boolean(value)
                if self._force_trial is True:
                    self._logger.debug(prefix + "*-*-*-*- Forcing Trial flag *-*-*-*-")
                    value = self._convert_boolean( 1 )

            values.append( value )
        fields.extend( non_id_fields )

        for field in optional_fields:
            value = self._find_value(metadata, entry, field)
            if value is not None:
                if field == "merge_stdout_stderr":
                    values.append( self._convert_boolean( value ) )
                else:
                    values.append( value )
                fields.append( field )

        mpi_install_id = self._select_insert("mpi_install",
                                             "mpi_install_id",
                                             fields, values)

        self._logger.debug("%s --- Processing: mpi_install = %s" % (prefix, str(mpi_install_id)) )

        #
        # Done
        #
        return {'mpi_install_id':mpi_install_id}

    ##########################################################
    def get_fields_for_test_build(self):
        fields = ["compiler_name",
                  "compiler_version",
                  "suite_name",
                  "start_timestamp",
                  "trial",
                  "result_message",
                  "test_result",
                  "exit_value",
                  "client_serial"]

        # mpi_install_id - optional, can be NONE

        optional = ["mpi_install_id",
                    "duration",
                    "exit_signal",
                    "description",
                    "environment",
                    "merge_stdout_stderr",
                    "result_stdout",
                    "result_stderr"]

        return {'required':fields, 'optional':optional}

    def insert_test_build(self, submit_id, metadata, entry):
        prefix = self._name + " (test_build) "
        test_build_id = -1

        # self._logger.debug( "************** Test Build ****************" )
        # self._logger.debug( json.dumps( entry, \
        #                                 sort_keys=True, \
        #                                 indent=4, \
        #                                 separators=(',', ': ') ) )
        # self._logger.debug( "************** Metadata ****************" )
        # self._logger.debug( json.dumps( metadata, \
        #                                 sort_keys=True, \
        #                                 indent=4, \
        #                                 separators=(',', ': ') ) )

        #
        # Find the MPI Install ID
        #
        self._logger.debug("%s --- Processing: mpi_install_id" % (prefix) )
        mpi_install_id = self._find_mpi_install_id(submit_id, metadata, entry)
        mpi_install_info = self._get_mpi_install_info(mpi_install_id)
        if mpi_install_info is None:
            return {"error_msg": "%s Not able to associate this test build with an mpi_install phase" % (prefix)}
        self._logger.debug("%s --- Processing: mpi_install_id = %s" % (prefix, str(mpi_install_id)) )

        #
        # Process: test_build_compiler
        #
        self._logger.debug("%s --- Processing: test_build_compiler" % (prefix) )

        fields = ["compiler_name",
                  "compiler_version"]
        values = []
        for field in fields:
            value = self._find_value(metadata, entry, field)
            if value is None:
                return {"error_msg": "%s Missing field: %s" % (prefix, field)} 
            values.append( value )

        test_build_compiler_id = self._select_insert("compiler", "compiler_id", fields, values)

        self._logger.debug("%s --- Processing: test_build_compiler = %s" % (prefix, str(test_build_compiler_id)) )

        #
        # Process: test_suites
        #
        self._logger.debug("%s --- Processing: test_suite" % (prefix) )

        # test_suite_description = DEFAULT
        fields = ["suite_name"]
        values = []
        for field in fields:
            value = self._find_value(metadata, entry, field)
            if value is None:
                return {"error_msg": "%s Missing field: %s" % (prefix, field)} 
            values.append( value )

        test_suite_id = self._select_insert("test_suites", "test_suite_id", fields, values)

        self._logger.debug("%s --- Processing: test_suite = %s" % (prefix, str(test_suite_id)) )

        #
        # Process: description
        #
        self._logger.debug("%s --- Processing: description" % (prefix) )

        description_id = 0
        if 'description' not in entry.keys():
            self._logger.debug("%s --- Processing: description -- Skip" % (prefix) )
        else:
            fields = ["description"]
            values = []
            for field in fields:
                value = self._find_value(metadata, entry, field)
                if value is None:
                    return {"error_msg": "%s Missing field: %s" % (prefix, field)} 
                values.append( value )

            description_id = self._select_insert("description",
                                                 "description_id",
                                                 fields, values)

            self._logger.debug("%s --- Processing: description = %s" % (prefix, str(description_id)) )

        #
        # Process: result_message
        #
        self._logger.debug("%s --- Processing: result_message" % (prefix) )

        fields = ["result_message"]
        values = []
        for field in fields:
            value = self._find_value(metadata, entry, field)
            if value is None:
                return {"error_msg": "%s Missing field: %s" % (prefix, field)} 
            values.append( value )

        result_message_id = self._select_insert("result_message",
                                                "result_message_id",
                                                fields, values)

        self._logger.debug("%s --- Processing: result_message = %s" % (prefix, str(result_message_id)) )

        #
        # Process: environment
        #
        self._logger.debug("%s --- Processing: environment" % (prefix) )

        environment_id = 0
        if 'environment' not in entry.keys():
            self._logger.debug("%s --- Processing: environment -- Skip" % (prefix) )
        else:
            fields = ["environment"]
            values = []
            for field in fields:
                value = self._find_value(metadata, entry, field)
                if value is None:
                    return {"error_msg": "%s Missing field: %s" % (prefix, field)} 
                values.append( value )

            environment_id = self._select_insert("environment",
                                                 "environment_id",
                                                 fields, values)

            self._logger.debug("%s --- Processing: environment = %s" % (prefix, str(environment_id)) )

        #
        # Process: test_build
        #
        self._logger.debug("%s --- Processing: test_build" % (prefix) )

        # "submit_timestamp" = DEFAULT
        fields = ["submit_id",
                  "mpi_install_id",
                  "compute_cluster_id",
                  "mpi_install_compiler_id",
                  "mpi_get_id",
                  "mpi_install_configure_id",
                  "test_build_compiler_id",
                  "test_suite_id",
                  "description_id",
                  "environment_id",
                  "result_message_id"]
        non_id_fields = ["start_timestamp",
                         "test_result",
                         "trial",
                         "duration",
                         "exit_value",
                         "exit_signal",
                         "client_serial"]
        optional_fields = ["result_stdout",
                           "result_stderr",
                           "merge_stdout_stderr"]

        values = [submit_id,
                  mpi_install_info['mpi_install_id'],
                  mpi_install_info['compute_cluster_id'],
                  mpi_install_info['mpi_install_compiler_id'],
                  mpi_install_info['mpi_get_id'],
                  mpi_install_info['mpi_install_configure_id'],
                  test_build_compiler_id,
                  test_suite_id,
                  description_id,
                  environment_id,
                  result_message_id]

        for field in non_id_fields:
            value = self._find_value(metadata, entry, field)
            
            if value is None:
                if field == "exit_signal":
                    value = -1
                elif field == "duration":
                    value = "0 seconds"
                else:
                    return {"error_msg": "%s Missing field: %s" % (prefix, field)} 

            if field == 'trial':
                value = self._convert_boolean(value)
                if self._force_trial is True:
                    self._logger.debug(prefix + "*-*-*-*- Forcing Trial flag *-*-*-*-")
                    value = self._convert_boolean( 1 )

            values.append( value )
        fields.extend( non_id_fields )

        for field in optional_fields:
            value = self._find_value(metadata, entry, field)
            if value is not None:
                if field == "merge_stdout_stderr":
                    values.append( self._convert_boolean( value ) )
                else:
                    values.append( value )
                fields.append( field )

        test_build_id = self._select_insert("test_build",
                                            "test_build_id",
                                            fields, values)

        self._logger.debug("%s --- Processing: test_build = %s" % (prefix, str(test_build_id)) )

        #
        # Done
        #
        return {'test_build_id':test_build_id}

    ##########################################################
    def get_fields_for_test_run(self):
        fields = ["test_name",
                  "np",
                  "command",
                  "start_timestamp",
                  "trial",
                  "result_message",
                  "test_result",
                  "exit_value",
                  "client_serial"]

        # mpi_install_id - optional, can be NONE
        # test_build_id  - optional, can be NONE

        optional = ["mpi_install_id",
                    "test_build_id",
                    "duration",
                    "launcher",
                    "resource_manager",
                    "parameters",
                    "network",
                    "exit_signal",
                    "latency_bandwidth",
                    "message_size",
                    "latency_min",
                    "latency_avg",
                    "latency_max",
                    "bandwidth_min",
                    "bandwidth_avg",
                    "bandwidth_max",
                    "description",
                    "environment",
                    "merge_stdout_stderr",
                    "result_stdout",
                    "result_stderr",
                    "bios_nodelist",
                    "bios_params",
                    "bios_values",
                    "flashupdt_cfg",
                    "firmware_nodelist",
                    "targets",
                    "image",
                    "controllers",
                    "bootstrap",
                    "harasser_seed",
                    "inject_script",
                    "cleanup_script",
                    "check_script"]

        return {'required':fields, 'optional':optional}

    def insert_test_run(self, submit_id, metadata, entry):
        prefix = self._name + " (test_run) "
        test_run_id = -1

        # self._logger.debug( "************** Test Run   ****************" )
        # self._logger.debug( json.dumps( entry, \
        #                                 sort_keys=True, \
        #                                 indent=4, \
        #                                 separators=(',', ': ') ) )
        # self._logger.debug( "************** Metadata ****************" )
        # self._logger.debug( json.dumps( metadata, \
        #                                 sort_keys=True, \
        #                                 indent=4, \
        #                                 separators=(',', ': ') ) )

        #
        # Get test_build_id and info
        #
        self._logger.debug("%s --- Processing: test_build_id" % (prefix) )
        test_build_id = self._find_test_build_id(submit_id, metadata, entry)
        test_build_info = self._get_test_build_info(test_build_id)
        if test_build_info is None:
            return {"error_msg": "%s Not able to associate this test run with a test build phase" % (prefix)}
        self._logger.debug("%s --- Processing: test_build_id = %s" % (prefix, str(test_build_id)) )

        #
        # Process: latency_bandwidth
        # JJH - need to double check this section
        self._logger.debug("%s --- Processing: latency_bandwidth" % (prefix) )

        performance_id = 0
        if 'latency_bandwidth' not in entry.keys():
            self._logger.debug("%s --- Processing: latency_bandwidth -- Skip" % (prefix) )
        else:
            fields = ["message_size",
                      "latency_min",
                      "latency_avg",
                      "latency_max",
                      "bandwidth_min",
                      "bandwidth_avg",
                      "bandwidth_max"]
            values = []
            for field in fields:
                value = self._find_value(metadata, entry, field)
                if value is None:
                    return {"error_msg": "%s Missing field: %s" % (prefix, field)} 
                values.append( value )

            latency_bandwidth_id = self._select_insert("latency_bandwidth",
                                                       "latency_bandwidth_id",
                                                       fields, values)

            self._logger.debug("%s --- Processing: latency_bandwidth = %s" % (prefix, str(latency_bandwidth_id)) )

            fields = ["latency_bandwidth_id"]
            values = [latency_bandwidth_id]

            performance_id = self._select_insert("performance",
                                                 "performance_id",
                                                 fields, values)

            self._logger.debug("%s --- Processing: latency_bandwidth (performance_id) = %s" % (prefix, str(performance_id)) )


        #
        # Process: test_run_command
        #
        # Examples:
        # launcher         = 'mpirun'
        # resource_manager = 'slurm'
        # parameters       = '-mca foo bar -mca zip zaz'
        # network          = 'loopback,shmem,tcp'
        # Only process these parameters if they are all provided by the client.
        #
        self._logger.debug("%s --- Processing: test_run_command" % (prefix) )

        req_fields = ["launcher",
                      "resource_manager",
                      "parameters",
                      "network"]
        is_good = True
        test_run_network_id = 0
        test_run_command_id = 0

        for field in req_fields:
            if field not in entry.keys():
                self._logger.debug("%s --- Processing: test_run_command -- Skip (missing field %s)" % (prefix, field) )
                is_good = False

        if is_good is True:
            # Process the networks parameter
            test_run_network_id = self._process_networks( self._find_value(metadata, entry, "network") )

            self._logger.debug("%s --- Processing: test_run_command (network_id) = %s" % (prefix, str(test_run_network_id)) )

            # Process the test_run_command
            fields = ["launcher",
                      "resource_mgr",
                      "parameters",
                      "network",
                      "test_run_network_id"]
            values = []
            for field in fields:
                if field == "resource_mgr":
                    value = self._find_value(metadata, entry, "resource_manager")
                elif field == "test_run_network_id":
                    value = test_run_network_id
                else:
                    value = self._find_value(metadata, entry, field)
                if value is None:
                    return {"error_msg": "%s Missing field: %s" % (prefix, field)} 
                values.append( value )

            test_run_command_id = self._select_insert("test_run_command",
                                                      "test_run_command_id",
                                                      fields, values)

            self._logger.debug("%s --- Processing: test_run_command = %s" % (prefix, str(test_run_command_id)) )

        #
        # Process: test_names
        #
        self._logger.debug("%s --- Processing: test_names" % (prefix) )

        # test_name_description = DEFAULT
        fields = ["test_suite_id",
                  "test_name"]
        
        field = fields[1]
        value = self._find_value(metadata, entry, field)
        if value is None:
            return {"error_msg": "%s Missing field: %s" % (prefix, field)} 

        values = [test_build_info['test_suite_id'],
                  value]

        test_name_id = self._select_insert("test_names",
                                           "test_name_id",
                                           fields, values)

        self._logger.debug("%s --- Processing: test_names = %s" % (prefix, str(test_name_id)) )

        #
        # Process: description
        #
        self._logger.debug("%s --- Processing: description" % (prefix) )

        description_id = 0
        if 'description' not in entry.keys():
            self._logger.debug("%s --- Processing: description -- Skip" % (prefix) )
        else:
            skip = False
            fields = ["description"]
            values = []
            for field in fields:
                value = self._find_value(metadata, entry, field)
                if value is None:
                    self._logger.debug("%s --- Processing: description -- missing field (%s) -- Skip" % (prefix, field) )
                    skip = True
                values.append( value )

            if skip is False:
                description_id = self._select_insert("description",
                                                     "description_id",
                                                     fields, values)

                self._logger.debug("%s --- Processing: description = %s" % (prefix, str(description_id)) )

        #
        # Process: result_message
        #
        self._logger.debug("%s --- Processing: result_message" % (prefix) )

        fields = ["result_message"]
        values = []
        for field in fields:
            value = self._find_value(metadata, entry, field)
            if value is None:
                return {"error_msg": "%s Missing field: %s" % (prefix, field)} 
            values.append( value )

        result_message_id = self._select_insert("result_message",
                                                "result_message_id",
                                                fields, values)

        self._logger.debug("%s --- Processing: result_message = %s" % (prefix, str(result_message_id)) )

        #
        # Process: environment
        #
        self._logger.debug("%s --- Processing: environment" % (prefix) )

        environment_id = 0
        if 'environment' not in entry.keys():
            self._logger.debug("%s --- Processing: environment -- Skip" % (prefix) )
        else:
            fields = ["environment"]
            values = []
            for field in fields:
                value = self._find_value(metadata, entry, field)
                if value is None:
                    return {"error_msg": "%s Missing field: %s" % (prefix, field)} 
                values.append( value )

            environment_id = self._select_insert("environment",
                                                 "environment_id",
                                                 fields, values)

            self._logger.debug("%s --- Processing: environment = %s" % (prefix, str(environment_id)) )

        #
        # Process: cluster_checker
        #
        self._logger.debug("%s --- Processing: cluster_checker" % (prefix) )

        clck_id = 0
        if 'cluster_checker' not in entry.keys():
            self._logger.debug("%s --- Processing: cluster_checker -- Skip" % (prefix) )
        else:
            fields = ["clck_results_file"]
            values = []
            for field in fields:
                value = self._find_value(metadata, entry, field)
                if value is None:
                    return {"error_msg": "%s Missing field: %s" % (prefix, field)} 
                values.append( value )

            clck_id = self._select_insert("cluster_checker",
                                          "clck_id",
                                          fields, values)

            self._logger.debug("%s --- Processing: cluster_checker = %s" % (prefix, str(clck_id)) )

        #
        # Process: bios
        #
        self._logger.debug("%s --- Processing: bios" % (prefix) )

        bios_id = 0
        if 'bios_nodelist' not in entry.keys() \
                or 'bios_params' not in entry.keys() \
                or 'bios_values' not in entry.keys():
            self._logger.debug("%s --- Processing: bios -- Skip" % (prefix) )
        else:
            fields = ["bios_nodelist", "bios_params", "bios_values"]
            values = []
            for field in fields:
                value = self._find_value(metadata, entry, field)
                if value is None:
                    return {"error_msg": "%s Missing field: %s" % (prefix, field)} 
                values.append( value )

            bios_id = self._select_insert("bios",
                                          "bios_id",
                                          fields, values)

            self._logger.debug("%s --- Processing: bios = %s" % (prefix, str(bios_id)) )

        #
        # Process: firmware
        #
        self._logger.debug("%s --- Processing: firmware" % (prefix) )

        firmware_id = 0
        if 'flashupdt_cfg' not in entry.keys() or 'firmware_nodelist' not in entry.keys():
            self._logger.debug("%s --- Processing: firmware -- Skip" % (prefix) )
        else:
            fields = ["flashupdt_cfg", "firmware_nodelist"]
            values = []
            for field in fields:
                value = self._find_value(metadata, entry, field)
                if value is None:
                    return {"error_msg": "%s Missing field: %s" % (prefix, field)} 
                values.append( value )

            firmware_id = self._select_insert("firmware",
                                              "firmware_id",
                                              fields, values)

            self._logger.debug("%s --- Processing: firmware = %s" % (prefix, str(firmware_id)) )

        #
        # Process: provision
        #
        self._logger.debug("%s --- Processing: provision" % (prefix) )

        provision_id = 0
        if 'targets' not in entry.keys() \
                or 'image' not in entry.keys() \
                or 'controllers' not in entry.keys() \
                or 'bootstrap' not in entry.keys():
            self._logger.debug("%s --- Processing: provision -- Skip" % (prefix) )
        else:
            fields = ["targets", "image", "controllers", "bootstrap"]
            values = []
            for field in fields:
                value = self._find_value(metadata, entry, field)
                if value is None:
                    return {"error_msg": "%s Missing field: %s" % (prefix, field)} 
                values.append( value )

            provision_id = self._select_insert("provision",
                                               "provision_id",
                                               fields, values)

            self._logger.debug("%s --- Processing: provision = %s" % (prefix, str(provision_id)) )

        #
        # Process: harasser
        #
        self._logger.debug("%s --- Processing: harasser" % (prefix) )

        harasser_id = 0
        if 'harasser_seed' not in entry.keys() \
                or 'inject_script' not in entry.keys() \
                or 'cleanup_script' not in entry.keys() \
                or 'check_script' not in entry.keys():
            self._logger.debug("%s --- Processing: harasser -- Skip" % (prefix) )
        else:
            fields = ["harasser_seed", "inject_script", "cleanup_script", "check_script"]
            values = []
            for field in fields:
                value = self._find_value(metadata, entry, field)
                if value is None:
                    return {"error_msg": "%s Missing field: %s" % (prefix, field)} 
                values.append( value )

            harasser_id = self._select_insert("harasser",
                                              "harasser_id",
                                              fields, values)

            self._logger.debug("%s --- Processing: harasser = %s" % (prefix, str(harasser_id)) )

        # TODO: Add Process: firmware, provision, harasser too

        #
        # Process: test_run
        #
        self._logger.debug("%s --- Processing: test_run" % (prefix) )

        # "submit_timestamp" = DEFAULT
        fields = ["submit_id",
                  "mpi_install_id",
                  "compute_cluster_id",
                  "mpi_install_compiler_id",
                  "mpi_get_id",
                  "mpi_install_configure_id",
                  "test_build_id",
                  "test_build_compiler_id",
                  "test_suite_id",
                  "test_name_id",
                  "performance_id",
                  "test_run_command_id",
                  "description_id",
                  "environment_id",
                  "result_message_id",
                  "clck_id",
                  "bios_id",
                  "firmware_id",
                  "provision_id",
                  "harasser_id"]

        non_id_fields = ["start_timestamp",
                         "np",
                         "full_command",
                         "test_result",
                         "trial",
                         "duration",
                         "exit_value",
                         "exit_signal",
                         "client_serial"]
        optional_fields = ["result_stdout",
                           "result_stderr",
                           "merge_stdout_stderr"]

        values = [submit_id,
                  test_build_info['mpi_install_id'],
                  test_build_info['compute_cluster_id'],
                  test_build_info['mpi_install_compiler_id'],
                  test_build_info['mpi_get_id'],
                  test_build_info['mpi_install_configure_id'],
                  test_build_info['test_build_id'],
                  test_build_info['test_build_compiler_id'],
                  test_build_info['test_suite_id'],
                  test_name_id,
                  performance_id,
                  test_run_command_id,
                  description_id,
                  environment_id,
                  result_message_id,
                  clck_id,
                  bios_id,
                  firmware_id,
                  provision_id,
                  harasser_id]

        for field in non_id_fields:
            # Try acommon alias for this field 'command'
            if field == 'full_command':
                value = self._find_value(metadata, entry, field)
                if value is None:
                    value = self._find_value(metadata, entry, 'command')
            else:
                value = self._find_value(metadata, entry, field)

            if value is None:
                if field == "exit_signal":
                    value = -1
                elif field == "duration":
                    value = "0 seconds"
                else:
                    return {"error_msg": "%s Missing field: %s" % (prefix, field)} 

            if field == 'trial':
                value = self._convert_boolean(value)
                if self._force_trial is True:
                    self._logger.debug(prefix + "*-*-*-*- Forcing Trial flag *-*-*-*-")
                    value = self._convert_boolean( 1 )

            values.append( value )
        fields.extend( non_id_fields )

        for field in optional_fields:
            value = self._find_value(metadata, entry, field)
            if value is not None:
                if field == "merge_stdout_stderr":
                    values.append( self._convert_boolean( value ) )
                else:
                    values.append( value )
                fields.append( field )

        test_run_id = self._select_insert("test_run",
                                          "test_run_id",
                                          fields, values)

        self._logger.debug("%s --- Processing: test_run = %s" % (prefix, str(test_run_id)) )

        #
        # Done
        #
        return {'test_run_id':test_run_id}
