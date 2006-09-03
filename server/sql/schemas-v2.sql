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
       os_name character varying(256) NOT NUL,
       os_version character varying(256) NOT NULL,
       UNIQUE (os_name,os_version,platform_hardware,platform_type,platform_id)
);

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
	tstamp timestamp without timezone,
	-- phase value: 1=mpi_install, 2=test_build, 3=test_run
	phase smallint,
	-- phase_id will be an index into mpi_install, test_build, or
        -- test_run tables, depending on value of phase
	phase_id integer
);

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

DROP TABLE test_build;
CREATE TABLE test_build (
	test_build_id serial, --> this changes every night
	mpi_install_id integer, --> refers to mpi_install table

	suite_name character varying(64) NOT NULL,  --> *** do not know how to standardize this
	compiler_id integer, --> refers to compiler table

	results_id integer, --> refers to results table, this changes every night
);

DROP TABLE test_run;
CREATE TABLE test_run (
	test_run_id serial,
	test_build_id --> refers to test_build table

	variant smallint,
	name character varying(64) NOT NULL,
	command text NOT NULL,
	np smallint,

	results_id integer, --> refers to results table
);

DROP TABLE results;
CREATE TABLE results (
	results_id serial,

	environment text,
	merge_stdout_stderr boolean,
	stdout text, --> what's the largest text blob we can put in PG?  Rich says default might be 8k!
	stderr text,
	start_timestamp timestamp without timezone,
	stop_timestamp timestamp without timezone,
	-- result value: 1=pass, 2=fail, 3=skipped, 4=timed out
	result smallint,
	-- do we want exit status?
	exit_status smallint
};
