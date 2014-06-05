# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.


class NewRelic::Agent::MockScopeListener

  attr_reader :scopes

  def initialize
    @scopes = []
  end

  def notice_push_frame(state, time)
  end

  def notice_pop_frame(state, scope, time)
    @scopes << scope
  end

  def on_finishing_transaction(time)
  end

  def enabled?
    true
  end
end
