# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/helper'

# This class encapsulates an error that was noticed by New Relic in a managed app.
class NewRelic::NoticedError
  extend NewRelic::CollectionHelper
  attr_accessor :path, :timestamp, :params, :message, :exception_class_name
  attr_reader   :exception_id, :is_internal,
                :custom_attributes, :agent_attributes, :intrinsic_attributes

  STRIPPED_EXCEPTION_REPLACEMENT_MESSAGE = "Message removed by New Relic 'strip_exception_messages' setting"

  def initialize(path, data, exception, timestamp = Time.now)
    @exception_id = exception.object_id
    @path = path

    @custom_attributes    = data.delete(:custom_attributes)
    @agent_attributes     = data.delete(:agent_attributes)
    @intrinsic_attributes = data.delete(:intrinsic_attributes)
    @params = NewRelic::NoticedError.normalize_params(data)

    @exception_class_name = exception.is_a?(Exception) ? exception.class.name : 'Error'

    # It's critical that we not hold onto the exception class constant in this
    # class. These objects get serialized for Resque to a process that might
    # not have the original exception class loaded, so do all processing now
    # while we have the actual exception!
    @is_internal = (exception.class < NewRelic::Agent::InternalAgentError)

    if exception.nil?
      @message = '<no message>'
    elsif exception.respond_to?('original_exception')
      @message = (exception.original_exception || exception).to_s
    else # exception is not nil, but does not respond to original_exception
      @message = exception.to_s
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
    if NewRelic::Agent.config[:'strip_exception_messages.enabled'] &&
       !self.class.passes_message_whitelist(exception.class)
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

  def ==(other)
    if other.respond_to?(:exception_id)
      exception_id == other.exception_id
    else
      false
    end
  end

  def self.passes_message_whitelist(exception_class)
    NewRelic::Agent.config.stripped_exceptions_whitelist.any? do |klass|
      exception_class <= klass
    end
  end

  include NewRelic::Coerce

  def to_collector_array(encoder=nil)
    [ NewRelic::Helper.time_to_millis(timestamp),
      string(path),
      string(message),
      string(exception_class_name),
      build_params ]
  end

  USER_ATTRIBUTES = "userAttributes".freeze
  AGENT_ATTRIBUTES = "agentAttributes".freeze
  INTRINSIC_ATTRIBUTES = "intrinsics".freeze

  def build_params
    append_attributes(params, USER_ATTRIBUTES, merged_custom_attributes)
    append_attributes(params, AGENT_ATTRIBUTES, @agent_attributes)
    append_attributes(params, INTRINSIC_ATTRIBUTES, @intrinsic_attributes)
    params
  end

  # We can get custom attributes from two sources--the transaction, which we
  # hold in @custom_attributes, or passed options to notice_error which show up
  # in params[:custom_params]. Both need filtering, so merge them together in
  # our Attributes class for consistent handling
  def merged_custom_attributes
    merged_attributes = NewRelic::Agent::Transaction::Attributes.new(NewRelic::Agent.instance.attribute_filter)

    if @custom_attributes
      custom_attributes_from_transaction = @custom_attributes.for_destination(NewRelic::Agent::AttributeFilter::DST_ERROR_COLLECTOR)
      merged_attributes.merge!(custom_attributes_from_transaction)
    end

    custom_attributes_from_notice_error = params.delete(:custom_params)
    if custom_attributes_from_notice_error
      merged_attributes.merge!(custom_attributes_from_notice_error)
    end

    merged_attributes
  end

  def append_attributes(outgoing_params, outgoing_key, source_attributes)
    if source_attributes
      attributes = source_attributes.for_destination(NewRelic::Agent::AttributeFilter::DST_ERROR_COLLECTOR)
    else
      attributes = {}
    end

    outgoing_params[outgoing_key] = event_params(attributes)
  end

end
