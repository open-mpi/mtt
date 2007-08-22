--
-- A list of additional indexes to be applied to the database
--

--
-- Compute Cluster Table
--
-- NONE: compute_cluster

--
-- Submit Table
--
--
DROP INDEX idx_submit_http_username;
CREATE INDEX idx_submit_http_username on submit (http_username);


--
-- Compiler Table
--
-- NONE: compiler

--
-- MPI Get Table
--
-- NONE: mpi_get

--
-- MPI Install Configure Args Table
--
-- NONE: mpi_install_configure_args

--
-- MPI Install table
--
DROP INDEX idx_mpi_install_submit_id;
CREATE INDEX idx_mpi_install_submit_id          ON mpi_install (submit_id);
DROP INDEX idx_mpi_install_compute_cluster_id;
CREATE INDEX idx_mpi_install_compute_cluster_id ON mpi_install (compute_cluster_id);
DROP INDEX idx_mpi_install_compiler_id;
CREATE INDEX idx_mpi_install_compiler_id        ON mpi_install (compiler_id);
DROP INDEX idx_mpi_install_mpi_get_id;
CREATE INDEX idx_mpi_install_mpi_get_id         ON mpi_install (mpi_get_id);
DROP INDEX idx_mpi_install_configure_id;
CREATE INDEX idx_mpi_install_configure_id       ON mpi_install (configure_id);


DROP INDEX idx_mpi_install_test_result;
CREATE INDEX idx_mpi_install_test_result        ON mpi_install (test_result);
DROP INDEX idx_mpi_install_exit_value;
CREATE INDEX idx_mpi_install_exit_value         ON mpi_install (exit_value);
DROP INDEX idx_mpi_install_client_serial;
CREATE INDEX idx_mpi_install_client_serial      ON mpi_install (client_serial);


--
-- Test Suites Table
--
-- NONE: test_suites

--
-- Test Names Table
--
DROP INDEX idx_test_names_test_suite_id;
CREATE INDEX idx_test_names_test_suite_id       ON test_names (test_suite_id);

--
-- Test Build table
--
DROP INDEX idx_test_build_submit_id;
CREATE INDEX idx_test_build_submit_id          ON test_build (submit_id);
DROP INDEX idx_test_build_compute_cluster_id;
CREATE INDEX idx_test_build_compute_cluster_id ON test_build (compute_cluster_id);
DROP INDEX idx_test_build_mpi_compiler_id;
CREATE INDEX idx_test_build_mpi_compiler_id    ON test_build (mpi_install_compiler_id);
DROP INDEX idx_test_build_mpi_get_id;
CREATE INDEX idx_test_build_mpi_get_id         ON test_build (mpi_get_id);
DROP INDEX idx_test_build_configure_id;
CREATE INDEX idx_test_build_configure_id       ON test_build (configure_id);

DROP INDEX idx_test_build_mpi_install_id;
CREATE INDEX idx_test_build_mpi_install_id     ON test_build (mpi_install_id);
DROP INDEX idx_test_build_test_suite_id;
CREATE INDEX idx_test_build_test_suite_id      ON test_build (test_suite_id);
DROP INDEX idx_test_build_test_compiler_id;
CREATE INDEX idx_test_build_test_compiler_id   ON test_build (test_build_compiler_id);

DROP INDEX idx_test_build_test_result;
CREATE INDEX idx_test_build_test_result        ON test_build (test_result);
DROP INDEX idx_test_build_exit_value;
CREATE INDEX idx_test_build_exit_value         ON test_build (exit_value);
DROP INDEX idx_test_build_client_serial;
CREATE INDEX idx_test_build_client_serial      ON test_build (client_serial);

--
-- Latency Bandwidth Table
--
-- NONE: latency_bandwidth

--
-- Test Run Command Table
--
-- NONE: test_run_command

--
-- Test Run Table
--
DROP INDEX idx_test_run_submit_id;
CREATE INDEX idx_test_run_submit_id          ON test_run (submit_id);
DROP INDEX idx_test_run_compute_cluster_id;
CREATE INDEX idx_test_run_compute_cluster_id ON test_run (compute_cluster_id);
DROP INDEX idx_test_run_mpi_compiler_id;
CREATE INDEX idx_test_run_mpi_compiler_id    ON test_run (mpi_install_compiler_id);
DROP INDEX idx_test_run_mpi_get_id;
CREATE INDEX idx_test_run_mpi_get_id         ON test_run (mpi_get_id);
DROP INDEX idx_test_run_configure_id;
CREATE INDEX idx_test_run_configure_id       ON test_run (configure_id);

DROP INDEX idx_test_run_mpi_install_id;
CREATE INDEX idx_test_run_mpi_install_id     ON test_run (mpi_install_id);
DROP INDEX idx_test_run_test_suite_id;
CREATE INDEX idx_test_run_test_suite_id      ON test_run (test_suite_id);
DROP INDEX idx_test_run_test_compiler_id;
CREATE INDEX idx_test_run_test_compiler_id   ON test_run (test_build_compiler_id);

DROP INDEX idx_test_run_test_build_id;
CREATE INDEX idx_test_run_test_build_id      ON test_run (test_build_id);
DROP INDEX idx_test_run_test_name_id;
CREATE INDEX idx_test_run_test_name_id       ON test_run (test_name_id);
DROP INDEX idx_test_run_latency_bandwidth_id;
CREATE INDEX idx_test_run_latency_bandwidth_id   ON test_run (latency_bandwidth_id);
DROP INDEX idx_test_run_command_id;
CREATE INDEX idx_test_run_command_id         ON test_run (command_id);

DROP INDEX idx_test_run_test_result;
CREATE INDEX idx_test_run_test_result        ON test_run (test_result);
DROP INDEX idx_test_run_exit_value;
CREATE INDEX idx_test_run_exit_value         ON test_run (exit_value);
DROP INDEX idx_test_run_client_serial;
CREATE INDEX idx_test_run_client_serial      ON test_run (client_serial);

