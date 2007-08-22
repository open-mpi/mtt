--
-- The tables here support the execution of the reporter
--

--
-- Permalinks
--
DROP TABLE permalinks CASCADE;
CREATE TABLE permalinks (
    permalink_id    serial PRIMARY KEY,
    permalink       text NOT NULL,
    created         timestamp without time zone DEFAULT now(),

    UNIQUE (
        permalink_id,
        permalink
    )
);
