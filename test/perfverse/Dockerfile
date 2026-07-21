ARG RUBY_VERSION=3.3.3
FROM registry.docker.com/library/ruby:$RUBY_VERSION AS base

ARG AGENT_VERSION

# Fail the build if AGENT_VERSION is not provided
RUN test -n "$AGENT_VERSION"


WORKDIR /usr/src/app
COPY rails7 .
COPY newrelic.yml ./config/
COPY certs/otlp_localhost.crt ./config/otlp_localhost.crt
COPY --chmod=0755 bin/set-agent-version.sh /set-agent-version.sh
COPY --chmod=0755 entrypoint.sh /entrypoint.sh

# Trust the otlp_receiver sidecar's self-signed cert (see test/perfverse/bin/generate-otlp-cert.sh)
# so continuous profiling's OTLP export can complete its TLS handshake against it.
ENV SSL_CERT_FILE=/usr/src/app/config/otlp_localhost.crt

# Set agent version
RUN /set-agent-version.sh

# RUN gem install date
RUN bundle install \
    && cat /usr/src/app/Gemfile.lock | grep newrelic_rpm
RUN bundle exec rake db:setup
RUN bundle exec rake assets:precompile

ENTRYPOINT ["/entrypoint.sh"]
