# frozen_string_literal: true

# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require "newrelic_prepender/version"

module NewRelic
  module Prepender
    def self.do_prepend *bases
      bases.each {|b| b.__send__ :prepend, self}
    end
  end
end

require 'action_controller'

NewRelic::Prepender.do_prepend ::ActionController::Base

if ::Rails::VERSION::MAJOR.to_i == 5
  NewRelic::Prepender.do_prepend ::ActionController::API
end

require 'action_view'

NewRelic::Prepender.do_prepend ::ActionView::Base,
                               ::ActionView::Template,
                               ::ActionView::Renderer

if ::Rails::VERSION::MAJOR.to_i == 5
  require 'action_cable/engine'

  NewRelic::Prepender.do_prepend ::ActionCable::Engine,
                                 ::ActionCable::RemoteConnections

  require 'active_job'

  NewRelic::Prepender.do_prepend ::ActiveJob::Base
end

require 'active_record'

NewRelic::Prepender.do_prepend ::ActiveRecord::Base,
                               ::ActiveRecord::Relation
