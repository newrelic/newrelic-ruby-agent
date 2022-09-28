# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'elasticsearch/instrumentation'
require_relative 'elasticsearch/chain'
require_relative 'elasticsearch/prepend'

DependencyDetection.defer do
  named :elasticsearch

  depends_on do
    defined?(::Elasticsearch) || defined?(::Elastic)
  end

  executes do
    ::NewRelic::Agent.logger.info('Installing elasticsearch instrumentation')

    to_instrument = if defined?(::Elastic)
      ::Elastic::Transport::Client
    else
      ::Elasticsearch::Transport::Client
    end

    if use_prepend?
      prepend_instrument to_instrument, NewRelic::Agent::Instrumentation::Elasticsearch::Prepend
    else
      chain_instrument NewRelic::Agent::Instrumentation::Elasticsearch
    end
  end
end
