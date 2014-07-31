These test cases cover obfuscation (more properly, masking) of literal values
from SQL statements captured by agents. SQL statements may be captured and
attached to transaction trace nodes, or to slow SQL traces.

Input queries end with the suffix `.sql`, and the expected obfuscated results
end with the suffix `.obfuscated`. Input queries may contain comment lines
explaining notes about the test case. Comment lines will precede the actual
query, and begin with a `#` symbol.

Test cases that have a `.mysql` or `.postgres` tag in the filename preceding the
`.sql` suffix are specific to either mysql or postgres obfuscation. This is
relevant because PostgreSQL uses different identifier and string quoting rules
than MySQL (most notably, double-quoted string literals are not allowed in
PostgreSQL, where double-quotes are instead used around identifiers).

The following database documentation may be helpful in understanding these test
cases:
* [MySQL String Literals](http://dev.mysql.com/doc/refman/5.5/en/string-literals.html)
* [PostgreSQL String Constants](http://www.postgresql.org/docs/8.2/static/sql-syntax-lexical.html#SQL-SYNTAX-CONSTANTS)
