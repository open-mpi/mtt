--
-- Open MPI Archive Test Results Tables 
--
-- (Speedy tables are pruned daily to reduce row counts
-- which makes for speedier queries.)
--
-- Usage: $ psql -d dbname -U dbusername -f this_filename
--

DROP TABLE speedy_compute_cluster   CASCADE;
DROP TABLE speedy_submit            CASCADE;
DROP TABLE speedy_mpi_get           CASCADE;
DROP TABLE speedy_compiler          CASCADE;
DROP TABLE speedy_mpi_install       CASCADE;
DROP TABLE speedy_test_build        CASCADE;
DROP TABLE speedy_test_run          CASCADE;
DROP TABLE speedy_results           CASCADE;
DROP TABLE speedy_latency_bandwidth CASCADE;
DROP TABLE speedy_alerts            CASCADE;
DROP TABLE speedy_users             CASCADE;
DROP TABLE speedy_failure           CASCADE;
DROP TABLE speedy_cluster_owner     CASCADE;

--
-- We use LIKE, and not INHERITS, because initially we need
-- to COPY data from the speedy tables to the archive tables
-- without those rows getting reflected in the the archive
-- tables
--

CREATE TABLE speedy_compute_cluster   (LIKE compute_cluster   INCLUDING DEFAULTS);
CREATE TABLE speedy_submit            (LIKE submit            INCLUDING DEFAULTS);
CREATE TABLE speedy_mpi_get           (LIKE mpi_get           INCLUDING DEFAULTS);
CREATE TABLE speedy_compiler          (LIKE compiler          INCLUDING DEFAULTS);
CREATE TABLE speedy_mpi_install       (LIKE mpi_install       INCLUDING DEFAULTS);
CREATE TABLE speedy_test_build        (LIKE test_build        INCLUDING DEFAULTS);
CREATE TABLE speedy_test_run          (LIKE test_run          INCLUDING DEFAULTS);
CREATE TABLE speedy_results           (LIKE results           INCLUDING DEFAULTS);
CREATE TABLE speedy_latency_bandwidth (LIKE latency_bandwidth INCLUDING DEFAULTS);
CREATE TABLE speedy_alerts            (LIKE alerts            INCLUDING DEFAULTS);
CREATE TABLE speedy_users             (LIKE users             INCLUDING DEFAULTS);
CREATE TABLE speedy_failure           (LIKE failure           INCLUDING DEFAULTS);
CREATE TABLE speedy_cluster_owner     (LIKE cluster_owner     INCLUDING DEFAULTS);

--
-- Copy the CONSTRAINTs over
--
-- A template for the following list can be generated using
-- this command:
--
-- $ pg_dump -d dbname -U dbusername -s | grep -E 'ADD CONSTRAINT' -A1 -B1
--

