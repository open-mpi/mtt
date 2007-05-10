--
-- Script to DELETE unreferenced rows (which were probably left behind
-- do to defects in prune_db.pl).  This script is necessary because there
-- is no FOREIGN KEY constraint preserving referential integrity between
-- the phase TABLEs and the results TABLE.
--

-- Archive tables
SELECT phase_id INTO TEMPORARY TABLE phase_id3 FROM results WHERE phase = 3;
SELECT phase_id INTO TEMPORARY TABLE phase_id2 FROM results WHERE phase = 2;
SELECT phase_id INTO TEMPORARY TABLE phase_id1 FROM results WHERE phase = 1;
DELETE FROM test_run    WHERE test_run_id    NOT IN (SELECT * FROM phase_id3);
DELETE FROM test_build  WHERE test_build_id  NOT IN (SELECT * FROM phase_id2);
DELETE FROM mpi_install WHERE mpi_install_id NOT IN (SELECT * FROM phase_id1);
VACUUM ANALYZE test_run;
VACUUM ANALYZE test_build;
VACUUM ANALYZE mpi_install;

-- Speedy tables
SELECT phase_id INTO TEMPORARY TABLE speedy_phase_id3 FROM speedy_results WHERE phase = 3;
SELECT phase_id INTO TEMPORARY TABLE speedy_phase_id2 FROM speedy_results WHERE phase = 2;
SELECT phase_id INTO TEMPORARY TABLE speedy_phase_id1 FROM speedy_results WHERE phase = 1;
DELETE FROM speedy_test_run    WHERE test_run_id    NOT IN (SELECT * FROM speedy_phase_id3);
DELETE FROM speedy_test_build  WHERE test_build_id  NOT IN (SELECT * FROM speedy_phase_id2);
DELETE FROM speedy_mpi_install WHERE mpi_install_id NOT IN (SELECT * FROM speedy_phase_id1);
VACUUM ANALYZE speedy_test_run;
VACUUM ANALYZE speedy_test_build;
VACUUM ANALYZE speedy_mpi_install;
