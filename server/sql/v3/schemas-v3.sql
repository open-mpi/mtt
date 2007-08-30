--
-- Open MPI Test Results Tables
--
-- Usage: $ psql -d dbname -U dbusername < this_filename
--

-- Roles:
--   GRANT mtt to iu;

--
-- PARTITION/FK PROBLEM: 
--  A foreign key reference is only valid for the specific table in which 
--  the data is contained. Currently (as of 8.2) this does not work for
--  partition tables. The following error is likely to appear if a 
--  table contains a foreign reference to a partition table:
--     ERROR:  insert or update on table "test_build_y2006_m11_wk4" violates foreign key constraint "test_build_y2006_m11_wk4_mpi_install_id_fkey"
--     DETAIL:  Key (mpi_install_id)=(1) is not present in table "mpi_install".
--  Even though ID '1' is in mpi_install, but in one of the child 
--  partitions.
--  The work around is not to have foreign key conditions between the tables
--  which could slow down operations if we ever have to join any of the 
--  3 partition tables, which is unlikey.
--

--
-- Serial number used for individual MTT runs
--
DROP SEQUENCE client_serial;
CREATE SEQUENCE client_serial;

--
-- Cluster Table
--
DROP TABLE compute_cluster CASCADE;
CREATE TABLE compute_cluster (
    compute_cluster_id  serial,

    -- Current Max: 42 chars
    platform_name       varchar(128) NOT NULL DEFAULT 'bogus',
    -- Current Max: 6 chars
    platform_hardware   varchar(128) NOT NULL DEFAULT 'bogus',
    -- Current Max: 54 chars
    platform_type       varchar(128) NOT NULL DEFAULT 'bogus',
    -- Current Max: 5 chars
    os_name             varchar(128) NOT NULL DEFAULT 'bogus',
    -- Current Max: 43 chars
    os_version          varchar(128) NOT NULL DEFAULT 'bogus',

    UNIQUE (
            os_name,
            os_version,
            platform_hardware,
            platform_type,
            platform_name
    ),

    PRIMARY KEY (compute_cluster_id)
);

--
-- Submit Table
--
DROP TABLE submit CASCADE;
CREATE TABLE submit (
    submit_id           serial,

    -- Current Max: 95 chars
    hostname            varchar(128) NOT NULL DEFAULT 'bogus',
    -- Current Max: 8 chars
    local_username      varchar(16)  NOT NULL DEFAULT 'bogus',
    -- Current Max: 8 chars
    http_username       varchar(16)  NOT NULL DEFAULT 'bogus',
    -- Current Max: 8 chars
    mtt_client_version  varchar(16)          NOT NULL DEFAULT '',

    PRIMARY KEY (submit_id)
);

--
-- Compiler Table
--
DROP TABLE compiler CASCADE;
CREATE TABLE compiler (
    compiler_id      serial,

    -- Current Max: 9 chars
    compiler_name    varchar(64) NOT NULL DEFAULT 'bogus',
    -- Current Max: 35 chars
    compiler_version varchar(64) NOT NULL DEFAULT 'bogus',

    UNIQUE (
            compiler_name,
            compiler_version
    ),

    PRIMARY KEY (compiler_id)
);


--
-- MPI Get Table
--
DROP TABLE mpi_get CASCADE;
CREATE TABLE mpi_get (
    mpi_get_id  serial,

    -- Current Max: 21 chars
    mpi_name    varchar(64) NOT NULL DEFAULT 'bogus',
    -- Current Max: 24 chars
    mpi_version varchar(128) NOT NULL DEFAULT 'bogus',

    UNIQUE (
            mpi_name,
            mpi_version
    ),

    PRIMARY KEY (mpi_get_id)
);

--
-- Results: Description Normalization table
--
DROP TABLE description CASCADE;
CREATE TABLE description (
    description_id  serial,

    description     text DEFAULT 'bogus',

    PRIMARY KEY (description_id)
);

--
-- Results: Result Message Normalization table
--
DROP TABLE result_message CASCADE;
CREATE TABLE result_message (
    result_message_id  serial,

    result_message     text DEFAULT 'bogus',

    PRIMARY KEY (result_message_id)
);

