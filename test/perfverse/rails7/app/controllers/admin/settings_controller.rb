# frozen_string_literal: true

# SettingsController - an example of a controller in a subdirectory
class Admin::SettingsController < AdminController
  skip_before_action :verify_authenticity_token

  SETTINGS = %w[on off open closed forward reverse parallel linear timed elapsed].freeze

  # GET /admin/settings
  def index
    html = '<h1>Secret Admin Settings</h1><ul>'
    SETTINGS.each { |setting| html += "<li>#{setting}</li>" }
    html += '</ul>'

    render inline: html
  end
end
