-- Serial number used for tnames
DROP SEQUENCE ttable_id;
CREATE SEQUENCE ttable_id CYCLE;

DROP TABLE ttable CASCADE;
CREATE TABLE ttable (
    tname character varying(256) UNIQUE,
    accessed timestamp without time zone DEFAULT now()
);
