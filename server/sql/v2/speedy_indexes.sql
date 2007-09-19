--
-- Indexes for speedy tables
--

DROP INDEX idx_speedy_phase_id_pair;
CREATE INDEX idx_speedy_phase_id_pair ON speedy_results (phase_id, phase);
DROP INDEX idx_speedy_submit_id;
CREATE INDEX idx_speedy_submit_id     ON speedy_results (submit_id);
DROP INDEX idx_speedy_test_result;
CREATE INDEX idx_speedy_test_result   ON speedy_results (test_result);
DROP INDEX idx_speedy_client_serial;
CREATE INDEX idx_speedy_client_serial ON speedy_results (client_serial);
DROP INDEX idx_speedy_exit_value;
CREATE INDEX idx_speedy_exit_value    ON speedy_results (exit_value);

DROP INDEX idx_speedy_compute_cluster_id;
CREATE INDEX idx_speedy_compute_cluster_id   ON speedy_mpi_install (compute_cluster_id);
DROP INDEX idx_speedy_mpi_get_id;
CREATE INDEX idx_speedy_mpi_get_id           ON speedy_mpi_install (mpi_get_id);
DROP INDEX idx_speedy_compiler_id;
CREATE INDEX idx_speedy_compiler_id          ON speedy_mpi_install (compiler_id);
DROP INDEX idx_speedy_mpi_install_id;
CREATE INDEX idx_speedy_mpi_install_id       ON speedy_test_build (mpi_install_id);
DROP INDEX idx_speedy_test_build_id;
CREATE INDEX idx_speedy_test_build_id        ON speedy_test_run (test_build_id);
DROP INDEX idx_speedy_latency_bandwidth_id;
CREATE INDEX idx_speedy_latency_bandwidth_id ON speedy_results (latency_bandwidth_id);
DROP INDEX idx_speedy_latency_bandwidth;
CREATE INDEX idx_speedy_latency_bandwidth    ON speedy_results (test_result) WHERE latency_bandwidth_id != -38;
DROP INDEX idx_speedy_trial;
CREATE INDEX idx_speedy_trial                ON speedy_results (trial);
DROP INDEX idx_speedy_start_timestamp;
CREATE INDEX idx_speedy_start_timestamp      ON speedy_results (start_timestamp);
DROP INDEX idx_speedy_start_timestamp;
CREATE INDEX idx_speedy_start_timestamp      ON speedy_results (start_timestamp);
