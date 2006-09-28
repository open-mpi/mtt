--
-- Open MPI Test Results Tables
--
-- Usage: $ psql -d dbname -U dbusername < this_filename
--

DROP TABLE compute_cluster;
CREATE TABLE compute_cluster (
    compute_cluster_id serial UNIQUE,
    -- JMS: Changed these to not have any default values -- we want to
    -- the error checking to ensure that proper values are insertted
    -- for all of these.
    platform_id character varying(256) NOT NULL,
    platform_hardware character varying(256) NOT NULL,
    platform_type character varying(256) NOT NULL,
    os_name character varying(256) NOT NULL,
    os_version character varying(256) NOT NULL,
    UNIQUE (compute_cluster_id,
            os_name,
            os_version,
            platform_hardware,
            platform_type,
            platform_id
    )
);

-- JMS What are all these INSERTs for?
INSERT INTO compute_cluster (compute_cluster_id) VALUES ('-1');

-- Serial number used for individual MTT runs
DROP SEQUENCE client_serial;
CREATE SEQUENCE client_serial;

DROP TABLE submit;
CREATE TABLE submit (
    submit_id serial UNIQUE,

    -- JMS: similar to above, no default values here
    client_serial integer NOT NULL,
    mtt_version_major smallint NOT NULL,
    mtt_version_minor smallint NOT NULL,
    hostname character varying(128) NOT NULL,
    local_username character varying(16) NOT NULL,
    http_username character varying(16) NOT NULL,
    tstamp timestamp without time zone NOT NULL DEFAULT now(),
    UNIQUE (submit_id,
            client_serial,
            mtt_version_major,
            mtt_version_minor,
            hostname,
            local_username,
            http_username
    )
);

INSERT INTO submit (submit_id) VALUES ('-1'); 

DROP INDEX submit_serial_idx;
CREATE INDEX submit_serial_idx ON submit(serial_id);
DROP INDEX submit_tstamp_idx;
CREATE INDEX submit_tstamp_idx ON submit(tstamp);
DROP INDEX submit_phase_idx;
CREATE INDEX submit_phase_idx ON submit(phase_id);

DROP TABLE mpi_get;
CREATE TABLE mpi_get (
    mpi_get_id serial UNIQUE,
    -- JMS: similar to above, no default values here
    section_name character varying(64) NOT NULL,
    version character varying(32) NOT NULL,
    UNIQUE (mpi_get_id,
            section_name,
            version
    )
);

INSERT INTO mpi_get (mpi_get_id) VALUES ('-1'); 

DROP TABLE compiler;
CREATE TABLE compiler (
    compiler_id serial UNIQUE,
    -- JMS: similar to above, no default values here
    compiler_name character varying(64) NOT NULL,
    compiler_version character varying(64) NOT NULL,
    UNIQUE (compiler_id,
            compiler_name,
            compiler_version
    )
);

INSERT INTO compiler (compiler_id) VALUES ('-1'); 

DROP TABLE mpi_install;
CREATE TABLE mpi_install (
    mpi_install_id serial UNIQUE,

    -- JMS: similar to above, no default values here
    compute_cluster_id integer NOT NULL, --> refers to compute_cluster table
    mpi_get_id integer NOT NULL, --> refers to mpi_get table
    compiler_id integer NOT NULL, --> refers to compiler table
    configure_arguments character varying(512) NOT NULL DEFAULT '', --> put this into separate table because substring searchs will be much faster, but rich says that this is a fairly uncommon way to search for our results, so the PITA for putting this in another table might not be worth it
    vpath_mode character varying(16) NOT NULL,

    results_id integer NOT NULL, --> refers to results table, this changes every night
    UNIQUE (mpi_install_id,
            compute_cluster_id,
            mpi_get_id,
            compiler_id,
            configure_arguments,
            vpath_mode
    )
);

INSERT INTO mpi_install (mpi_install_id) VALUES ('-1'); 

DROP INDEX mpi_install_compute_cluster_idx;
CREATE INDEX mpi_install_compute_cluster_idx ON mpi_install(compute_compute_cluster_id);
DROP INDEX mpi_install_mpi_get_idx;
CREATE INDEX mpi_install_mpi_get_idx ON mpi_install(mpi_get_id);
DROP INDEX mpi_install_compiler_idx;
CREATE INDEX mpi_install_compiler_idx ON mpi_install(compiler_id);
DROP INDEX mpi_install_results_idx;
CREATE INDEX mpi_install_results_idx ON mpi_install(results_id);

