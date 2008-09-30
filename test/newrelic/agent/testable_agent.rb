
require 'newrelic/agent'


RAILS_ROOT='.' if !defined? RAILS_ROOT


class String
  def titleize
    self
  end
end

