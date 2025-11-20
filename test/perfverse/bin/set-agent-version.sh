#!/bin/bash

if [[ "${AGENT_VERSION}" == "AGENT_DISABLED" ]]; then
  # install latest agent because its gonna be disabled anyways
  sed -i -E "s/gem 'newrelic_rpm', '>= [0-9\.]+'/gem 'newrelic_rpm'/g" /usr/src/app/Gemfile \
    && cat /usr/src/app/Gemfile | grep newrelic_rpm
else
  sed -i -E "s/gem 'newrelic_rpm', '>= [0-9\.]+'/gem 'newrelic_rpm', git: 'https:\/\/github.com\/newrelic\/newrelic-ruby-agent.git', tag: '${AGENT_VERSION}'/g" /usr/src/app/Gemfile \
    && cat /usr/src/app/Gemfile | grep newrelic_rpm
fi