DROP TABLE test_build;
CREATE TABLE test_build (
    test_build_id serial UNIQUE, --> this changes every night
    -- JMS: similar to above, no default values here
    mpi_install_id integer NOT NULL, --> refers to mpi_install table

    suite_name character varying(64) NOT NULL,  --> *** do not know how to standardize this 
    compiler_id integer NOT NULL, --> refers to compiler table

    results_id integer NOT NULL, --> refers to results table, this changes every night
    UNIQUE (test_build_id,
            mpi_install_id,
            suite_name,
            compiler_id,
            results_id
    )
);

INSERT INTO test_build (test_build_id) VALUES ('-1'); 

DROP INDEX test_build_mpi_install_idx;
CREATE INDEX test_build_mpi_install_idx ON test_build(mpi_install_id);
DROP INDEX test_build_compiler_idx;
CREATE INDEX test_build_compiler_idx ON test_build(compiler_id);
DROP INDEX test_build_results_idx;
CREATE INDEX test_build_results_idx ON test_build(results_id);

DROP TABLE test_run;
CREATE TABLE test_run (
    test_run_id serial UNIQUE,
    -- JMS: similar to above, no default values here
    test_build_id integer NOT NULL,--> refers to test_build table

    variant smallint NOT NULL,
    test_name character varying(64) NOT NULL,
    command text NOT NULL,
    np smallint NOT NULL,

    results_id integer NOT NULL, --> refers to results table
    -- JMS: we need to talk about this one
    failure_id integer NOT NULL  --> points to information about failure
);

INSERT INTO test_run (test_run_id) VALUES ('-1'); 

DROP INDEX test_build_idx;
CREATE INDEX test_build_idx ON test_run(test_build_id);
DROP INDEX results_idx;
CREATE INDEX results_idx ON test_run(results_id);

DROP TABLE results;
CREATE TABLE results (
    results_id serial UNIQUE,
    submit_id integer NOT NULL DEFAULT -1,

    environment text NOT NULL DEFAULT '',
    merge_stdout_stderr boolean,
    result_stdout text NOT NULL DEFAULT '', --> what is the largest text blob we can put in PG?  Rich says default might be 8k!
    result_stderr text NOT NULL DEFAULT '',
    start_timestamp timestamp without time zone,
    stop_timestamp timestamp without time zone,
    -- JMS: similar to above, no default values here
    exit_status smallint NOT NULL,
    -- Key: result value: 1=pass, 2=fail, 3=skipped, 4=timed out
    test_result smallint NOT NULL,
    -- set to DEFAULT for correctness tests (i.e., no performance results)
    performance_id integer NOT NULL DEFAULT -1
);

INSERT INTO results (results_id) VALUES ('-1'); 

DROP TABLE performance;
CREATE TABLE performance (
    performance_id serial UNIQUE,
    x_axis_label character varying(64) NOT NULL DEFAULT '',
    y_axis_label character varying(64) NOT NULL DEFAULT '',
    performance_data double precision[][] NOT NULL DEFAULT '{{"0.0"}}',
    description text NOT NULL DEFAULT ''
);

INSERT INTO performance (performance_id) VALUES ('-1');

DROP INDEX results_success_idx;
CREATE INDEX results_success_idx ON results(success);

-- For "new" failure reporting

DROP TABLE failure;
CREATE TABLE failure (
    failure_id integer NOT NULL DEFAULT -1,
    timestamp timestamp without time zone,  --> first time the failure occurred
    field character varying(16) NOT NULL DEFAULT '',   --> maps to any non *_id field name in mtt database
    value character varying(16) NOT NULL DEFAULT ''   --> value of field 
);

INSERT INTO failure (failure_id) VALUES ('-1'); 

DROP TABLE users;
CREATE TABLE users (
    users_id serial UNIQUE,
    address character(64) NOT NULL DEFAULT '',
    gecos character(32) NOT NULL DEFAULT ''
);

INSERT INTO users (users_id) VALUES ('-1'); 

DROP TABLE cluster_owner;
CREATE TABLE cluster_owner (
    cluster_owner_id serial UNIQUE,
    compute_cluster_id integer NOT NULL DEFAULT -1, --> refers to compute_cluster table
    users_id integer NOT NULL DEFAULT -1 --> refers to users table
);

INSERT INTO cluster_owner (cluster_owner_id) VALUES ('-1'); 

DROP INDEX cluster_owner_users_idx;
CREATE INDEX cluster_owner_users_idx ON cluster_owner(users_id);
DROP INDEX cluster_owner_cluster_idx;
CREATE INDEX cluster_owner_cluster_idx ON cluster_owner(compute_cluster_id);
