-- Create virtual tables (aka VIEWs) for the three
-- phases. Naming scheme is the phase name with "_"
-- prepended

DROP VIEW all_phases CASCADE;
CREATE VIEW all_phases AS
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
    (CASE WHEN
      test_result = 0
      THEN '_if' END) as fail,
    (CASE WHEN
      test_result = 1
      THEN '_ip' END) as pass,
    (CASE WHEN
      test_result = 2
      THEN '_is' END) as skipped,
    (CASE WHEN
      test_result = 3
      THEN '_it' END) as timed_out
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
    (CASE WHEN
      test_result = 0
      THEN '_bf' END) as fail,
    (CASE WHEN
      test_result = 1
      THEN '_bp' END) as pass,
    (CASE WHEN
      test_result = 2
      THEN '_bs' END) as skipped,
    (CASE WHEN
      test_result = 3
      THEN '_bt' END) as timed_out
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
      THEN '_rt' END) as timed_out
FROM
    (results NATURAL JOIN submit)
    JOIN test_run NATURAL JOIN
        (test_build NATURAL JOIN
            (mpi_install NATURAL JOIN
              compute_cluster NATURAL JOIN
                compiler NATURAL JOIN
                    mpi_get))
    ON (results.phase = 3 AND phase_id = test_run_id)
;

DROP VIEW mpi_install_view CASCADE;
CREATE VIEW mpi_install_view AS
SELECT

    -- submit
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

    -- results
    exit_status,
    start_timestamp,
    duration,
    result_message,
    result_stdout,
    result_stderr,
    environment,
    client_serial,

    (CASE WHEN
      test_result = 0
      THEN '_if' END) as fail,
    (CASE WHEN
      test_result = 1
      THEN '_ip' END) as pass,
    (CASE WHEN
      test_result = 2
      THEN '_is' END) as skipped,
    (CASE WHEN
      test_result = 3
      THEN '_it' END) as timed_out
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

    -- submit
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

    -- results
    exit_status,
    start_timestamp,
    duration,
    result_message,
    result_stdout,
    result_stderr,
    environment,
    client_serial,

    (CASE WHEN
      test_result = 0
      THEN '_bf' END) as fail,
    (CASE WHEN
      test_result = 1
      THEN '_bp' END) as pass,
    (CASE WHEN
      test_result = 2
      THEN '_bs' END) as skipped,
    (CASE WHEN
      test_result = 3
      THEN '_bt' END) as timed_out
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

    -- submit
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

    -- results
    exit_status,
    start_timestamp,
    duration,
    result_message,
    result_stdout,
    result_stderr,
    environment,
    client_serial,

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
      THEN '_rt' END) as timed_out
FROM
    (results NATURAL JOIN submit)
    JOIN test_run NATURAL JOIN
        (test_build NATURAL JOIN
            (mpi_install NATURAL JOIN
              compute_cluster NATURAL JOIN
                compiler NATURAL JOIN
                    mpi_get))
    ON (results.phase = 3 AND phase_id = test_run_id)
;

