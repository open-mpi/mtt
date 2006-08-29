--
-- Open MPI Test Results Tables
--
-- Usage: $ cat schemas.sql | psql -d <dbname> -U <dbusername>
--

CREATE TABLE once (
    run_index integer DEFAULT 1,
    mtt_version_major integer,
    mtt_version_minor integer,
    platform_hardware character varying(256) DEFAULT 'N/A'::character varying,
    platform_type character varying(256) DEFAULT 'N/A'::character varying,
    platform_id character varying(256) DEFAULT 'N/A'::character varying,
    os_name character varying(256) DEFAULT 'N/A'::character varying,
    os_version character varying(256) DEFAULT 'N/A'::character varying,
    hostname character varying(256) DEFAULT ''::character varying,
    mpi_name character varying(256) DEFAULT ''::character varying,
    mpi_version character varying(256) DEFAULT ''::character varying,
    submitting_unix_user character varying(256) DEFAULT ''::character varying,
    submitting_http_user character varying(256) DEFAULT ''::character varying,
    unique (run_index,hostname,os_name,os_version,platform_hardware,platform_type,mpi_name,mpi_version)
);

-- All three phases require these fields
CREATE TABLE general_a (
    run_index integer,
    test_result smallint,
    timed_out boolean,
    mpi_get_section_name character varying(256) DEFAULT 'N/A'::character varying,
    mpi_install_section_name character varying(256) DEFAULT 'N/A'::character varying,
    mpi_details character varying(256) DEFAULT 'N/A'::character varying,
    merge_stdout_stderr integer DEFAULT 0,
    environment text DEFAULT 'N/A'::text,
    vpath_mode character varying(256) DEFAULT 'N/A'::character varying,
    result_message character varying(256),
    stderr text DEFAULT 'N/A'::text,
    stdout text DEFAULT 'N/A'::text,
    start_run_timestamp timestamp without time zone,
    start_test_timestamp timestamp without time zone,
    submit_test_timestamp timestamp without time zone,
    test_duration_interval interval
);

-- MPI Install and Test Build phases require these fields
CREATE TABLE general_b (
    compiler_name character varying(256) DEFAULT 'N/A'::character varying,
    compiler_version character varying(256) DEFAULT 'N/A'::character varying
);

CREATE TABLE installs (
    configure_arguments character varying(256) DEFAULT 'N/A'::character varying
)
INHERITS (general_a,general_b);

CREATE TABLE builds (
    test_build_section_name character varying(256) DEFAULT 'N/A'::character varying
) 
INHERITS (general_a,general_b);

CREATE TABLE runs (
    test_build_section_name character varying(256) DEFAULT 'N/A'::character varying,
    test_command character varying(256) DEFAULT 'N/A'::character varying,
    test_name character varying(256),
    test_np integer,
    test_run_section_name character varying(256) DEFAULT 'N/A'::character varying
)
INHERITS (general_a);
