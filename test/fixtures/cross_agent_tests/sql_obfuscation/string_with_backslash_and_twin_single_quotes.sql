# If backslashes are being ignored in single-quoted strings
# (standard_conforming_strings=on in PostgreSQL, or NO_BACKSLASH_ESCAPES is on
# in MySQL), then this is valid SQL.
SELECT * FROM table WHERE col='foo\''bar'