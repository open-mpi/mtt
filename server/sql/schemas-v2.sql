--
-- Open MPI Test Results Tables
--
-- Usage: $ psql -d dbname -U dbusername < this_filename
--

DROP TABLE compute_cluster;
CREATE TABLE compute_cluster (
    compute_cluster_id serial UNIQUE,
    platform_name character varying(256) NOT NULL DEFAULT 'bogus',
    platform_hardware character varying(256) NOT NULL DEFAULT 'bogus',
    platform_type character varying(256) NOT NULL DEFAULT 'bogus',
    os_name character varying(256) NOT NULL DEFAULT 'bogus',
    os_version character varying(256) NOT NULL DEFAULT 'bogus',
    UNIQUE (compute_cluster_id,
            os_name,
            os_version,
            platform_hardware,
            platform_type,
            platform_name
    )
);

-- Serial number used for individual MTT runs
DROP SEQUENCE client_serial;
CREATE SEQUENCE client_serial;

-- We may consider splitting this table into submit_data (who/from-where submitted)
-- and submit_log (when was submitted)
DROP TABLE submit;
CREATE TABLE submit (
    submit_id serial UNIQUE,
    client_serial integer NOT NULL DEFAULT '-38', --> refers to the serial sequence
    mtt_version_major smallint NOT NULL DEFAULT '-38',
    mtt_version_minor smallint NOT NULL DEFAULT '-38',
    hostname character varying(128) NOT NULL DEFAULT 'bogus',
    local_username character varying(16) NOT NULL DEFAULT 'bogus',
    http_username character varying(16) NOT NULL DEFAULT 'bogus',
    tstamp timestamp without time zone NOT NULL DEFAULT now(),
    UNIQUE (submit_id,
            client_serial,
            mtt_version_major,
            mtt_version_minor,
            hostname,
            local_username,
            http_username,
            tstamp
    )
);


DROP INDEX submit_serial_idx;
CREATE INDEX submit_serial_idx ON submit(serial_id);
DROP INDEX submit_tstamp_idx;
CREATE INDEX submit_tstamp_idx ON submit(tstamp);
DROP INDEX submit_phase_idx;
CREATE INDEX submit_phase_idx ON submit(phase_id);

DROP TABLE mpi_get;
CREATE TABLE mpi_get (
    mpi_get_id serial UNIQUE,
    section_name character varying(64) NOT NULL DEFAULT 'bogus',
    version character varying(32) NOT NULL DEFAULT 'bogus',
    UNIQUE (mpi_get_id,
            section_name,
            version
    )
);

DROP TABLE compiler;
CREATE TABLE compiler (
    compiler_id serial UNIQUE,
    compiler_name character varying(64) NOT NULL DEFAULT 'bogus',
    compiler_version character varying(64) NOT NULL DEFAULT 'bogus',
    UNIQUE (compiler_id,
            compiler_name,
            compiler_version
    )
);

DROP TABLE mpi_install;
CREATE TABLE mpi_install (
    mpi_install_id serial UNIQUE,

    compute_cluster_id integer NOT NULL DEFAULT '-38', --> refers to compute_cluster table
    mpi_get_id integer NOT NULL DEFAULT '-38', --> refers to mpi_get table
    compiler_id integer NOT NULL DEFAULT '-38', --> refers to compiler table

    --> put this into separate table because substring searchs will be much faster,
    --> but rich says that this is a fairly uncommon way to search for our results, so
    --> the PITA for putting this in another table might not be worth it
    configure_arguments character varying(512) NOT NULL DEFAULT '', 
    vpath_mode character varying(16) NOT NULL DEFAULT 'bogus',
    --> 1=32bit, 2=64bit
    bitness smallint NOT NULL DEFAULT '1',

    results_id integer NOT NULL DEFAULT '-38', --> refers to results table, this changes every night
    UNIQUE (mpi_install_id,
            compute_cluster_id,
            mpi_get_id,
            compiler_id,
            configure_arguments,
            vpath_mode
    )
);

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
    mpi_install_id integer NOT NULL DEFAULT '-38', --> refers to mpi_install table

    suite_name character varying(64) NOT NULL DEFAULT 'bogus',  --> *** do not know how to standardize this 
    compiler_id integer NOT NULL DEFAULT '-38', --> refers to compiler table

    results_id integer NOT NULL DEFAULT '-38', --> refers to results table, this changes every night
    UNIQUE (test_build_id,
            mpi_install_id,
            suite_name,
            compiler_id,
            results_id
    )
);

DROP INDEX test_build_mpi_install_idx;
CREATE INDEX test_build_mpi_install_idx ON test_build(mpi_install_id);
DROP INDEX test_build_compiler_idx;
CREATE INDEX test_build_compiler_idx ON test_build(compiler_id);
DROP INDEX test_build_results_idx;
CREATE INDEX test_build_results_idx ON test_build(results_id);

