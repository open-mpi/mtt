--
-- Open MPI Test Results Tables
--
-- Usage: $ psql -d dbname -U dbusername < this_filename
--

DROP TABLE cluster;
CREATE TABLE cluster (
       cluster_id serial,
       platform_id character varying(256) NOT NULL,
       platform_hardware character varying(256) NOT NULL,
       platform_type character varying(256) NOT NULL,
       os_name character varying(256) NOT NULL,
       os_version character varying(256) NOT NULL,
       UNIQUE (os_name,os_version,platform_hardware,platform_type,platform_id)
);

DROP TABLE users;
CREATE TABLE users (
       users_id serial,
       address character(64) NOT NULL,
       gecos character(32) NOT NULL
);

DROP TABLE cluster_owner;
CREATE TABLE cluster_owner (
       cluster_owner_id serial,
       cluster_id integer, --> refers to cluster table
       users_id integer --> refers to users table
);

DROP INDEX cluster_owner_users_idx;
CREATE INDEX cluster_owner_users_idx ON cluster_owner(users_id);
DROP INDEX cluster_owner_cluster_idx;
CREATE INDEX cluster_owner_cluster_idx ON cluster_owner(cluster_id);

-- Serial number used for individual MTT runs
DROP SEQUENCE client_serial;
CREATE SEQUENCE client_serial;

DROP TABLE submit;
CREATE TABLE submit (
	submit_id serial,
	serial_id integer, --> refers to the serial sequence
	mtt_version_major smallint,
	mtt_version_minor smallint,
	hostname character varying(128) NOT NULL,
	local_username character varying(16) NOT NULL,
	http_username character varying(16) NOT NULL,
	tstamp timestamp without time zone,
	-- phase value: 1=mpi_install, 2=test_build, 3=test_run
	phase smallint,
	-- phase_id will be an index into mpi_install, test_build, or
        -- test_run tables, depending on value of phase
	phase_id integer
);

DROP INDEX submit_serial_idx;
CREATE INDEX submit_serial_idx ON submit(serial_id);
DROP INDEX submit_tstamp_idx;
CREATE INDEX submit_tstamp_idx ON submit(tstamp);
DROP INDEX submit_phase_idx;
CREATE INDEX submit_phase_idx ON submit(phase_id);

DROP TABLE mpi_get;
CREATE TABLE mpi_get (
	mpi_get_id serial,
	name character varying(64) NOT NULL,
	version character varying(32) NOT NULL
);

DROP TABLE compiler;
CREATE TABLE compiler (
	compiler_id serial,
	compiler_name character varying(64) NOT NULL,
	compiler_version character varying(64) NOT NULL
);

DROP TABLE mpi_install;
CREATE TABLE mpi_install (
	mpi_install_id serial,

	cluster_id integer, --> refers to cluster table
	mpi_get_id integer, --> refers to mpi_get table
	compiler_id integer, --> refers to compiler table
	configure_arguments character varying(512), --> put this into separate table because substring searchs will be much faster, but rich says that this is a fairly uncommon way to search for our results, so the PITA for putting this in another table might not be worth it
	vpath_mode smallint,

	results_id integer --> refers to results table, this changes every night
);

DROP INDEX mpi_install_cluster_idx;
CREATE INDEX mpi_install_cluster_idx ON mpi_install(cluster_id);
DROP INDEX mpi_install_mpi_get_idx;
CREATE INDEX mpi_install_mpi_get_idx ON mpi_install(mpi_get_id);
DROP INDEX mpi_install_compiler_idx;
CREATE INDEX mpi_install_compiler_idx ON mpi_install(compiler_id);
DROP INDEX mpi_install_results_idx;
CREATE INDEX mpi_install_results_idx ON mpi_install(results_id);

DROP TABLE test_build;
CREATE TABLE test_build (
	test_build_id serial, --> this changes every night
	mpi_install_id integer, --> refers to mpi_install table

	suite_name character varying(64) NOT NULL,  --> *** do not know how to standardize this
	compiler_id integer, --> refers to compiler table

	results_id integer --> refers to results table, this changes every night
);

DROP INDEX test_build_mpi_install_idx;
CREATE INDEX test_build_mpi_install_idx ON test_build(mpi_install_id);
DROP INDEX test_build_compiler_idx;
CREATE INDEX test_build_compiler_idx ON test_build(compiler_id);
DROP INDEX test_build_results_idx;
CREATE INDEX test_build_results_idx ON test_build(results_id);

DROP TABLE test_run;
CREATE TABLE test_run (
	test_run_id serial,
	test_build_id integer,--> refers to test_build table

	variant smallint,
	name character varying(64) NOT NULL,
	command text NOT NULL,
	np smallint,

	results_id integer, --> refers to results table
    failure_id integer DEFAULT NULL, --> points to information about failure
                                     --> null if it's yet to be "churned"
);

DROP INDEX test_build_idx;
CREATE INDEX test_build_idx ON test_run(test_build_id);
DROP INDEX results_idx;
CREATE INDEX results_idx ON test_run(results_id);

DROP TABLE results;
CREATE TABLE results (
	results_id serial,

	environment text,
	merge_stdout_stderr boolean,
	result_stdout text, --> what is the largest text blob we can put in PG?  Rich says default might be 8k!
	result_stderr text,
	start_timestamp timestamp without time zone,
	stop_timestamp timestamp without time zone,
	-- do we want exit status?
	exit_status smallint,
	-- result value: 1=pass, 2=fail, 3=skipped, 4=timed out
	result smallint
);

DROP INDEX results_result_idx;
CREATE INDEX results_result_idx ON results(result);

-- For "new" failure reporting

DROP TABLE failure;
CREATE TABLE failure (
    failure_id integer,
    timestamp timestamp without time zone,  --> first time the failure occurred
    field character varying(16) NOT NULL,   --> maps to any non *_id field name in mtt database
    value character varying(16) NOT NULL    --> value of field
);