--
-- Results: Environment Normalization table
--
DROP TABLE environment CASCADE;
CREATE TABLE environment (
    environment_id  serial,

    environment     text DEFAULT 'bogus',

    PRIMARY KEY (environment_id)
);


--
-- MPI Install Configure Argument Normalization table
--
DROP TABLE mpi_install_configure_args CASCADE;
CREATE TABLE mpi_install_configure_args (
    mpi_install_configure_id        serial,

    -- http://www.postgresql.org/docs/8.2/interactive/datatype-bit.html
    -- 00 = none
    -- 01 = relative
    -- 10 = absolute
    vpath_mode          bit(2)  NOT NULL DEFAULT B'00',
    -- 000000 = unknown
    -- 000001 = 8
    -- 000010 = 16
    -- 000100 = 32
    -- 001000 = 64
    -- 010000 = 128
    bitness             bit(6) NOT NULL DEFAULT B'000000',
    -- 00 = unknown
    -- 01 = little
    -- 10 = big
    -- 11 = both (Mac OS X Universal Binaries)
    endian              bit(2) NOT NULL DEFAULT B'00',

    -- Current Max: 1319 chars
    configure_arguments text NOT NULL DEFAULT '', 

    UNIQUE (
            vpath_mode,
            bitness,
            endian,
            configure_arguments
    ),

    PRIMARY KEY (mpi_install_configure_id)
);

--
-- Collect 'results' data into a table for easy updating
-- Note: Never select on this table, it give missleading results.
--  It will count all the tuples of its children even though it 
--  doesn't contain any tuples. I guess this is a quick way to 
--  get the total number of results in the database across the
--  three partiion tables.
--
DROP TABLE results_fields CASCADE;
CREATE TABLE results_fields (
    description_id      integer NOT NULL,

    start_timestamp     timestamp without time zone NOT NULL DEFAULT now() - interval '24 hours',
    -- result value: 0=fail, 1=pass, 2=skipped, 3=timed out
    test_result         smallint NOT NULL DEFAULT '-38',
    -- flag data submitted by experimental MTT runs
    trial               boolean DEFAULT 'f',
    submit_timestamp    timestamp without time zone NOT NULL DEFAULT now(),
    duration            interval NOT NULL DEFAULT '-38 seconds',
    environment_id      integer NOT NULL,
    result_stdout       text NOT NULL DEFAULT '', 
    result_stderr       text NOT NULL DEFAULT '',
    result_message_id   integer NOT NULL,
    merge_stdout_stderr boolean NOT NULL DEFAULT 't',
    -- set if process exited
    exit_value          integer NOT NULL DEFAULT '-38',
    -- set if process was signaled
    exit_signal         integer NOT NULL DEFAULT '-38',
    -- keep track of individual MTT runs
    client_serial       integer NOT NULL DEFAULT '-38'
);

--
-- MPI Install Table
--
DROP TABLE mpi_install CASCADE;
CREATE TABLE mpi_install (
    mpi_install_id      serial,

    submit_id           integer NOT NULL DEFAULT '-38',
    compute_cluster_id  integer NOT NULL DEFAULT '-38',
    mpi_install_compiler_id         integer NOT NULL DEFAULT '-38',
    mpi_get_id          integer NOT NULL DEFAULT '-38',
    mpi_install_configure_id        integer NOT NULL DEFAULT '-38',

    -- ********** --

    PRIMARY KEY (mpi_install_id),

    FOREIGN KEY (submit_id) REFERENCES submit(submit_id),
    FOREIGN KEY (compute_cluster_id) REFERENCES compute_cluster(compute_cluster_id),
    FOREIGN KEY (mpi_install_compiler_id) REFERENCES compiler(compiler_id),
    FOREIGN KEY (mpi_get_id) REFERENCES mpi_get(mpi_get_id),
    FOREIGN KEY (mpi_install_configure_id) REFERENCES mpi_install_configure_args(mpi_install_configure_id),
    FOREIGN KEY (description_id) REFERENCES description(description_id),
    FOREIGN KEY (environment_id) REFERENCES environment(environment_id),
    FOREIGN KEY (result_message_id) REFERENCES result_message(result_message_id)

) INHERITS(results_fields);

