--
-- Open MPI Testing Stats
--
-- Stats are to be collected daily
--

--
-- Contribution/Coverage table
--
DROP TABLE mtt_stats_contrib CASCADE;
CREATE TABLE mtt_stats_contrib (
    mtt_stats_contrib_id            serial,

    -- Day Represented (One day increments 9 pm - 9pm)
    collection_date             date,
    is_day                      boolean,
    is_month                    boolean,
    is_year                     boolean,

    -- Org name = submit.http_username
    org_name                    char(16),

    -- Platform Name
    -- Total = select count(distinct(platform)) from ...
    platform_name               varchar(128),

    -- OS Name
    os_name                     varchar(128),

    -- Compiler Name/Version
    --   MPI Install
    mpi_install_compiler_name    varchar(64),
    mpi_install_compiler_version varchar(64),
    --   Test Build
    test_build_compiler_name     varchar(64),
    test_build_compiler_version  varchar(64),

    -- MPI Get Name/Version
    mpi_get_name                varchar(64),
    mpi_get_version             varchar(32),

    -- MPI Install Configuration
    -- (use configure_id, we can join to get the data later)
    mpi_install_config          integer,

    -- Test Suite Name
    test_suite                  varchar(32),

    -- Launcher
    launcher                    varchar(128),

    -- Resource Mgr
    resource_mgr                varchar(32),

    -- Network
    network                     varchar(32),

    -- # of distinct tests ran (test_names) for a test_suite
    num_tests                   integer,

    -- # of distinct MCA params
    num_parameters              integer,

    -- 
    -- # of mpi_install pass/fail
    num_mpi_install_pass        integer,
    num_mpi_install_fail        integer,

    -- # of test_build pass/fail
    num_test_build_pass         integer,
    num_test_build_fail         integer,

    -- # of test_run pass/fail/skip/timed/perf
    num_test_run_pass           integer,
    num_test_run_fail           integer,
    num_test_run_skip           integer,
    num_test_run_timed          integer,
    num_test_run_perf           integer,
    
    PRIMARY KEY (mtt_stats_contrib_id)
);

--
-- Database Stats table
--
DROP TABLE mtt_stats_database CASCADE;
CREATE TABLE mtt_stats_database (
    mtt_stats_database_id       serial,

    -- One day increments 9 pm - 9pm
    collection_date             date DEFAULT now(),

    -- DB size in Bytes
    -- select pg_database_size('mtt')
    -- select pg_size_pretty(pg_database_size('mtt'))
    size_db                     bigint,

    -- # Tuples in all tables
    num_tuples                  bigint,
    -- # Tuples in mpi_install
    num_tuples_mpi_install      bigint,
    -- # Tuples in test_build
    num_tuples_test_build       bigint,
    -- # Tuples in test_run
    num_tuples_test_run         bigint,

    PRIMARY KEY (mtt_stats_database_id)
);
