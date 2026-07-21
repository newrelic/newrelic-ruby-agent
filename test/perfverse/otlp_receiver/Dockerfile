# Build from the repo root so this can pull the already-generated proto Ruby files straight out
# of lib/, e.g.:
#   docker build -f test/perfverse/otlp_receiver/Dockerfile -t otlp_receiver:local .
ARG RUBY_VERSION=3.3.3
FROM registry.docker.com/library/ruby:$RUBY_VERSION

WORKDIR /app

RUN gem install google-protobuf webrick

COPY lib/new_relic/agent/continuous_profiling/proto ./proto
COPY test/perfverse/certs/otlp_localhost.crt test/perfverse/certs/otlp_localhost.key ./
COPY test/perfverse/otlp_receiver/otlp_receiver.rb .

CMD ["ruby", "otlp_receiver.rb"]
