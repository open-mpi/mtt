-- Create virtual tables (aka VIEWs) for the three
-- phases. Naming scheme is the phase name suffixed
-- by '_view'

DROP VIEW all_view CASCADE;
CREATE VIEW all_view AS
SELECT
    start_timestamp,
    http_username,
    local_username,
    hostname,
    bitness,
    compiler_name,
    compiler_version,
    configure_arguments,
    mpi_name,
    mpi_version,
    os_name,
    os_version,
    platform_hardware,
    platform_name,
    platform_type,
    trial,
    (CASE WHEN
      test_result = 0
      THEN '_if' END) as fail,
    (CASE WHEN
      test_result = 1
      THEN '_ip' END) as pass,

    -- These are just place holder columns needed because
    -- UNION requires each query in the UNION have identical
    -- columns
    '' as skipped,
    '' as timed_out,
    '' as latency_bandwidth
FROM
    (results NATURAL JOIN submit) JOIN 
        (mpi_install NATURAL JOIN
          compute_cluster NATURAL JOIN
            compiler NATURAL JOIN
                mpi_get)
    ON (results.phase = 1 AND phase_id = mpi_install_id)

UNION ALL

SELECT
    start_timestamp,
    http_username,
    local_username,
    hostname,
    bitness,
    compiler_name,
    compiler_version,
    configure_arguments,
    mpi_name,
    mpi_version,
    os_name,
    os_version,
    platform_hardware,
    platform_name,
    platform_type,
    trial,
    (CASE WHEN
      test_result = 0
      THEN '_bf' END) as fail,
    (CASE WHEN
      test_result = 1
      THEN '_bp' END) as pass,

    -- These are just place holder columns needed because
    -- UNION requires each query in the UNION have identical
    -- columns
    '' as skipped,
    '' as timed_out,
    '' as latency_bandwidth
FROM
    (results NATURAL JOIN submit) JOIN 
        (test_build NATURAL JOIN
            (mpi_install NATURAL JOIN
              compute_cluster NATURAL JOIN
                compiler NATURAL JOIN
                    mpi_get))
    ON (results.phase = 2 AND phase_id = test_build_id)

UNION ALL

SELECT
    start_timestamp,
    http_username,
    local_username,
    hostname,
    bitness,
    compiler_name,
    compiler_version,
    configure_arguments,
    mpi_name,
    mpi_version,
    os_name,
    os_version,
    platform_hardware,
    platform_name,
    platform_type,
    trial,
    (CASE WHEN
      test_result = 0
      THEN '_rf' END) as fail,
    (CASE WHEN
      test_result = 1
      THEN '_rp' END) as pass,
    (CASE WHEN
      test_result = 2
      THEN '_rs' END) as skipped,
    (CASE WHEN
      test_result = 3
      THEN '_rt' END) as timed_out,
    (CASE WHEN
      results.latency_bandwidth_id != -38
      THEN '_rl' END) as latency_bandwidth
FROM
    (results NATURAL JOIN submit)
    JOIN test_run NATURAL JOIN
        (test_build NATURAL JOIN
            (mpi_install NATURAL JOIN
              compute_cluster NATURAL JOIN
                compiler NATURAL JOIN
                    mpi_get))
    ON (results.phase = 3 AND 
        phase_id = test_run_id)
    LEFT OUTER JOIN latency_bandwidth 
        USING (latency_bandwidth_id)
;

DROP VIEW mpi_install_view CASCADE;
CREATE VIEW mpi_install_view AS
SELECT

    -- compute_cluster
    os_name,
    os_version,
    platform_hardware,
    platform_name,
    platform_type,

    -- mpi_install
    mpi_name,
    mpi_version,
    compiler_name,
    compiler_version,
    configure_arguments,
    vpath_mode,
    endian,
    bitness,

    -- submit
    http_username,
    local_username,
    hostname,

    -- results
    exit_status,
    signal,
    start_timestamp,
    duration,
    result_message,
    result_stdout,
    result_stderr,
    environment,
    client_serial,
    trial,

    (CASE WHEN
      test_result = 0
      THEN '_if' END) as fail,
    (CASE WHEN
      test_result = 1
      THEN '_ip' END) as pass
FROM
    (results NATURAL JOIN submit) JOIN 
        (mpi_install NATURAL JOIN
          compute_cluster NATURAL JOIN
            compiler NATURAL JOIN
                mpi_get)
    ON (results.phase = 1 AND phase_id = mpi_install_id)
;

DROP VIEW test_build_view CASCADE;
CREATE VIEW test_build_view AS
SELECT

    -- compute_cluster
    os_name,
    os_version,
    platform_hardware,
    platform_name,
    platform_type,

    -- mpi_install
    mpi_name,
    mpi_version,

    -- test_build
    suite_name,
    compiler_name,
    compiler_version,
    bitness,

    -- submit
    http_username,
    local_username,
    hostname,

    -- results
    exit_status,
    signal,
    start_timestamp,
    duration,
    result_message,
    result_stdout,
    result_stderr,
    environment,
    client_serial,
    trial,

    (CASE WHEN
      test_result = 0
      THEN '_bf' END) as fail,
    (CASE WHEN
      test_result = 1
      THEN '_bp' END) as pass
FROM
    (results NATURAL JOIN submit) JOIN 
        (test_build NATURAL JOIN
            (mpi_install NATURAL JOIN
              compute_cluster NATURAL JOIN
                compiler NATURAL JOIN
                    mpi_get))
    ON (results.phase = 2 AND phase_id = test_build_id)
;

DROP VIEW test_run_view CASCADE;
CREATE VIEW test_run_view AS
SELECT

    -- compute_cluster
    os_name,
    os_version,
    platform_hardware,
    platform_name,
    platform_type,

    -- mpi_install
    mpi_name,
    mpi_version,

    -- test_build
    suite_name,

    -- test_run
    test_name,
    command,
    np,
    variant,

    -- submit
    http_username,
    local_username,
    hostname,

    -- results
    exit_status,
    signal,
    start_timestamp,
    duration,
    result_message,
    result_stdout,
    result_stderr,
    environment,
    client_serial,
    trial,

    -- latency_bandwidth
    message_size,
    bandwidth_min,
    bandwidth_max,
    bandwidth_avg,
    latency_min,
    latency_max,
    latency_avg,

    -- results
    (CASE WHEN
      test_result = 1
      THEN '_rp' END) as pass,
    (CASE WHEN
      test_result = 0
      THEN '_rf' END) as fail,
    (CASE WHEN
      test_result = 2
      THEN '_rs' END) as skipped,
    (CASE WHEN
      test_result = 3
      THEN '_rt' END) as timed_out,
    (CASE WHEN
      results.latency_bandwidth_id != -38
      THEN '_rl' END) as latency_bandwidth
FROM
    results NATURAL JOIN submit
    JOIN test_run NATURAL JOIN
        (test_build NATURAL JOIN
            (mpi_install NATURAL JOIN
              compute_cluster NATURAL JOIN
                compiler NATURAL JOIN
                    mpi_get))
    ON (results.phase = 3 AND 
        phase_id = test_run_id)
    LEFT OUTER JOIN latency_bandwidth 
        USING (latency_bandwidth_id)
;
