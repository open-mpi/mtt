-- 1) Rename the old column to ...column_dropped... to get it out of the way of
-- step 2.

ALTER TABLE some_table RENAME some_column TO some_column_dropped;

-- 2) Create a new column with the wanted type and appropriate
-- constraints. Only not null is supported at the moment.

ALTER TABLE some_table ADD some_column new_type;

-- 3) Alter in the corrected default.

ALTER TABLE some_table ALTER COLUMN some_column SET DEFAULT 'new_default';

-- 4) Copy data from old column to new column.

UPDATE some_table SET some_column=some_column_dropped;

-- 5) Drop the old (original) column that had earlier been renamed.

ALTER TABLE some_table DROP COLUMN some_column_dropped;
