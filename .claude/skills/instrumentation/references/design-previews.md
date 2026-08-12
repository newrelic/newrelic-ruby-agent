# Design preview examples

Worked examples of the §3 design-preview block, one per canonical category. Read the entry that matches the gem you're instrumenting and adapt the realistic example values (host/port/queue/model/etc.) to what the test app would actually hit. The preview format itself lives in SKILL.md §3 — this file holds only the per-category fillings.

## Datastore (Redis-style, wrapping `Redis::Client#call`)

```text
Metrics
  - Datastore/operation/Redis/get
  - Datastore/operation/Redis/set
  - Datastore/Redis/allOther
  - Datastore/instance/Redis/localhost/6379
  - Supportability/Redis/Invoked

Segments
  - name: Datastore/operation/Redis/get
    kind: Datastore
    attributes: { host: "localhost", port_path_or_id: "6379", database_name: "0", statement: "get ?" }
```

## External HTTP (wrapping `Net::HTTP#request`)

```text
Metrics
  - External/example.com/Net::HTTP/GET
  - External/example.com/all
  - External/allWeb
  - Supportability/NetHTTP/Invoked

Segments
  - name: External/example.com/Net::HTTP/GET
    kind: External
    attributes: { uri: "https://example.com/path", procedure: "GET", http.statusCode: 200 }
```

## Messaging (wrapping `Aws::SQS::Client#send_message`)

```text
Metrics
  - MessageBroker/SQS/Queue/Produce/Named/my-queue
  - Supportability/AwsSqs/Invoked

Segments
  - name: MessageBroker/SQS/Queue/Produce/Named/my-queue
    kind: MessageBroker
    attributes: { messaging.system: "aws_sqs", cloud.region: "us-east-1", cloud.account.id: "123456789012", messaging.destination.name: "my-queue" }
```

## AI-LLM (wrapping `OpenAI::Client#chat`)

```text
Metrics
  - Supportability/OpenAI/Invoked
  - Supportability/Ruby/ML/OpenAI/<gem-version>

Segments
  - name: Llm/completion/OpenAI/chat
    kind: Llm
    attributes: { llm: true }

Events
  - LlmChatCompletionSummary { id, request.model, response.model, request.max_tokens, response.number_of_messages, response.choices.finish_reason, ... }
  - LlmChatCompletionMessage (one per message in the request and response)
```
