# PostgreSQL supports an alternate string quoting mode where backslash escape
# sequences are interpreted.
# See: http://www.postgresql.org/docs/9.3/static/sql-syntax-lexical.html#SQL-SYNTAX-STRINGS-ESCAPE
SELECT "col1", "col2" from "table" WHERE "col3"=E'foo\'bar\\baz' AND country=e'foo\'bar\\baz'