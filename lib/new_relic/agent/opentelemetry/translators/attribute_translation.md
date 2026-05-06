# Attribute Translation

- [Attribute Mappings](#attribute-mappings)
- [Attribute Translators](#attribute-translators)
- [Attribute translation in the span lifecycle](#attribute-translation-in-the-span-lifecycle)
- [Adding a new attribute category for translation](#adding-a-new-attribute-category-for-translation)
- [Potential gotchas](#potential-gotchas)

OpenTelemetry semantic conventions differ from the attributes New Relic sends
for various types of telemetry. One of the hybrid agent's responsibilities
is to translate some attributes from the OTel semantic conventions into
New Relic standards.

We take care of this using attribute translators and attribute mappings.

## Attribute Mappings

The `NewRelic::Agent::OpenTelemetry::AttributeMappings` class includes constants
that break down how a given New Relic attribute should be assigned based on
possible OpenTelemetry semantic conventions.

The class has multiple constants, each one based thematically on a certain
semantic convention.

Here is an example of the structure of the mappings:

```ruby
EXAMPLE_MAPPINGS = {
  'nr_key' => {
    otel_keys: ['semconv_a', 'semconv_b'],
    category: :intrinsics,
    segment_field: :api_argument,
    destinations: AttributeFilter::DST_TRANSACTION_TRACER
  }
}
```

To break this down:
* `EXAMPLE_MAPPINGS`: the name of the constant that holds the mappings for your
new category
* `'nr_key'`: The New Relic attribute we're translating OpenTelemetry data into
* `:otel_keys`: an array of string keys from OpenTelemetry semantic
conventions across different versions that map to the New Relic key
* `:category`: The type of New Relic attribute bucket this falls into. Options
are `:intrinsic`, `:agent`, or `:instance_variable`. If `:agent` is selected,
then a `:destinations` key must also be present. If `:instance_variable` is
used, the `nr_key` should be the name of the instance variable the otel keys
should map to. Be cautious with `:intrinsic` categories. The attributes may be
deleted if they're applied to a segment, but should work if they're applied to
a transaction.
* `:segment_field`: An argument that used in a segment API to apply a value. For
example, the `NewRelic::Agent::Tracer.start_external_request` segment API
expects an argument for `procedure`. If you want the `:otel_keys` to translate
into this argument, you would set the `:segment_field` as `:procedure`.
* `:destinations`: These are the `AttributeFilter` class destinations that
direct the agent to send agent attributes to. There is a `DEFAULT_DESTINATIONS`
constant at the beginning of the `AttributeMappings` class that has some
standard destinations for most converted OTel attributes.

## Attribute Translators

The attribute translators work in two steps.

First, the `NewRelic::Agent::OpenTelemetry::AttributeTranslator.translate`
method is called when a span is created to determine the appropriate translator
to dispatch the translation to.

The appropriate translator can be determined based on a span's:
* instrumentation scope
* discriminating attributes
* span kind

If no translator can be identified, a `GenericTranslator` will be used instead
and all provided attributes will be assigned as custom attributes.

From there, the identified translator class has its own `translate` method that
leverages its corresponding `AttributeMappings` constant (ex.
`HTTP_CLIENT_MAPPINGS` for the `HttpClientTranslator`) to distribute the
attributes into the correct New Relic categories. If, after translating the
attributes, there are still some attributes without a corresponding New Relic
key, then those attributes will be assigned as custom attributes on the span.

You may notice the attribute translator classes are sparse. This is because the
shared logic of attribute translation lives in the `BaseTranslator` class.

If custom parsing is required to create or derive a New Relic attribute from a
OpenTelemetry attribute, then a custom method can be defined in the translator
class to perform this operation. This is required in the case of crafting a URI
for the `start_external_request_segment` API. On these occasions, the custom
methods should be called within the `extra_operations` method so that they can
be invoked in the shared `translate` method.

The return value is a hash that looks something like this:

```ruby
  {
    intrinsic: {"host" => "potatoes.com", "port" => 443},
    agent: {
      "request.uri" => {value: "/sustainable-spuds", destinations: 23},
      "request.headers.host" => {value: "potatoes.com", destinations: 23},
      "request.headers.userAgent" => {
        value: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)
        AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0
        Safari/537.36",
        destinations: 23
      },
      "request.method" => {value: "GET", destinations: 23}
    },
    custom: {
      "url.scheme" => "http", "url.query" => "query=true"
    },
    for_segment_api: {name: "Controller/OTelClient/GET /sustainable-spuds"},
    instance_variable: {"http_status_code" => 200},
    translator: NewRelic::Agent::OpenTelemetry::HttpServerTranslator
  }
```

Notice that the return value also includes the translator that performed the
initial translation. This means that whenever the OTel attribute APIs are called
(`Span#set_attribute`, `Span#add_attributes`), the translator will be used to
divide up the provided attributes.

## Attribute translation in the span lifecycle

* `Tracer#start_span` method is called
* `AttributeTranslator.translate` is called, providing the instrumentation
scope, attributes, span name and span kind to help with indentifying the
translator and also translating the provided attributes
* When the `Translator` is identified, its translate method is called to
create a hash with the attributes translated into the correct categories
* A New Relic transaction/segment is created using the translated attributes to
populate their corresponding arguments in the APIs
* Before the `start_span` completes, intrinsic, agent, and instance variable
attributes are applied to the span using `span.apply_translated_attributes`
* In addition, the `translator` is assigned as an instance variable on the span
* `Tracer#start_span` completes
* If `Span#add_attributes` or `Span#set_attribute` is called during the life of
the span, those APIs will leverage the assigned translator to dispatch the
attributes to their correct New Relic categories
* The `Span#finish` is called, and the New Relic intrinsic, agent, and custom
attributes are recorded

## Adding a new attribute category for translation

* Create a new class in the `lib/new_relic/agent/opentelemetry/translators`
directory that's named after the category you'd like to translate
* Update the `AttributeMappings` class to include a new constant with the
mappings for your new category
* Update the `AttributeTranslator::TRANSLATOR_REGISTRY` constant with the
conditions that signal your new translator should be used. The class of your
new translator should be the value of any keys that could be used to identify
the new translator should be used

## Potential Gotchas

Some segments, like external request segments, overwrite the intrinsics array
when the span event primitive creates the final payload. this means that any
intrinsic attributes we try to manually add will be removed. This was a problem
with the `http_status_code` attribute and is why we assign this attribute by
instance variable instead of directly as an intrinsic.

Intrinsic attribute assignment has worked fine with transactions, so use this
approach with caution and make sure it is fully tested.