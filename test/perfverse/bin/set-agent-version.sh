#!/bin/bash

if [[ "${AGENT_VERSION}" == "AGENT_DISABLED" ]]; then
  # install latest agent because its gonna be disabled anyways
  sed -i -E "s/gem 'newrelic_rpm', '>= [0-9\.]+'/gem 'newrelic_rpm'/g" /usr/src/app/Gemfile \
    && cat /usr/src/app/Gemfile | grep newrelic_rpm
elif [[ "${AGENT_VERSION}" == BRANCH_* ]]; then
  # local/manual testing of an unreleased branch (e.g. before it's tagged) -- bundler's
  # tag: option only resolves refs/tags/*, so a branch needs its own git option. Uses a
  # colon-free "BRANCH_" sentinel (like AGENT_DISABLED above), NOT "branch:", because the
  # outer "git_tag:ENV_VAR_1=one;ENV_VAR_2=two" format (see run_perf_tests.rb's
  # transform_agent_tags) splits on the *first* colon -- a "branch:" prefix would collide
  # with that and get mis-split.
  branch="${AGENT_VERSION#BRANCH_}"
  sed -i -E "s/gem 'newrelic_rpm', '>= [0-9\.]+'/gem 'newrelic_rpm', git: 'https:\/\/github.com\/newrelic\/newrelic-ruby-agent.git', branch: '${branch}'/g" /usr/src/app/Gemfile \
    && cat /usr/src/app/Gemfile | grep newrelic_rpm
else
  sed -i -E "s/gem 'newrelic_rpm', '>= [0-9\.]+'/gem 'newrelic_rpm', git: 'https:\/\/github.com\/newrelic\/newrelic-ruby-agent.git', tag: '${AGENT_VERSION}'/g" /usr/src/app/Gemfile \
    && cat /usr/src/app/Gemfile | grep newrelic_rpm
fi
