require "newrelic_prepender/version"

module NewRelic
  module Prepender
  end
end

require 'action_controller'

::ActionController::Base.prepend NewRelic::Prepender

if ::Rails::VERSION::MAJOR.to_i == 5
  ::ActionController::API.prepend NewRelic::Prepender
end

require 'action_view'

::ActionView::Base.prepend NewRelic::Prepender
::ActionView::Template.prepend NewRelic::Prepender
::ActionView::Renderer.prepend NewRelic::Prepender

if ::Rails::VERSION::MAJOR.to_i == 5
  require 'action_cable/engine'

  ::ActionCable::Engine.prepend NewRelic::Prepender
  ::ActionCable::RemoteConnections.prepend NewRelic::Prepender

  require 'active_job'

  ::ActiveJob::Base.prepend NewRelic::Prepender
end

require 'active_record'

::ActiveRecord::Base.prepend NewRelic::Prepender
::ActiveRecord::Relation.prepend NewRelic::Prepender
