# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/helper'

# This class encapsulates an error that was noticed by New Relic in a managed app.
class NewRelic::NoticedError
  extend NewRelic::CollectionHelper
  attr_accessor :path, :timestamp, :params, :message,
                :exception_class_name, :exception_class_constant
  attr_reader :exception_id

  STRIPPED_EXCEPTION_REPLACEMENT_MESSAGE = "Message removed by New Relic 'strip_exception_messages' setting"

  def initialize(path, data, exception, timestamp = Time.now)
    @exception_id = exception.object_id
    @path = path
    @params = NewRelic::NoticedError.normalize_params(data)

    @exception_class_name = exception.is_a?(Exception) ? exception.class.name : 'Error'
    @exception_class_constant = exception.class

    if exception.respond_to?('original_exception')
      @message = exception.original_exception.message.to_s
    else
      @message = (exception || '<no message>').to_s
    end

    unless @message.is_a?(String)
      # In pre-1.9.3, Exception.new({}).to_s.class != String
      # That is, Exception#to_s may not return a String instance if one wasn't
      # passed in upon creation of the Exception. So, try to generate a useful
      # String representation of the exception message, falling back to failsafe
      @message = String(@message.inspect) rescue '<unknown message type>'
    end

    # clamp long messages to 4k so that we don't send a lot of
    # overhead across the wire
    @message = @message[0..4095] if @message.length > 4096

    # replace error message if enabled
    if NewRelic::Agent.config[:'strip_exception_messages.enabled'] && !whitelisted?
      @message = STRIPPED_EXCEPTION_REPLACEMENT_MESSAGE
    end

    @timestamp = timestamp
  end

  # @exception_class has been deprecated in favor of the more descriptive
  # @exception_class_name.
  # @deprecated
  def exception_class
    exception_class_name
  end

  def whitelisted?
    NewRelic::Agent.config.stripped_exceptions_whitelist.find do |klass|
      exception_class_constant <= klass
    end
  end

  def ==(other)
    if other.respond_to?(:exception_id)
      exception_id == other.exception_id
    else
      false
    end
  end

  include NewRelic::Coerce

  def to_collector_array(encoder=nil)
    [ NewRelic::Helper.time_to_millis(timestamp),
      string(path),
      string(message),
      string(exception_class_name),
      params ]
  end
end
