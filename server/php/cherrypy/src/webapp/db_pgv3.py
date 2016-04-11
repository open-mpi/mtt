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
        #self._logger.debug(insert_stmt)
        #self._logger.debug( ", ".join(str(x) for x in values) )
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
                  "configure_arguments",
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
                    "result_stderr"]

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
                  "result_message_id"]

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
                  result_message_id]

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
