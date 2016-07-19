--
-- View for Intel(R) Cluster Checker
--
DROP VIEW IF EXISTS clck_1;
CREATE OR REPLACE VIEW clck_1 AS
    SELECT test_run.duration,
        0 AS encoding,
        test_run.exit_value AS exit_status,
        submit.hostname,
        ''::text AS node_names,
        0 AS num_nodes,
        test_run.test_run_command_id::character varying AS optionid,
        test_run.test_run_id AS rowid,
        test_names.test_name AS provider,
        test_run.result_stdout AS stdout,
        test_run.result_stderr AS stderr,
        date_part('epoch'::text, test_run.start_timestamp)::integer AS "timestamp",
        submit.local_username AS username,
        1 AS version
    FROM test_run
        JOIN submit ON test_run.submit_id = submit.submit_id
        JOIN test_names ON test_run.test_name_id = test_names.test_name_id;
