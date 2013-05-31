# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/helper'

# This class encapsulates an error that was noticed by New Relic in a managed app.
class NewRelic::NoticedError
  extend NewRelic::CollectionHelper
  attr_accessor :path, :timestamp, :params, :exception_class, :message
  attr_reader :exception_id

  def initialize(path, data, exception, timestamp = Time.now)
    @exception_id = exception.object_id
    @path = path
    @params = NewRelic::NoticedError.normalize_params(data)

    @exception_class = exception.class

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
    if NewRelic::Agent.config[:strip_exception_messages]
      @message = "Message removed by New Relic 'strip_exception_messages' setting" unless whitelisted?
    end

    @timestamp = timestamp
  end

  def whitelisted?
    @whitelist ||= whitelisted_exception_classes
    @whitelist.compact.find { |klass| exception_class <= klass }
  end

  def whitelisted_exception_classes
    whitelist = NewRelic::Agent.config[:strip_exception_messages_whitelist]
    return unless whitelist

    whitelist = whitelist.split(/\s*,\s*/).map do |class_name|
      constantize(class_name)
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

  def exception_name_for_collector
    if exception_class < Exception
      exception_class.name
    else
      'Error'
    end
  end

  def to_collector_array(encoder=nil)
    [ NewRelic::Helper.time_to_millis(timestamp),
      string(path),
      string(message),
      string(exception_name_for_collector),
      params ]
  end

  private

  def constantize(class_name)
    namespaces = class_name.split('::')

    namespaces.inject(Object) do |namespace, name|
      return unless namespace
      namespace.const_get(name) if namespace.const_defined?(name)
    end
  end
end
