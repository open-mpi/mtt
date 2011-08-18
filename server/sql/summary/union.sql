EXPLAIN
ANALYZE
SELECT
    submit_http_username,
    compute_cluster_platform_name,
    compute_cluster_platform_hardware,
    compute_cluster_os_name,
    mpi_get_mpi_name,
    mpi_get_mpi_version,
    SUM(_mpi_p) as _mpi_p,
    SUM(_mpi_f) as _mpi_f,
    SUM(_build_p) as _build_p,
    SUM(_build_f) as _build_f,
    SUM(_run_p) as _run_p,
    SUM(_run_f) as _run_f,
    SUM(_run_s) as _run_s,
    SUM(_run_t) as _run_t,
    SUM(_run_l) as _run_l
FROM (
    (
    SELECT
    start_timestamp,
    end_timestamp,
    submit_http_username,
    compute_cluster_platform_name,
    compute_cluster_platform_hardware,
    compute_cluster_os_name,
    mpi_get_mpi_name,
    mpi_get_mpi_version,
    mpi_install_configure_args_bitness,
    mpi_install_configure_args_endian,
    compiler_compiler_name,
    compiler_compiler_version,
    test_suites_suite_name,
    np,
    pass as _mpi_p,
    fail as _mpi_f,
    (0) as _build_p,
    (0) as _build_f,
    (0) as _run_p,
    (0) as _run_f,
    (0) as _run_s,
    (0) as _run_t,
    (0) as _run_l
    FROM
    summary_mpi_install
    WHERE
    (start_timestamp > date_trunc('hour', (now() - interval '24 hours')) AND
     start_timestamp < date_trunc('hour', (now() - interval '-1 hours')) AND submit_http_username = 'iu')
    )
    UNION ALL
    (
    SELECT
    start_timestamp,
    end_timestamp,
    submit_http_username,
    compute_cluster_platform_name,
    compute_cluster_platform_hardware,
    compute_cluster_os_name,
    mpi_get_mpi_name,
    mpi_get_mpi_version,
    mpi_install_configure_args_bitness,
    mpi_install_configure_args_endian,
    compiler_compiler_name,
    compiler_compiler_version,
    test_suites_suite_name,
    np,
    (0) as _mpi_p,
    (0) as _mpi_f,
    pass as _build_p,
    fail as _build_f,
    (0) as _run_p,
    (0) as _run_f,
    (0) as _run_s,
    (0) as _run_t,
    (0) as _run_l
    FROM
    summary_test_build
    WHERE
    (start_timestamp > date_trunc('hour', (now() - interval '24 hours')) AND
     start_timestamp < date_trunc('hour', (now() - interval '-1 hours')) AND submit_http_username = 'iu')
    )
    UNION ALL
    (
    SELECT
    start_timestamp,
    end_timestamp,
    submit_http_username,
    compute_cluster_platform_name,
    compute_cluster_platform_hardware,
    compute_cluster_os_name,
    mpi_get_mpi_name,
    mpi_get_mpi_version,
    mpi_install_configure_args_bitness,
    mpi_install_configure_args_endian,
    compiler_compiler_name,
    compiler_compiler_version,
    test_suites_suite_name,
    np,
    (0) as _mpi_p,
    (0) as _mpi_f,
    (0) as _build_p,
    (0) as _build_f,
    pass as _run_p,
    fail as _run_f,
    skip as _run_s,
    timeout as _run_t,
    perf as _run_l
    FROM
    summary_test_run
    WHERE
    (start_timestamp > date_trunc('hour', (now() - interval '24 hours')) AND
     start_timestamp < date_trunc('hour', (now() - interval '-1 hours')) AND submit_http_username = 'iu')
    )
) as summary
GROUP BY
    submit_http_username,
    compute_cluster_platform_name,
    compute_cluster_platform_hardware,
    compute_cluster_os_name,
    mpi_get_mpi_name,
    mpi_get_mpi_version
ORDER BY
    submit_http_username,
    compute_cluster_platform_name,
    compute_cluster_platform_hardware,
    compute_cluster_os_name,
    mpi_get_mpi_name,
    mpi_get_mpi_version
;


    