--
-- Test Suite Table
--
DROP TABLE test_suites CASCADE;
CREATE TABLE test_suites (
    test_suite_id       serial,

    -- Current Max: 15 chars
    suite_name          varchar(32) NOT NULL DEFAULT 'bogus',
    test_suite_description         text DEFAULT '',

    UNIQUE (
        suite_name
    ),

    PRIMARY KEY (test_suite_id)
);

--
-- Ind. Test Name Table
-- NOTE: Test names are assumed to be unique in a test suite
--
DROP TABLE test_names CASCADE;
CREATE TABLE test_names (
    test_name_id        serial,

    test_suite_id       integer NOT NULL,

    -- Current Max: 39  chars
    test_name           varchar(64) NOT NULL DEFAULT 'bogus',
    test_name_description         text DEFAULT '',

    UNIQUE (
        test_suite_id,
        test_name
    ),

    PRIMARY KEY (test_name_id),

    FOREIGN KEY (test_suite_id) REFERENCES test_suites(test_suite_id)
);

--
-- Test Build Table
--
DROP TABLE test_build CASCADE;
CREATE TABLE test_build (
    test_build_id       serial,

    submit_id           integer NOT NULL DEFAULT '-38',
    compute_cluster_id  integer NOT NULL DEFAULT '-38',
    mpi_install_compiler_id         integer NOT NULL DEFAULT '-38',
    mpi_get_id          integer NOT NULL DEFAULT '-38',
    mpi_install_configure_id        integer NOT NULL DEFAULT '-38',
    mpi_install_id      integer NOT NULL DEFAULT '-38',
    test_suite_id       integer NOT NULL DEFAULT '-38',
    test_build_compiler_id         integer NOT NULL DEFAULT '-38',

    -- ********** --

    PRIMARY KEY (test_build_id),

    FOREIGN KEY (submit_id) REFERENCES submit(submit_id),
    FOREIGN KEY (compute_cluster_id) REFERENCES compute_cluster(compute_cluster_id),
    FOREIGN KEY (mpi_install_compiler_id) REFERENCES compiler(compiler_id),
    FOREIGN KEY (mpi_get_id) REFERENCES mpi_get(mpi_get_id), 
    FOREIGN KEY (mpi_install_configure_id) REFERENCES mpi_install_configure_args(mpi_install_configure_id),
    -- PARTITION/FK PROBLEM: FOREIGN KEY (mpi_install_id) REFERENCES mpi_install(mpi_install_id),
    FOREIGN KEY (test_suite_id) REFERENCES test_suites(test_suite_id),
    FOREIGN KEY (test_build_compiler_id) REFERENCES compiler(compiler_id),
    FOREIGN KEY (description_id) REFERENCES description(description_id),
    FOREIGN KEY (environment_id) REFERENCES environment(environment_id),
    FOREIGN KEY (result_message_id) REFERENCES result_message(result_message_id)
) INHERITS(results_fields);

--
-- Latency/Bandwidth Table
--
DROP TABLE latency_bandwidth CASCADE;
CREATE TABLE latency_bandwidth (
    latency_bandwidth_id    serial,

    message_size            integer[] DEFAULT '{}',
    bandwidth_min           double precision[] DEFAULT '{}',
    bandwidth_max           double precision[] DEFAULT '{}',
    bandwidth_avg           double precision[] DEFAULT '{}',
    latency_min             double precision[] DEFAULT '{}',
    latency_max             double precision[] DEFAULT '{}',
    latency_avg             double precision[] DEFAULT '{}',

    PRIMARY KEY (latency_bandwidth_id)
);

--
-- Performance Table
--
DROP TABLE performance CASCADE;
CREATE TABLE performance (
    performance_id          serial,

    latency_bandwidth_id    integer,

    PRIMARY KEY (performance_id),

    FOREIGN KEY (latency_bandwidth_id) REFERENCES latency_bandwidth(latency_bandwidth_id)
);

--
-- Interconnect Normalization table
--
DROP TABLE interconnects CASCADE;
CREATE TABLE interconnects (
    interconnect_id         serial,

    interconnect_name       varchar(32),

    PRIMARY KEY (interconnect_id)
);

