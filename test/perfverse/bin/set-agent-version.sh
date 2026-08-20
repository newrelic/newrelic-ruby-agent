#!/bin/bash

if [[ "${AGENT_VERSION}" == "AGENT_DISABLED" ]]; then
  # install latest agent because its gonna be disabled anyways
  sed -i -E "s/gem 'newrelic_rpm', '>= [0-9\.]+'/gem 'newrelic_rpm'/g" /usr/src/app/Gemfile \
    && cat /usr/src/app/Gemfile | grep newrelic_rpm
elif [[ "${AGENT_VERSION}" == BRANCH_* ]]; then
  # For testing an unreleased branch -- bundler's tag: option only resolves refs/tags/*.
  # Uses a colon-free "BRANCH_" sentinel, not "branch:", since run_perf_tests.rb's
  # transform_agent_tags splits the outer "git_tag:VAR=val;..." format on the first colon.
  branch="${AGENT_VERSION#BRANCH_}"
  sed -i -E "s/gem 'newrelic_rpm', '>= [0-9\.]+'/gem 'newrelic_rpm', git: 'https:\/\/github.com\/newrelic\/newrelic-ruby-agent.git', branch: '${branch}'/g" /usr/src/app/Gemfile \
    && cat /usr/src/app/Gemfile | grep newrelic_rpm
else
  sed -i -E "s/gem 'newrelic_rpm', '>= [0-9\.]+'/gem 'newrelic_rpm', git: 'https:\/\/github.com\/newrelic\/newrelic-ruby-agent.git', tag: '${AGENT_VERSION}'/g" /usr/src/app/Gemfile \
    && cat /usr/src/app/Gemfile | grep newrelic_rpm
fi