DROP TABLE test_run;
CREATE TABLE test_run (
    test_run_id serial UNIQUE,
    test_build_id integer NOT NULL DEFAULT '-38',--> refers to test_build table

    variant smallint NOT NULL DEFAULT '-38',
    test_name character varying(64) NOT NULL DEFAULT 'bogus',
    command text NOT NULL DEFAULT 'bogus',
    np smallint NOT NULL DEFAULT '-38',

    results_id integer NOT NULL DEFAULT '-38', --> refers to results table
    failure_id integer NOT NULL DEFAULT '-38'  --> points to information about failure
);

DROP INDEX test_build_idx;
CREATE INDEX test_build_idx ON test_run(test_build_id);
DROP INDEX results_idx;
CREATE INDEX results_idx ON test_run(results_id);

DROP TABLE results;
CREATE TABLE results (
    results_id serial UNIQUE,
    submit_id integer NOT NULL DEFAULT '-38',

    environment text NOT NULL DEFAULT '',
    merge_stdout_stderr boolean NOT NULL DEFAULT 't',
    result_stdout text NOT NULL DEFAULT '', --> what is the largest text blob we can put in PG?  Rich says default might be 8k!
    result_stderr text NOT NULL DEFAULT '',
    start_timestamp timestamp without time zone NOT NULL DEFAULT now() - interval '24 hours',
    stop_timestamp timestamp without time zone NOT NULL DEFAULT now() - interval '24 hours',
    exit_status smallint NOT NULL DEFAULT '-38',
    -- success value: 1=pass, 2=fail, 3=skipped, 4=timed out
    test_result smallint NOT NULL DEFAULT '-38',
    -- set to DEFAULT for correctness tests
    performance_id integer NOT NULL DEFAULT '-38'
);

DROP TABLE performance;
CREATE TABLE performance (
    performance_id serial UNIQUE,
    x_axis_label character varying(64) NOT NULL DEFAULT 'bogus',
    y_axis_label character varying(64) NOT NULL DEFAULT 'bogus',
    messages_size integer[],
    bandwidth integer[],
    latency_min double precision[],
    latency_max double precision[],
    latency_avg double precision[]
);

DROP INDEX results_success_idx;
CREATE INDEX results_success_idx ON results(success);


DROP TABLE alerts;
CREATE TABLE alerts (
    alerts_id serial UNIQUE,
    users_id integer NOT NULL DEFAULT '-38',
    enabled smallint,
    url text NOT NULL DEFAULT 'bogus',
    subject character(64) NOT NULL DEFAULT 'bogus',
    description character(64) NOT NULL DEFAULT 'bogus'
);


DROP TABLE users;
CREATE TABLE users (
    users_id serial UNIQUE,
    username character(16) NOT NULL DEFAULT 'bogus',
    email_address character(64) NOT NULL DEFAULT 'bogus',
    gecos character(32) NOT NULL DEFAULT 'bogus'
);

-- For "new" failure reporting

DROP TABLE failure;
CREATE TABLE failure (
    failure_id integer NOT NULL DEFAULT '-38',
    first_occurrence timestamp without time zone,    --> first occurrence
    last_occurrence timestamp without time zone,     --> most recent occurrence
    field character varying(16) NOT NULL DEFAULT 'bogus', --> maps to any non *_id field name in mtt database
    value character varying(16) NOT NULL DEFAULT 'bogus'  --> value of field
);

DROP TABLE cluster_owner;
CREATE TABLE cluster_owner (
    cluster_owner_id serial UNIQUE,
    compute_cluster_id integer NOT NULL DEFAULT '-38', --> refers to compute_cluster table
    users_id integer NOT NULL DEFAULT '-38' --> refers to users table
);

DROP INDEX cluster_owner_users_idx;
CREATE INDEX cluster_owner_users_idx ON cluster_owner(users_id);
DROP INDEX cluster_owner_cluster_idx;
CREATE INDEX cluster_owner_cluster_idx ON cluster_owner(compute_cluster_id);

INSERT INTO performance (performance_id) VALUES (DEFAULT);
INSERT INTO failure (failure_id) VALUES (DEFAULT); 

-- Soon we will be strict, and disallow empty rows of this sort 
-- DEFAULT is a random bogus value for such an empty row
INSERT INTO compute_cluster (compute_cluster_id) VALUES (DEFAULT);
INSERT INTO submit (submit_id) VALUES (DEFAULT); 
INSERT INTO mpi_get (mpi_get_id) VALUES (DEFAULT); 
INSERT INTO compiler (compiler_id) VALUES (DEFAULT); 
INSERT INTO mpi_install (mpi_install_id) VALUES (DEFAULT); 
INSERT INTO test_build (test_build_id) VALUES (DEFAULT); 
INSERT INTO test_run (test_run_id) VALUES (DEFAULT); 
INSERT INTO results (results_id) VALUES (DEFAULT); 
INSERT INTO users (users_id) VALUES (DEFAULT); 
INSERT INTO cluster_owner (cluster_owner_id) VALUES (DEFAULT); 