ALTER TABLE ONLY speedy_compute_cluster   ADD CONSTRAINT speedy_compute_cluster_pkey          PRIMARY KEY (compute_cluster_id);
ALTER TABLE ONLY speedy_compute_cluster   ADD CONSTRAINT speedy_compute_cluster_os_name_key   UNIQUE  (os_name, os_version, platform_hardware, platform_type, platform_name);
ALTER TABLE ONLY speedy_submit            ADD CONSTRAINT speedy_submit_pkey                   PRIMARY KEY (submit_id);
ALTER TABLE ONLY speedy_submit            ADD CONSTRAINT speedy_submit_mtt_version_major_key  UNIQUE  (mtt_version_major, mtt_version_minor, hostname, local_username, http_username);
ALTER TABLE ONLY speedy_mpi_get           ADD CONSTRAINT speedy_mpi_get_pkey                  PRIMARY KEY (mpi_get_id);
ALTER TABLE ONLY speedy_mpi_get           ADD CONSTRAINT speedy_mpi_get_mpi_name_key          UNIQUE  (mpi_name, mpi_version);
ALTER TABLE ONLY speedy_compiler          ADD CONSTRAINT speedy_compiler_pkey                 PRIMARY KEY (compiler_id);
ALTER TABLE ONLY speedy_compiler          ADD CONSTRAINT speedy_compiler_compiler_name_key    UNIQUE  (compiler_name, compiler_version);
ALTER TABLE ONLY speedy_mpi_install       ADD CONSTRAINT speedy_mpi_install_pkey              PRIMARY KEY (mpi_install_id);
ALTER TABLE ONLY speedy_test_build        ADD CONSTRAINT speedy_test_build_pkey               PRIMARY KEY (test_build_id);
ALTER TABLE ONLY speedy_test_build        ADD CONSTRAINT speedy_test_build_mpi_install_id_key UNIQUE  (mpi_install_id, suite_name, compiler_id);
ALTER TABLE ONLY speedy_test_run          ADD CONSTRAINT speedy_test_run_pkey                 PRIMARY KEY (test_run_id);
ALTER TABLE ONLY speedy_test_run          ADD CONSTRAINT speedy_test_run_test_build_id_key    UNIQUE  (test_build_id, variant, test_name, command, np);
ALTER TABLE ONLY speedy_results           ADD CONSTRAINT speedy_results_pkey                  PRIMARY KEY (results_id);
ALTER TABLE ONLY speedy_latency_bandwidth ADD CONSTRAINT speedy_latency_bandwidth_pkey        PRIMARY KEY (latency_bandwidth_id);
ALTER TABLE ONLY speedy_users             ADD CONSTRAINT speedy_users_pkey                    PRIMARY KEY (users_id);
ALTER TABLE ONLY speedy_cluster_owner     ADD CONSTRAINT speedy_cluster_owner_pkey            PRIMARY KEY (cluster_owner_id);

ALTER TABLE ONLY speedy_mpi_install       ADD CONSTRAINT "$1" FOREIGN KEY (compute_cluster_id) REFERENCES speedy_compute_cluster(compute_cluster_id);
ALTER TABLE ONLY speedy_mpi_install       ADD CONSTRAINT "$2" FOREIGN KEY (mpi_get_id)         REFERENCES speedy_mpi_get(mpi_get_id);
ALTER TABLE ONLY speedy_mpi_install       ADD CONSTRAINT "$3" FOREIGN KEY (compiler_id)        REFERENCES speedy_compiler(compiler_id);
ALTER TABLE ONLY speedy_test_build        ADD CONSTRAINT "$1" FOREIGN KEY (mpi_install_id)     REFERENCES speedy_mpi_install(mpi_install_id);
ALTER TABLE ONLY speedy_test_build        ADD CONSTRAINT "$2" FOREIGN KEY (compiler_id)        REFERENCES speedy_compiler(compiler_id);
ALTER TABLE ONLY speedy_test_run          ADD CONSTRAINT "$1" FOREIGN KEY (test_build_id)      REFERENCES speedy_test_build(test_build_id);
ALTER TABLE ONLY speedy_results           ADD CONSTRAINT "$1" FOREIGN KEY (submit_id)          REFERENCES speedy_submit(submit_id);
ALTER TABLE ONLY speedy_cluster_owner     ADD CONSTRAINT "$1" FOREIGN KEY (compute_cluster_id) REFERENCES speedy_compute_cluster(compute_cluster_id);

--
-- Make rows in speedy tables DELETE-able using ON
-- DELETE CASCADE for FOREIGN KEYS
--

ALTER TABLE ONLY speedy_test_build DROP CONSTRAINT "$1";
ALTER TABLE ONLY speedy_test_build ADD CONSTRAINT "$1" FOREIGN KEY (mpi_install_id) REFERENCES speedy_mpi_install(mpi_install_id) ON DELETE CASCADE;
ALTER TABLE ONLY speedy_test_run DROP CONSTRAINT "$1";
ALTER TABLE ONLY speedy_test_run ADD CONSTRAINT "$1" FOREIGN KEY (test_build_id)  REFERENCES speedy_test_build(test_build_id) ON DELETE CASCADE;
