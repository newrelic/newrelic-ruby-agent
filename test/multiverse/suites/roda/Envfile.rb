# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

# instrumentation_methods :chain, :prepend

# RODA_VERSIONS = [
#   [nil, 2.4],
#   ['3.19.0', 2.4]
# ]

# def gem_list(roda_version = nil)
#   <<~RB
#     gem 'roda'#{roda_version}
#     gem 'rack', '~> 2.2'
#     gem 'rack-test', '>= 0.8.0', :require => 'rack/test'
#     gem 'minitest', '~> 5.18.0'
#   RB
# end

# create_gemfiles(RODA_VERSIONS)

gemfile <<~RB
  gem 'roda'
  gem 'rack', '~> 2.2'
  gem 'rack-test', '>= 0.8.0', :require => 'rack/test'
  gem 'minitest', '~> 5.18.0'
RB
