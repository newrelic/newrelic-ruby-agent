# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require "newrelic_prepender/version"

module NewRelic
  module Prepender
    def self.do_prepend base
      if RUBY_VERSION >= '2.1.0'
        base.prepend NewRelic::Prepender
      else
        base.__send__ :prepend, NewRelic::Prepender
      end
    end
  end
end

require 'action_controller'

NewRelic::Prepender.do_prepend ::ActionController::Base

if ::Rails::VERSION::MAJOR.to_i == 5
  NewRelic::Prepender.do_prepend ::ActionController::API
end

require 'action_view'

NewRelic::Prepender.do_prepend ::ActionView::Base
NewRelic::Prepender.do_prepend ::ActionView::Template
NewRelic::Prepender.do_prepend ::ActionView::Renderer

if ::Rails::VERSION::MAJOR.to_i == 5
  require 'action_cable/engine'

  NewRelic::Prepender.do_prepend ::ActionCable::Engine
  NewRelic::Prepender.do_prepend ::ActionCable::RemoteConnections

  require 'active_job'

  NewRelic::Prepender.do_prepend ::ActiveJob::Base
end

require 'active_record'

NewRelic::Prepender.do_prepend ::ActiveRecord::Base
NewRelic::Prepender.do_prepend ::ActiveRecord::Relation