--
-- Test Run Command Network Normalization Table
--
DROP SEQUENCE test_run_network_id;
CREATE SEQUENCE test_run_network_id;


DROP TABLE test_run_networks CASCADE;
CREATE TABLE test_run_networks (
    -- This value should never be referenced!
    network_id              serial,

    test_run_network_id     int,
    interconnect_id         int,

    PRIMARY KEY (network_id),

    FOREIGN KEY (interconnect_id) REFERENCES interconnects(interconnect_id)
);


--
-- Test Run Command Normalization Table
--
DROP TABLE test_run_command CASCADE;
CREATE TABLE test_run_command (
    test_run_command_id          serial,

    -- mpirun, mpiexec, yod, ...
    launcher            varchar(16) DEFAULT '',
    -- Resource Manager [RSH, SLURM, PBS, ...]
    resource_mgr        varchar(32) DEFAULT '',
    -- Runtime Parameters [MCA, SSI, ...]
    parameters          text DEFAULT '',
    -- Network
    network             varchar(32) DEFAULT '',
    test_run_network_id int DEFAULT 0,

    PRIMARY KEY (test_run_command_id)
);

--
-- Test Run Table
-- NOTE:
--  This is the parent partition table which defines the fields and basic constraints.
--  It will never contain any information, but serve as a point of reference.
--  Use the create-partitions.pl script to generate the child table SQL commands
--  Needed to link with this table.
--
DROP TABLE test_run CASCADE;
CREATE TABLE test_run (
    test_run_id         serial,

    submit_id           integer NOT NULL DEFAULT '-38',
    compute_cluster_id  integer NOT NULL DEFAULT '-38',
    mpi_install_compiler_id         integer NOT NULL DEFAULT '-38',
    mpi_get_id          integer NOT NULL DEFAULT '-38',
    mpi_install_configure_id        integer NOT NULL DEFAULT '-38',
    mpi_install_id      integer NOT NULL DEFAULT '-38',
    test_suite_id       integer NOT NULL DEFAULT '-38',
    test_build_compiler_id         integer NOT NULL DEFAULT '-38',
    test_build_id       integer NOT NULL DEFAULT '-38',
    test_name_id        integer NOT NULL DEFAULT '-38',
    performance_id      integer  DEFAULT '-38',
    test_run_command_id integer NOT NULL DEFAULT '-38',

    np                  smallint NOT NULL DEFAULT '-38',
    full_command        text NOT NULL DEFAULT 'bogus',

    -- ********** --

    PRIMARY KEY (test_run_id),

    FOREIGN KEY (submit_id) REFERENCES submit(submit_id),
    FOREIGN KEY (compute_cluster_id) REFERENCES compute_cluster(compute_cluster_id),
    FOREIGN KEY (mpi_install_compiler_id) REFERENCES compiler(compiler_id),
    FOREIGN KEY (mpi_get_id) REFERENCES mpi_get(mpi_get_id),
    FOREIGN KEY (mpi_install_configure_id) REFERENCES mpi_install_configure_args(mpi_install_configure_id),
    -- PARTITION/FK PROBLEM: FOREIGN KEY (mpi_install_id) REFERENCES mpi_install(mpi_install_id),
    FOREIGN KEY (test_suite_id) REFERENCES test_suites(test_suite_id),
    FOREIGN KEY (test_build_compiler_id) REFERENCES compiler(compiler_id),
    -- PARTITION/FK PROBLEM: FOREIGN KEY (test_build_id) REFERENCES test_build(test_build_id),
    FOREIGN KEY (test_name_id) REFERENCES test_names(test_name_id),
    FOREIGN KEY (performance_id) REFERENCES performance(performance_id),
    FOREIGN KEY (test_run_command_id) REFERENCES test_run_command(test_run_command_id),
    FOREIGN KEY (description_id) REFERENCES description(description_id),
    FOREIGN KEY (environment_id) REFERENCES environment(environment_id),
    FOREIGN KEY (result_message_id) REFERENCES result_message(result_message_id)

) INHERITS(results_fields);


