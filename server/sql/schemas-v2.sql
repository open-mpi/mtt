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
    UNIQUE (
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

DROP TABLE submit;
CREATE TABLE submit (
    submit_id serial UNIQUE,
    mtt_version_major smallint NOT NULL DEFAULT '-38',
    mtt_version_minor smallint NOT NULL DEFAULT '-38',
    hostname character varying(128) NOT NULL DEFAULT 'bogus',
    local_username character varying(16) NOT NULL DEFAULT 'bogus',
    http_username character varying(16) NOT NULL DEFAULT 'bogus',
    UNIQUE (
            mtt_version_major,
            mtt_version_minor,
            hostname,
            local_username,
            http_username
    )
);

DROP INDEX submit_serial_idx;
CREATE INDEX submit_serial_idx ON submit(serial_id);
DROP INDEX submit_phase_idx;
CREATE INDEX submit_phase_idx ON submit(phase_id);

DROP TABLE mpi_get;
CREATE TABLE mpi_get (
    mpi_get_id serial UNIQUE,
    mpi_name character varying(64) NOT NULL DEFAULT 'bogus',
    mpi_version character varying(32) NOT NULL DEFAULT 'bogus',
    UNIQUE (
            mpi_name,
            mpi_version
    )
);

DROP TABLE compiler;
CREATE TABLE compiler (
    compiler_id serial UNIQUE,
    compiler_name character varying(64) NOT NULL DEFAULT 'bogus',
    compiler_version character varying(64) NOT NULL DEFAULT 'bogus',
    UNIQUE (
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
    --> 0=no vpath, 1=relative vpath, 2=absolute vpath
    vpath_mode smallint NOT NULL DEFAULT '0',
    --> 1=32bit, 2=64bit
    bitness smallint NOT NULL DEFAULT '1',
    UNIQUE (
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

DROP TABLE test_build;
CREATE TABLE test_build (
    test_build_id serial UNIQUE, --> this changes every night
    mpi_install_id integer NOT NULL DEFAULT '-38', --> refers to mpi_install table

    suite_name character varying(64) NOT NULL DEFAULT 'bogus',  --> *** do not know how to standardize this 
    compiler_id integer NOT NULL DEFAULT '-38', --> refers to compiler table
    UNIQUE (
            mpi_install_id,
            suite_name,
            compiler_id
    )
);

DROP INDEX test_build_mpi_install_idx;
CREATE INDEX test_build_mpi_install_idx ON test_build(mpi_install_id);
DROP INDEX test_build_compiler_idx;
CREATE INDEX test_build_compiler_idx ON test_build(compiler_id);

DROP TABLE test_run;
CREATE TABLE test_run (
    test_run_id serial UNIQUE,
    test_build_id integer NOT NULL DEFAULT '-38',--> refers to test_build table

    variant smallint NOT NULL DEFAULT '-38',
    test_name character varying(64) NOT NULL DEFAULT 'bogus',
    command text NOT NULL DEFAULT 'bogus',
    np smallint NOT NULL DEFAULT '-38',
    UNIQUE (
        test_build_id,
        variant,
        test_name,
        command,
        np
    )
);

DROP INDEX test_build_idx;
CREATE INDEX test_build_idx ON test_run(test_build_id);

DROP TABLE results;
CREATE TABLE results (
    results_id serial UNIQUE,
    submit_id integer NOT NULL DEFAULT '-38',

    -- refer to the index of one of the three phases 
    phase_id integer NOT NULL DEFAULT '-38',
    -- 1=mpi_install, 2=test_build, 3=test_run
    phase smallint NOT NULL DEFAULT '-38',

    environment text NOT NULL DEFAULT '',
    merge_stdout_stderr boolean NOT NULL DEFAULT 't',
    result_stdout text NOT NULL DEFAULT '', --> what is the largest text blob we can put in PG?  Rich says default might be 8k!
    result_stderr text NOT NULL DEFAULT '',
    result_message text NOT NULL DEFAULT '',
    start_timestamp timestamp without time zone NOT NULL DEFAULT now() - interval '24 hours',
    stop_timestamp timestamp without time zone NOT NULL DEFAULT now() - interval '24 hours',
    duration interval NOT NULL DEFAULT '-38 seconds',

    submit_timestamp timestamp without time zone NOT NULL DEFAULT now(),
    client_serial integer NOT NULL DEFAULT '-38', --> refers to the serial sequence

    exit_status integer NOT NULL DEFAULT '-38',
    -- success value: 1=pass, 2=fail, 3=skipped, 4=timed out
    test_result smallint NOT NULL DEFAULT '-38',
    -- set to DEFAULT for correctness tests
    latency_bandwidth_id integer NOT NULL DEFAULT '-38'
);

DROP TABLE latency_bandwidth;
CREATE TABLE latency_bandwidth (
    latency_bandwidth_id serial UNIQUE,
    message_size integer[] DEFAULT '{}',
    bandwidth_min double precision[] DEFAULT '{}',
    bandwidth_max double precision[] DEFAULT '{}',
    bandwidth_avg double precision[] DEFAULT '{}',
    latency_min double precision[] DEFAULT '{}',
    latency_max double precision[] DEFAULT '{}',
    latency_avg double precision[] DEFAULT '{}'
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

    -- refer to the index of one of the three phases 
    phase_id integer NOT NULL DEFAULT '-38',
    -- 1=mpi_install, 2=test_build, 3=test_run
    phase smallint NOT NULL DEFAULT '-38',

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

INSERT INTO latency_bandwidth (latency_bandwidth_id) VALUES (DEFAULT);
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
