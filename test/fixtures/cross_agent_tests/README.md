# Cross Agent Tests

### Data Policy

None of these tests should contain customer data such as SQL strings.
Please be careful when adding new tests from real world failures.

### Tests

| Test Files    | Description   |
| ------------- |-------------|
| [rum_loader_insertion_location](rum_loader_insertion_location) | Describe where the RUM loader (formerly known as header) should be inserted. |
| [rum_footer_insertion_location](rum_footer_insertion_location) | Describe where the RUM footer (aka "client config") should be inserted.  These tests do not apply to agents which insert the footer directly after the loader. |
| [rules.json](rules.json) | Describe how url/metric/txn-name rules should be applied. |
| [rum_client_config.json](rum_client_config.json) | These tests dictate the format and contents of the browser monitoring client configuration.  For more information see: [SPEC](https://newrelic.atlassian.net/wiki/display/eng/JavaScript+Agent+Auto-Instrumentation) |
| [rum_cookie.json](rum_cookie.json)      | These tests indicate the format requirements of a valid RUM cookie. |
| [sql_parsing.json](sql_parsing.json) | These tests show how an SQL string should be parsed for the operation and table name. |
| [url_clean.json](url_clean.json) | These tests show how URLs should be cleaned before putting them into a trace segment's parameter hash (under the key 'uri'). |
| [url_domain_extraction.json](url_domain_extraction.json) | These tests show how the domain of a URL should be extracted (for the purpose of creating external metrics). |
| [postgres_explain_obfuscation](postgres_explain_obfuscation) | These tests show how plain-text explain plan output from PostgreSQL should be obfuscated when SQL obfuscation is enabled. |
| [sql_obfuscation](sql_obfuscation) | Describe how agents should obfuscate SQL queries before transmission to the collector. |
| [attribute_configuration](attribute_configuration.json) | These tests show how agents should respond to the various attribute configuration settings.  For more information see: [Attributes SPEC](https://newrelic.atlassian.net/wiki/display/eng/Agent+Attributes) |
| [cat_map](cat_map.json) | These tests cover the new Dirac attributes that are added for the CAT Map project. See the [CAT Map Spec](https://newrelic.jiveon.com/docs/DOC-1798) and the section below for details.|
| [labels](labels.json) | These tests cover the Labels for Language Agents project. See the [Labels for Language Agents Spec](https://newrelic.atlassian.net/wiki/display/eng/Labels+for+Language+Agents+-+draft+spec) for details.|
| [proc_cpuinfo](proc_cpuinfo) | These test correct processing of `/proc/cpuinfo` output on Linux hosts. |

### CAT Map test details

The CAT map test cases in `cat_map.json` are meant to be used to verify the
attributes that agents collect and attach to analytics transaction events for
the CAT map project.

Each test case should correspond to a simulated transaction in the agent under
test. Here's what the various fields in each test case mean:

| Name | Meaning |
| ---- | ------- |
| `name` | A human-meaningful name for the test case. |
| `appName` | The name of the New Relic application for the simulated transaction. |
| `transactionName` | The final name of the simulated transaction. |
| `transactionGuid` | The GUID of the simulated transaction. |
| `inboundPayload` | The (non-serialized) contents of the `X-NewRelic-Transaction` HTTP request header on the simulated transaction. Note that this value should be serialized to JSON, obfuscated using the CAT obfuscation algorithm, and Base64-encoded before being used in the header value. Note also that the `X-NewRelic-ID` header should be set on the simulated transaction, though its value is not specified in these tests. |
| `expectedIntrinsicFields` | A set of key-value pairs that are expected to be present in the analytics event generated for the simulated transaction. These fields should be present in the first hash of the analytic event payload (built-in agent-supplied fields). |
| `nonExpectedIntrinsicFields` | An array of attribute names that should *not* be present in the analytics event generated for the simulated transaction. |
| `outboundRequests` | An array of objects representing outbound requests that should be made in the context of the simulated transaction. See the table below for details. Only present if the test case involves making outgoing requests from the simulated transaction. |

Here's what the fields of each entry in the `outboundRequests` array mean:

| Name | Meaning |
| ---- | ------- |
| `outboundTxnName` | The name of the simulated transaction at the time this outbound request is made. Your test driver should set the transaction name to this value prior to simulating the outbound request. |
| `expectedOutboundPayload` | The expected (un-obfuscated) content of the outbound `X-NewRelic-Transaction` request header for this request. |
