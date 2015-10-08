# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/helper'
require 'new_relic/agent/attribute_filter'

# This class encapsulates an error that was noticed by New Relic in a managed app.
class NewRelic::NoticedError
  extend NewRelic::CollectionHelper

  attr_accessor :path, :timestamp, :message, :exception_class_name,
                :request_uri, :request_port, :file_name, :line_number,
                :stack_trace, :attributes_from_notice_error, :attributes

  attr_reader   :exception_id, :is_internal

  STRIPPED_EXCEPTION_REPLACEMENT_MESSAGE = "Message removed by New Relic 'strip_exception_messages' setting"

  def initialize(path, exception, timestamp = Time.now)
    @exception_id = exception.object_id
    @path = path
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
    NewRelic::Agent.config[:'strip_exception_messages.whitelist'].any? do |klass|
      exception_class <= klass
    end
  end

  include NewRelic::Coerce

  def to_collector_array(encoder=nil)
    [ NewRelic::Helper.time_to_millis(timestamp),
      string(path),
      string(message),
      string(exception_class_name),
      processed_attributes ]
  end

  USER_ATTRIBUTES = "userAttributes".freeze
  AGENT_ATTRIBUTES = "agentAttributes".freeze
  INTRINSIC_ATTRIBUTES = "intrinsics".freeze

  EMPTY_HASH = {}.freeze

  DESTINATION = NewRelic::Agent::AttributeFilter::DST_ERROR_COLLECTOR

  # Note that we process attributes lazily and store the result. This is because
  # there is a possibility that a noticed error will be discarded and not sent back
  # as a traced error or TransactionError.
  def processed_attributes
    @processed_attributes ||= begin
      attributes = base_parameters
      append_attributes(attributes, USER_ATTRIBUTES, merged_custom_attributes)
      append_attributes(attributes, AGENT_ATTRIBUTES, build_agent_attributes)
      append_attributes(attributes, INTRINSIC_ATTRIBUTES, build_intrinsic_attributes)
      attributes
    end
  end

  def base_parameters
    params = {}
    params[:request_uri] = request_uri if request_uri
    params[:file_name]   = file_name   if file_name
    params[:line_number] = line_number if line_number
    params[:stack_trace] = stack_trace if stack_trace
    params
  end

  # We can get custom attributes from two sources--the transaction, which we
  # hold in @attributes, or passed options to notice_error which show up in
  # @attributes_from_notice_error. Both need filtering, so merge them together
  # in our Attributes class for consistent handling
  def merged_custom_attributes
    merged_attributes = NewRelic::Agent::Transaction::Attributes.new(NewRelic::Agent.instance.attribute_filter)

    merge_custom_attributes_from_transaction(merged_attributes)
    merge_custom_attributes_from_notice_error(merged_attributes)

    merged_attributes.custom_attributes_for(DESTINATION)
  end

  def merge_custom_attributes_from_transaction(merged_attributes)
    if @attributes
      from_transaction = @attributes.custom_attributes_for(DESTINATION)
      merged_attributes.merge_custom_attributes(from_transaction)
    end
  end

  def merge_custom_attributes_from_notice_error(merged_attributes)
    if @attributes_from_notice_error
      from_notice_error = NewRelic::NoticedError.normalize_params(@attributes_from_notice_error)
      merged_attributes.merge_custom_attributes(from_notice_error)
    end
  end

  def build_agent_attributes
    if @attributes
      @attributes.agent_attributes_for(DESTINATION)
    else
      EMPTY_HASH
    end
  end

  def build_intrinsic_attributes
    if @attributes
      @attributes.intrinsic_attributes_for(DESTINATION)
    else
      EMPTY_HASH
    end
  end

  def append_attributes(outgoing_params, outgoing_key, source_attributes)
    outgoing_params[outgoing_key] = source_attributes || {}
  end

  def agent_attributes
    processed_attributes[AGENT_ATTRIBUTES]
  end

  def custom_attributes
    processed_attributes[USER_ATTRIBUTES]
  end

  def intrinsic_attributes
    processed_attributes[INTRINSIC_ATTRIBUTES]
  end
end
