DROP TABLE summary_mpi_install;
DROP TABLE summary_test_build;
DROP TABLE summary_test_run;
DROP TABLE summary_base;

DROP TABLE summary_range;

--
-- A table to quickly lookup the earliest date for which there is summary data.
--
CREATE TABLE summary_range (
    range_id          serial,
    start_timestamp   timestamp without time zone NOT NULL DEFAULT now() - interval '24 hours',
    end_timestamp     timestamp without time zone NOT NULL DEFAULT now() - interval '24 hours',
    time_interval     interval
);

-- INSERT INTO summary_range
--     (SELECT 1, min_start, min_end, (min_end-min_start) as interval
--      FROM (
--         SELECT
--             MIN(start_timestamp) as min_start,
--             MIN(end_timestamp) as min_end
--         FROM summary_mpi_install
--         ) as foo
--     );

-- UPDATE summary_range
--     SET
--         start_timestamp = (SELECT MIN(start_timestamp) FROM summary_mpi_install),
--         end_timestamp = (SELECT MIN(end_timestamp) FROM summary_mpi_install),
--         time_interval = (SELECT (MIN(end_timestamp) - MIN(start_timestamp)) FROM summary_mpi_install)
--     WHERE range_id = 1;

--
-- Base table for summary data
--
CREATE TABLE summary_base (
    -- select date_trunc('hour', now()) --
    start_timestamp   timestamp without time zone NOT NULL DEFAULT now() - interval '24 hours',
    end_timestamp     timestamp without time zone NOT NULL DEFAULT now() - interval '24 hours',

    trial             boolean DEFAULT 'f',

    --
    -- Submit
    --
    submit_http_username              varchar(16)  NOT NULL DEFAULT 'bogus',

    --
    -- Compute Cluster
    --
    compute_cluster_platform_name     varchar(128) NOT NULL DEFAULT 'bogus',
    compute_cluster_platform_hardware varchar(128) NOT NULL DEFAULT 'bogus',
    compute_cluster_os_name           varchar(128) NOT NULL DEFAULT 'bogus',

    --
    -- MPI Get
    --
    mpi_get_mpi_name       varchar(64) NOT NULL DEFAULT 'bogus',
    mpi_get_mpi_version    varchar(128) NOT NULL DEFAULT 'bogus',

    --
    -- MPI Install Configure Args
    --
    mpi_install_configure_args_bitness   bit(6) NOT NULL DEFAULT B'000000',
    mpi_install_configure_args_endian    bit(2) NOT NULL DEFAULT B'00',

    --
    -- Compiler
    --
    compiler_compiler_name      varchar(64) NOT NULL DEFAULT 'bogus',
    compiler_compiler_version   varchar(64) NOT NULL DEFAULT 'bogus',

    pass smallint NOT NULL DEFAULT '0',
    fail smallint NOT NULL DEFAULT '0'
);

--
-- Summary table for mpi_install
--
CREATE TABLE summary_mpi_install (
    summary_mpi_install_id      serial,
    -- ********** --
    PRIMARY KEY (summary_mpi_install_id)
) INHERITS(summary_base);

--
-- Summary table for test_build
--
CREATE TABLE summary_test_build (
    summary_test_build_id      serial,

    --
    -- Test Suite
    --
    test_suites_suite_name   varchar(32) DEFAULT 'bogus',

    -- ********** --
    PRIMARY KEY (summary_test_build_id)
) INHERITS(summary_base);

--
-- Summary table for test_run
--
CREATE TABLE summary_test_run (
    summary_test_run_id      serial,

    --
    -- Test Suite
    --
    test_suites_suite_name   varchar(32) DEFAULT 'bogus',

    --
    -- Test Run
    --
    np                  smallint DEFAULT (-38),

    --
    -- Additional Result Cases
    --
    skip smallint NOT NULL DEFAULT '0',
    timeout smallint NOT NULL DEFAULT '0',
    perf smallint NOT NULL DEFAULT '0',

    -- ********** --
    PRIMARY KEY (summary_test_run_id)
) INHERITS(summary_base);
