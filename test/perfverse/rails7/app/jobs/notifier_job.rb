# frozen_string_literal: true

# NotifierJob - an example of an ActiveJob class, whose 'perform' Method
# will be traced by New Relic
class NotifierJob < ApplicationJob
  queue_as :default

  def perform(*args)
    Rails.logger.debug "Received arguments: #{args}"
    relay_alert
  end

  private

  def relay_alert
    %w[d l r o w _ o l l e h].inject('') { |s, c| c + s }
  end
end
