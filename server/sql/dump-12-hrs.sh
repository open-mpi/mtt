#
# A script to take a 12 hour dump of data from the MTT database
#
#

#
# 12 hours worth of results
#
psql -d mtt3 -U mtt -c "DROP TABLE jjh_results"
psql -d mtt3 -U mtt -c "SELECT * INTO jjh_results FROM results WHERE start_timestamp > now() - interval '1 day' - interval '12 hours' and start_timestamp < now() - interval '1 day''"
pg_dump mtt3 -t jjh_results -U mtt -a  > results.txt;

#
# 12 hours of test_run
#
#pg_dump mtt3 -t test_run -U mtt -a  > test_run.txt;
psql -d mtt3 -U mtt -c "DROP TABLE jjh_test_run"
psql -d mtt3 -U mtt -c "DROP TABLE jjh_test_run2"
psql -d mtt3 -U mtt -c "select test_run.* into jjh_test_run from jjh_results join test_run on jjh_results.phase = 3 and jjh_results.phase_id = test_run.test_run_id";
psql -d mtt3 -U mtt -c "select distinct on (test_run_id) * into jjh_test_run2 from jjh_test_run ";
pg_dump mtt3 -t jjh_test_run2 -U mtt -a  > test_run.txt;

#
# 12 hours of test_build
#
#pg_dump mtt3 -t test_build -U mtt -a  > test_build.txt;
psql -d mtt3 -U mtt -c "DROP TABLE jjh_test_build"
psql -d mtt3 -U mtt -c "DROP TABLE jjh_test_build2"
psql -d mtt3 -U mtt -c "select * into jjh_test_build from ( \
(select distinct on (test_build.test_build_id) test_build.* from test_build join jjh_test_run2 on jjh_test_run2.test_build_id = test_build.test_build_id) \
union \
(select distinct on (test_build.test_build_id) test_build.* from test_build join jjh_results on jjh_results.phase = 2 and jjh_results.phase_id = test_build.test_build_id) \
) as abc order by test_build_id";

#select * into jjh_test_build from (
#(select distinct on (test_build.test_build_id) test_build.* from test_build join jjh_test_run2 on jjh_test_run2.test_build_id = test_build.test_build_id)
#union 
#(select distinct on (test_build.test_build_id) test_build.* from test_build join jjh_results on jjh_results.phase = 2 and jjh_results.phase_id = test_build.test_build_id)
#) as abc order by test_build_id;

pg_dump mtt3 -t jjh_test_build -U mtt -a  > test_build.txt;

#
# 12 hours of mpi_install
#
#pg_dump mtt3 -t mpi_install -U mtt -a  > mpi_install.txt;
psql -d mtt3 -U mtt -c "DROP TABLE jjh_mpi_install"
psql -d mtt3 -U mtt -c "DROP TABLE jjh_mpi_install2"
psql -d mtt3 -U mtt -c "select * into jjh_mpi_install from (\
(select distinct on (mpi_install.mpi_install_id) mpi_install.* from mpi_install join jjh_test_build on jjh_test_build.mpi_install_id = mpi_install.mpi_install_id) \
union \
(select distinct on (mpi_install.mpi_install_id) mpi_install.* from mpi_install join jjh_results on jjh_results.phase = 2 and jjh_results.phase_id = mpi_install.mpi_install_id) \
) as abc order by mpi_install_id";

#select * into jjh_mpi_install from (
#(select distinct on (mpi_install.mpi_install_id) mpi_install.* from mpi_install join jjh_test_build on jjh_test_build.mpi_install_id = mpi_install.mpi_install_id)
#union 
#(select distinct on (mpi_install.mpi_install_id) mpi_install.* from mpi_install join jjh_results on jjh_results.phase = 2 and jjh_results.phase_id = mpi_install.mpi_install_id)
#) as abc order by mpi_install_id;

pg_dump mtt3 -t jjh_mpi_install -U mtt -a  > mpi_install.txt;

#
# 12 hours of latency_bandwidth
#
#pg_dump mtt3 -t latency_bandwidth -U mtt -a  > latency_bandwidth.txt;
psql -d mtt3 -U mtt -c "DROP TABLE jjh_latency_bandwidth"
psql -d mtt3 -U mtt -c "select latency_bandwidth.* into jjh_latency_bandwidth from jjh_results join test_run on jjh_results.phase = 3 and jjh_results.phase_id = test_run.test_run_id join latency_bandwidth on jjh_results.latency_bandwidth_id = latency_bandwidth.latency_bandwidth_id";
pg_dump mtt3 -t jjh_latency_bandwidth -U mtt -a  > latency_bandwidth.txt;


#
# All of the other tables
#
pg_dump mtt3 -t compute_cluster -U mtt -a > compute_cluster.txt;
pg_dump mtt3 -t submit -U mtt -a > submit.txt;
pg_dump mtt3 -t mpi_get -U mtt -a  > mpi_get.txt;
pg_dump mtt3 -t compiler -U mtt -a  > compiler.txt;

#pg_dump mtt3 -t alerts -U mtt -a  > alerts.txt;
pg_dump mtt3 -t users -U mtt -a  > users.txt;
pg_dump mtt3 -t failure -U mtt -a  > failure.txt;
pg_dump mtt3 -t cluster_owner -U mtt -a  > cluster_owner.txt;


psql -d mtt3 -U mtt -c "DROP TABLE jjh_results"

psql -d mtt3 -U mtt -c "DROP TABLE jjh_test_run"
psql -d mtt3 -U mtt -c "DROP TABLE jjh_test_run2"

psql -d mtt3 -U mtt -c "DROP TABLE jjh_test_build"

psql -d mtt3 -U mtt -c "DROP TABLE jjh_mpi_install"

psql -d mtt3 -U mtt -c "DROP TABLE jjh_latency_bandwidth"
