#!/bin/bash

if [[ "${AGENT_VERSION}" == "AGENT_DISABLED" ]]; then
  # install latest agent because its gonna be disabled anyways
  sed -i -E "s/gem 'newrelic_rpm', '>= [0-9\.]+'/gem 'newrelic_rpm'/g" /usr/src/app/Gemfile \
    && cat /usr/src/app/Gemfile | grep newrelic_rpm
elif [[ "${AGENT_VERSION}" == branch:* ]]; then
  # local/manual testing of an unreleased branch (e.g. before it's tagged) -- bundler's
  # tag: option only resolves refs/tags/*, so a branch needs its own git option
  branch="${AGENT_VERSION#branch:}"
  sed -i -E "s/gem 'newrelic_rpm', '>= [0-9\.]+'/gem 'newrelic_rpm', git: 'https:\/\/github.com\/newrelic\/newrelic-ruby-agent.git', branch: '${branch}'/g" /usr/src/app/Gemfile \
    && cat /usr/src/app/Gemfile | grep newrelic_rpm
else
  sed -i -E "s/gem 'newrelic_rpm', '>= [0-9\.]+'/gem 'newrelic_rpm', git: 'https:\/\/github.com\/newrelic\/newrelic-ruby-agent.git', tag: '${AGENT_VERSION}'/g" /usr/src/app/Gemfile \
    && cat /usr/src/app/Gemfile | grep newrelic_rpm
fi
