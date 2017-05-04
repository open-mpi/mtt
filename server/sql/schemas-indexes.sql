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
DROP INDEX IF EXISTS idx_submit_http_username;
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
-- NONE: Partition base table

--
-- Test Suites Table
--
-- NONE: test_suites

--
-- Test Names Table
--
DROP INDEX IF EXISTS idx_test_names_test_suite_id;
CREATE INDEX idx_test_names_test_suite_id       ON test_names (test_suite_id);

--
-- Test Build table
--
-- NONE: Partition base table

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
-- NONE: Partition base table
