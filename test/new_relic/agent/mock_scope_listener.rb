# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.


class NewRelic::Agent::MockScopeListener

  attr_reader :scopes

  def initialize
    @scopes = []
  end

  def notice_first_scope_push(time)
  end

  def notice_push_scope(time)
  end

  def notice_pop_scope(scope, time)
    @scopes << scope
  end

  def notice_scope_empty(time)
  end

  def enabled?
    true
  end
end