-- ****************************************** --
-- Temporary Conversion tables
-- ****************************************** --
--
-- Cluster Table
--
DROP TABLE temp_conv_compute_cluster CASCADE;
CREATE TABLE temp_conv_compute_cluster (
    new_compute_cluster_id  integer NOT NULL,
    old_compute_cluster_id  integer NOT NULL
);
CREATE INDEX temp_conv_compute_cluster_idx ON temp_conv_compute_cluster (old_compute_cluster_id);

--
-- Submit Table
--
DROP TABLE temp_conv_submit CASCADE;
CREATE TABLE temp_conv_submit (
    new_submit_id  integer NOT NULL,
    old_submit_id  integer NOT NULL
);
CREATE INDEX temp_conv_submit_idx ON temp_conv_submit (old_submit_id);

--
-- Compiler Table
--
DROP TABLE temp_conv_compiler CASCADE;
CREATE TABLE temp_conv_compiler (
    new_compiler_id  integer NOT NULL,
    old_compiler_id  integer NOT NULL
);
CREATE INDEX temp_conv_compiler_idx ON temp_conv_compiler (old_compiler_id);

--
-- Mpi_Get Table
--
DROP TABLE temp_conv_mpi_get CASCADE;
CREATE TABLE temp_conv_mpi_get (
    new_mpi_get_id  integer NOT NULL,
    old_mpi_get_id  integer NOT NULL
);
CREATE INDEX temp_conv_mpi_get_idx ON temp_conv_mpi_get (old_mpi_get_id);

--
-- Latency_Bandwidth Table
--
DROP TABLE temp_conv_latency_bandwidth CASCADE;
CREATE TABLE temp_conv_latency_bandwidth (
    new_latency_bandwidth_id  integer NOT NULL,
    old_latency_bandwidth_id  integer NOT NULL
);
CREATE INDEX temp_conv_latency_bandwidth_idx ON temp_conv_latency_bandwidth (old_latency_bandwidth_id);

--
-- MPI Install
--
DROP TABLE temp_conv_mpi_install CASCADE;
CREATE TABLE temp_conv_mpi_install (
    new_mpi_install_id  integer NOT NULL,

    old_mpi_install_id  integer NOT NULL,
    old_results_id      integer NOT NULL
);

CREATE INDEX temp_conv_mpi_install_idx ON temp_conv_mpi_install (old_results_id);

--
-- Test Build
--
DROP TABLE temp_conv_test_build CASCADE;
CREATE TABLE temp_conv_test_build (
    new_test_build_id  integer NOT NULL,

    old_test_build_id  integer NOT NULL,
    old_results_id      integer NOT NULL
);

CREATE INDEX temp_conv_test_build_idx ON temp_conv_test_build (old_results_id);

--
-- Test Run
--
DROP TABLE temp_conv_test_run CASCADE;
CREATE TABLE temp_conv_test_run (
    new_test_run_id  integer NOT NULL,

    old_test_run_id  integer NOT NULL,
    old_results_id      integer NOT NULL
);

CREATE INDEX temp_conv_test_run_idx ON temp_conv_test_run (old_results_id);

--
-- Add a 'none' value to the latency-bandwidth table
-- This allows the foreign key constraint to work on all test_run entries,
-- even those that don't have latency/bandwidth data.
--
INSERT INTO latency_bandwidth VALUES(0);
INSERT INTO performance VALUES(0,0);

--
-- Add empty row to the description table
--
INSERT INTO description VALUES(0, '');

--
-- Add empty row to the environment table
--
INSERT INTO environment VALUES(0, '');

--
-- Add empty row to test_run_command as a placeholder
--
INSERT INTO test_run_command VALUES(0, '', '', '', '');

--
-- Add empty row to test_run_networks and interconnects
--
INSERT INTO interconnects VALUES(0, '');
INSERT INTO test_run_networks VALUES(0, 0, 0);

--
-- Add the partition tables
--
\i 2006-mpi-install.sql
\i 2006-test-build.sql
\i 2006-test-run.sql

\i 2007-mpi-install.sql
\i 2007-test-build.sql
\i 2007-test-run.sql

--
-- Add the partition table indexes
--
\i 2006-indexes.sql
\i 2007-indexes.sql
