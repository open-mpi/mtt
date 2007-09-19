-- 1) Rename the old column to ...column_dropped... to get it out of the way of
-- step 2.

ALTER TABLE mpi_install RENAME configure_arguments TO configure_arguments_dropped;

-- 2) Create a new column with the wanted type and appropriate
-- constraints. Only not null is supported at the moment.

ALTER TABLE mpi_install ADD configure_arguments text;

-- 3) Alter in the corrected default.

ALTER TABLE mpi_install ALTER COLUMN configure_arguments SET DEFAULT '';

-- 4) Copy data from old column to new column.

UPDATE mpi_install SET configure_arguments=configure_arguments_dropped;

-- 5) Drop the old (original) column that had earlier been renamed.

ALTER TABLE mpi_install DROP COLUMN configure_arguments_dropped;
