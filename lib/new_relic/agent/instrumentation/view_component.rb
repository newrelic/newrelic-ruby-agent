# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'view_component/instrumentation'
require_relative 'view_component/chain'
require_relative 'view_component/prepend'

DependencyDetection.defer do
  named :view_component

  depends_on do
    defined?(ViewComponent) &&
      ViewComponent::Base.method_defined?(:render_in)
  end

  executes do
    if use_prepend?
      prepend_instrument ViewComponent::Base, NewRelic::Agent::Instrumentation::ViewComponent::Prepend
    else
      chain_instrument NewRelic::Agent::Instrumentation::ViewComponent::Chain
    end
  end
end
