# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require "newrelic_prepender/version"

module NewRelic; module Prepender; end; end

require 'action_controller'

::ActionController::Base.__send__ :prepend, NewRelic::Prepender

if ::Rails::VERSION::MAJOR.to_i == 5
  ::ActionController::API.__send__ :prepend, NewRelic::Prepender
end

require 'action_view'

::ActionView::Base.__send__ :prepend, NewRelic::Prepender
::ActionView::Template.__send__ :prepend, NewRelic::Prepender
::ActionView::Renderer.__send__ :prepend, NewRelic::Prepender

if ::Rails::VERSION::MAJOR.to_i == 5
  require 'action_cable/engine'

  ::ActionCable::Engine.__send__ :prepend, NewRelic::Prepender
  ::ActionCable::RemoteConnections.__send__ :prepend, NewRelic::Prepender

  require 'active_job'

  ::ActiveJob::Base.__send__ :prepend, NewRelic::Prepender
end

require 'active_record'

::ActiveRecord::Base.__send__ :prepend, NewRelic::Prepender
::ActiveRecord::Relation.__send__ :prepend, NewRelic::Prepender
