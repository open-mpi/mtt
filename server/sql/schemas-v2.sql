--
-- Open MPI Test Results Tables
--
-- Usage: $ psql -d dbname -U dbusername < this_filename
--

DROP TABLE compute_cluster CASCADE;
CREATE TABLE compute_cluster (
    compute_cluster_id serial PRIMARY KEY,
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

DROP TABLE submit CASCADE;
CREATE TABLE submit (
    submit_id serial PRIMARY KEY,
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

DROP TABLE mpi_get CASCADE;
CREATE TABLE mpi_get (
    mpi_get_id serial PRIMARY KEY,
    mpi_name character varying(64) NOT NULL DEFAULT 'bogus',
    mpi_version character varying(32) NOT NULL DEFAULT 'bogus',
    UNIQUE (
            mpi_name,
            mpi_version
    )
);

DROP TABLE compiler CASCADE;
CREATE TABLE compiler (
    compiler_id serial PRIMARY KEY,
    compiler_name character varying(64) NOT NULL DEFAULT 'bogus',
    compiler_version character varying(64) NOT NULL DEFAULT 'bogus',
    UNIQUE (
            compiler_name,
            compiler_version
    )
);

DROP TABLE mpi_install CASCADE;
CREATE TABLE mpi_install (
    mpi_install_id serial PRIMARY KEY,

    compute_cluster_id integer NOT NULL DEFAULT '-38' REFERENCES compute_cluster,
    mpi_get_id integer NOT NULL DEFAULT '-38' REFERENCES mpi_get,
    compiler_id integer NOT NULL DEFAULT '-38' REFERENCES compiler,

    --> put this into separate table because substring searchs will be much faster,
    --> but rich says that this is a fairly uncommon way to search for our results, so
    --> the PITA for putting this in another table might not be worth it
    configure_arguments text NOT NULL DEFAULT '', 
    --> bitmapped field (LSB to MSB) 'none', 'relative', and 'absolute'
    vpath_mode smallint NOT NULL DEFAULT '0',
    --> bitmapped field (LSB to MSB) 8, 16, 32, 64, and 128
    bitness smallint NOT NULL DEFAULT '0',
    --> bitmapped field (LSB to MSB) 'little' and 'big'
    endian smallint NOT NULL DEFAULT '0',
    UNIQUE (
            compute_cluster_id,
            mpi_get_id,
            compiler_id,
            configure_arguments,
            vpath_mode,
            bitness,
            endian
    )
);

DROP TABLE test_build CASCADE;
CREATE TABLE test_build (
    test_build_id serial PRIMARY KEY,
    mpi_install_id integer NOT NULL DEFAULT '-38' REFERENCES mpi_install,

    --> *** do not know how to standardize this 
    suite_name character varying(64) NOT NULL DEFAULT 'bogus',
    compiler_id integer NOT NULL DEFAULT '-38' REFERENCES compiler,
    UNIQUE (
            mpi_install_id,
            suite_name,
            compiler_id
    )
);

DROP TABLE test_run CASCADE;
CREATE TABLE test_run (
    test_run_id serial PRIMARY KEY,
    test_build_id integer NOT NULL DEFAULT '-38' REFERENCES test_build,

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

DROP TABLE results CASCADE;
CREATE TABLE results (
    results_id serial PRIMARY KEY,
    submit_id integer NOT NULL DEFAULT '-38' REFERENCES submit,

    -- refer to the index of one of the three phases 
    phase_id integer NOT NULL DEFAULT '-38',
    -- 1=mpi_install, 2=test_build, 3=test_run
    phase smallint NOT NULL DEFAULT '-38',

    environment text NOT NULL DEFAULT '',
    merge_stdout_stderr boolean NOT NULL DEFAULT 't',

    --> what is the largest text blob we can put in PG?  Rich says default might be 8k!
    result_stdout text NOT NULL DEFAULT '', 
    result_stderr text NOT NULL DEFAULT '',
    result_message text NOT NULL DEFAULT '',
    start_timestamp timestamp without time zone NOT NULL DEFAULT now() - interval '24 hours',
    duration interval NOT NULL DEFAULT '-38 seconds',

    submit_timestamp timestamp without time zone NOT NULL DEFAULT now(),

    -- keep track of individual MTT runs
    client_serial integer NOT NULL DEFAULT '-38',

    -- flag data submitted by experimental MTT runs
    trial boolean NOT NULL DEFAULT 'f',

    -- set if process exited
    exit_value integer NOT NULL DEFAULT '-38',
    -- set if process was signaled
    exit_signal integer NOT NULL DEFAULT '-38',
    -- result value: 0=fail, 1=pass, 2=skipped, 3=timed out
    test_result smallint NOT NULL DEFAULT '-38',
    -- set to DEFAULT for correctness tests
    latency_bandwidth_id integer NOT NULL DEFAULT '-38'
);

DROP TABLE latency_bandwidth CASCADE;
CREATE TABLE latency_bandwidth (
    latency_bandwidth_id serial PRIMARY KEY,
    message_size integer[] DEFAULT '{}',
    bandwidth_min double precision[] DEFAULT '{}',
    bandwidth_max double precision[] DEFAULT '{}',
    bandwidth_avg double precision[] DEFAULT '{}',
    latency_min double precision[] DEFAULT '{}',
    latency_max double precision[] DEFAULT '{}',
    latency_avg double precision[] DEFAULT '{}'
);

DROP TABLE alerts CASCADE;
CREATE TABLE alerts (
    alerts_id serial PRIMARY KEY,
    users_id integer NOT NULL DEFAULT '-38' REFERENCES users,
    enabled smallint,
    url text NOT NULL DEFAULT 'bogus',
    subject character(64) NOT NULL DEFAULT 'bogus',
    description character(64) NOT NULL DEFAULT 'bogus'
);

DROP TABLE users CASCADE;
CREATE TABLE users (
    users_id serial PRIMARY KEY,
    username character(16) NOT NULL DEFAULT 'bogus',
    email_address character(64) NOT NULL DEFAULT 'bogus',
    gecos character(32) NOT NULL DEFAULT 'bogus'
);

-- For "new" failure reporting
DROP TABLE failure CASCADE;
CREATE TABLE failure (
    failure_id serial NOT NULL DEFAULT '-38',

    -- refer to the index of one of the three phases 
    phase_id integer NOT NULL DEFAULT '-38' REFERENCES phase,
    -- 1=mpi_install, 2=test_build, 3=test_run
    phase smallint NOT NULL DEFAULT '-38',

    first_occurrence timestamp without time zone, --> first occurrence
    last_occurrence timestamp without time zone,  --> most recent occurrence
    field character varying(16) NOT NULL DEFAULT 'bogus', --> maps to any non *_id field name in mtt database
    value character varying(16) NOT NULL DEFAULT 'bogus'  --> value of field
);

DROP TABLE cluster_owner CASCADE;
CREATE TABLE cluster_owner (
    cluster_owner_id serial PRIMARY KEY,
    compute_cluster_id integer NOT NULL DEFAULT '-38' REFERENCES compute_cluster,
    users_id integer NOT NULL DEFAULT '-38'
);
