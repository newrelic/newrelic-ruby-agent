# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# Represents url mapping rules stored on the server.  These rules should be applied
# to URLs which are not normalized into controller class/action by Rails routes.
# Insantiated strictly by Marshal.
class NewRelic::UrlRule
  attr_reader :match_expression, :replacement, :eval_order, :terminate_chain

  def apply url
    return nil
  end

  class RuleSet

  end
end
