-- For "new" failure reporting
-- Rows in this table are currently manually INSERTED
DROP TABLE failure;
CREATE TABLE failure (
    failure_id serial PRIMARY KEY,

    _params character varying(32)[] DEFAULT '{}',
    _values text[] DEFAULT '{}',

    --> first occurrence
    first_occurrence timestamp without time zone DEFAULT now(),
    --> most recent occurrence
    last_occurrence timestamp without time zone DEFAULT now(),  

    UNIQUE (
        _params,
        _values
    )
);
