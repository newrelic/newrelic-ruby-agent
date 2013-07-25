# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class ApplicationController < ActionController::Base
  helper :all # include all helpers, all the time
  layout 'application'

  before_filter :check_error, :check_delay

  def check_error
    raise params[:error] if params[:error]
  end

  def check_delay
    sleep params[:delay].to_i if params[:delay]
  end

  protect_from_forgery # :secret => '59f202b6d73975dbcca68b23c3b3d543'
end
