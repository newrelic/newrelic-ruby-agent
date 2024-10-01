# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'opensearch/instrumentation'
require_relative 'opensearch/chain'
require_relative 'opensearch/prepend'

DependencyDetection.defer do
  named :opensearch

  depends_on do
    defined?(OpenSearch)
  end

  executes do
    if use_prepend?
      prepend_instrument OpenSearch::Transport::Client, NewRelic::Agent::Instrumentation::OpenSearch::Prepend
    else
      chain_instrument NewRelic::Agent::Instrumentation::OpenSearch::Chain
    end
  end
end
