# Cross Agent Tests

| Test Files    | Description   |
| ------------- |-------------|
| [rum_loader_insertion_location](rum_loader_insertion_location) | Describe where the RUM loader (formerly known as header) should be inserted. |
| [rum_footer_insertion_location](rum_footer_insertion_location) | Describe where the RUM footer should be inserted. |
| [rules.json](rules.json) | Describe how url/metric/txn-name rules should be applied. |
| [rum_client_config.json](rum_client_config.json) | These tests dictate the format and contents of the browser monitoring client configuration.  For more information see: [SPEC](https://newrelic.atlassian.net/wiki/display/eng/JavaScript+Agent+Auto-Instrumentation) |
| [rum_cookie.json](rum_cookie.json)      | These tests indicate the format requirements of a valid RUM cookie. |
| [sql_parsing.json](sql_parsing.json) | These tests show how an SQL string should be parsed for the operation and table name. |
| [url_clean.json](url_clean.json) | These tests show how URLs should be cleaned before putting them into a trace segment's parameter hash (under the key 'uri'). |
| [url_domain_extraction.json](url_domain_extraction.json) | These tests show how the domain of a URL should be extracted (for the purpose of creating external metrics). |
