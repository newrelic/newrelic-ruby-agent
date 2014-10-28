# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'base64'

require 'new_relic/transaction_sample/segment'
require 'new_relic/transaction_sample/summary_segment'
require 'new_relic/transaction_sample/fake_segment'
require 'new_relic/transaction_sample/composite_segment'
module NewRelic
  # the number of segments that need to exist before we roll them up
  # into one segment with multiple executions
  COLLAPSE_SEGMENTS_THRESHOLD = 2

  class TransactionSample

    attr_accessor :params, :root_segment, :profile, :force_persist, :guid,
                  :threshold, :finished, :xray_session_id, :start_time,
                  :synthetics_resource_id
    attr_reader :root_segment, :params, :sample_id
    attr_writer :prepared

    @@start_time = Time.now

    def initialize(time = Time.now.to_f, sample_id = nil)
      @sample_id = sample_id || object_id
      @start_time = time
      @params = { :segment_count => -1, :request_params => {} }
      @segment_count = -1
      @root_segment = create_segment 0.0, "ROOT"
      @prepared = false
    end

    def prepared?
      @prepared
    end

    def count_segments
      @segment_count
    end

    # makes sure that the parameter cache for segment count is set to
    # the correct value
    def ensure_segment_count_set(count)
      params[:segment_count] ||= count
    end

    # offset from start of app
    def timestamp
      @start_time - @@start_time.to_f
    end

    def set_custom_param(name, value)
      @params[:custom_params] ||= {}
      @params[:custom_params][name] = value
    end

    include NewRelic::Coerce

    def to_array
      [ float(@start_time),
        @params[:request_params],
        @params[:custom_params],
        @root_segment.to_array ]
    end

    def to_collector_array(encoder)
      trace_tree = encoder.encode(self.to_array)
      [ Helper.time_to_millis(@start_time),
        Helper.time_to_millis(duration),
        string(transaction_name),
        string(@params[:uri]),
        trace_tree,
        string(@guid),
        nil,
        forced?,
        int_or_nil(xray_session_id),
        string(synthetics_resource_id)
      ]
    end

    def path_string
      @root_segment.path_string
    end

    def transaction_name
      @params[:path]
    end

    def transaction_name=(new_name)
      @params[:path] = new_name
    end

    def forced?
      !!@force_persist || !int_or_nil(xray_session_id).nil?
    end

    # relative_timestamp is seconds since the start of the transaction
    def create_segment(relative_timestamp, metric_name=nil)
      raise TypeError.new("Frozen Transaction Sample") if finished
      @params[:segment_count] += 1
      @segment_count += 1
      NewRelic::TransactionSample::Segment.new(relative_timestamp, metric_name)
    end

    def duration
      root_segment.duration
    end

    # Iterates recursively over each segment in the entire transaction
    # sample tree
    def each_segment(&block)
      @root_segment.each_segment(&block)
    end

    # Iterates recursively over each segment in the entire transaction
    # sample tree while keeping track of nested segments
    def each_segment_with_nest_tracking(&block)
      @root_segment.each_segment_with_nest_tracking(&block)
    end

    def to_s_compact
      @root_segment.to_s_compact
    end

    # Searches the tree recursively for the segment with the given
    # id. note that this is an internal id, not an ActiveRecord id
    def find_segment(id)
      @root_segment.find_segment(id)
    end

    def to_s
      s = "Transaction Sample collected at #{Time.at(start_time)}\n"
      s << "  {\n"
      s << "  Path: #{params[:path]} \n"

      params.each do |k,v|
        next if k == :path
        s << "  #{k}: " <<
        case v
          when Enumerable then v.map(&:to_s).sort.join("; ")
          when String then v
          when Float then '%6.3s' % v
          when Fixnum then v.to_s
          when nil then ''
        else
          raise "unexpected value type for #{k}: '#{v}' (#{v.class})"
        end << "\n"
      end
      s << "  }\n\n"
      s <<  @root_segment.to_debug_str(0)
    end

    # Return a new transaction sample that can be sent to the New
    # Relic service.
    def prepare_to_send!
      return self if @prepared

      if Agent::Database.should_record_sql?
        collect_explain_plans!
        prepare_sql_for_transmission!
      else
        strip_sql!
      end

      @prepared = true
      self
    end

    def params=(params)
      @params = params
    end

  private

    def strip_sql!
      each_segment do |segment|
        segment.params.delete(:sql)
      end
    end

    def collect_explain_plans!
      return unless Agent::Database.should_collect_explain_plans?
      threshold = Agent.config[:'transaction_tracer.explain_threshold']
      each_segment do |segment|
        if segment[:sql] && segment.duration > threshold
          segment[:explain_plan] = segment.explain_sql
        end
      end
    end

    def prepare_sql_for_transmission!
      strategy = Agent::Database.record_sql_method
      each_segment do |segment|
        if segment[:sql]
          segment[:sql] = case strategy
          when :raw
            segment[:sql].to_s
          when :obfuscated
            Agent::Database.obfuscate_sql(segment[:sql]).to_s
          end
        end
      end
    end
  end
end
