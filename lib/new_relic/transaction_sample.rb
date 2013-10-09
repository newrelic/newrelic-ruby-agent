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
                  :threshold, :finished, :xray_session_id
    attr_reader :root_segment, :params, :sample_id
    attr_writer :prepared

    @@start_time = Time.now

    include TransactionAnalysis

    def initialize(time = Time.now.to_f, sample_id = nil)
      @sample_id = sample_id || object_id
      @start_time = time
      @params = { :segment_count => -1, :request_params => {} }
      @segment_count = -1
      @root_segment = create_segment 0.0, "ROOT"
      @prepared = false

      @guid = generate_guid
      NewRelic::Agent::TransactionState.get.request_guid = @guid
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

    def to_json
      JSON.dump(self.to_array)
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
        int_or_nil(xray_session_id)
      ]
    end

    def start_time
      Time.at(@start_time)
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
    def create_segment(relative_timestamp, metric_name=nil, segment_id = nil)
      raise TypeError.new("Frozen Transaction Sample") if finished
      @params[:segment_count] += 1
      @segment_count += 1
      NewRelic::TransactionSample::Segment.new(relative_timestamp, metric_name, segment_id)
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
      s = "Transaction Sample collected at #{start_time}\n"
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

    # return a new transaction sample that treats segments
    # with the given regular expression in their name as if they
    # were never called at all.  This allows us to strip out segments
    # from traces captured in development environment that would not
    # normally show up in production (like Rails/Application Code Loading)
    def omit_segments_with(regex)
      regex = Regexp.new(regex)

      sample = TransactionSample.new(@start_time, sample_id)

      sample.params = params.dup
      sample.params[:segment_count] = 0

      delta = build_segment_with_omissions(sample, 0.0, @root_segment, sample.root_segment, regex)
      sample.root_segment.end_trace(@root_segment.exit_timestamp - delta)
      sample.profile = self.profile
      sample
    end

    # Return a new transaction sample that can be sent to the New
    # Relic service. This involves potentially one or more of the
    # following options
    #
    #   :explain_sql : run EXPLAIN on all queries whose response times equal the value for this key
    #       (for example :explain_sql => 2.0 would explain everything over 2 seconds.  0.0 would explain everything.)
    #   :record_sql => [ :raw | :obfuscated] : copy over the sql, obfuscating if necessary
    def prepare_to_send!(options={})
      return self if @prepared

      if options[:record_sql]
        collect_explain_plans!(options[:explain_sql]) if options[:explain_sql]
        prepare_sql_for_transmission!(options[:record_sql])
      else
        strip_sql!
      end

      @prepared = true
      self
    end

    def params=(params)
      @params = params
    end

    def force_persist_sample?
      NewRelic::Agent::TransactionState.get.request_token &&
        self.duration > NewRelic::Agent::TransactionState.get.transaction.apdex_t
    end

  private

    HEX_DIGITS = (0..15).map{|i| i.to_s(16)}
    # generate a random 64 bit uuid
    def generate_guid
      guid = ''
      HEX_DIGITS.each do |a|
        guid << HEX_DIGITS[rand(16)]
      end
      guid
    end

    # This is badly in need of refactoring
    def build_segment_with_omissions(new_sample, time_delta, source_segment, target_segment, regex)
      source_segment.called_segments.each do |source_called_segment|
        # if this segment's metric name matches the given regular expression, bail
        # here and increase the amount of time that we reduce the target sample with
        # by this omitted segment's duration.
        do_omit = regex =~ source_called_segment.metric_name

        if do_omit
          time_delta += source_called_segment.duration
        else
          target_called_segment = new_sample.create_segment(
                source_called_segment.entry_timestamp - time_delta,
                source_called_segment.metric_name,
                source_called_segment.segment_id)

          target_segment.add_called_segment target_called_segment
          source_called_segment.params.each do |k,v|
            target_called_segment[k]=v
          end

          time_delta = build_segment_with_omissions(
                new_sample, time_delta, source_called_segment, target_called_segment, regex)
          target_called_segment.end_trace(source_called_segment.exit_timestamp - time_delta)
        end
      end

      return time_delta
    end

    def strip_sql!
      each_segment do |segment|
        segment.params.delete(:sql)
      end
    end

    def collect_explain_plans!(threshold)
      each_segment do |segment|
        if segment[:sql] && segment.duration > threshold
          segment[:explain_plan] = segment.explain_sql
        end
      end
    end

    def prepare_sql_for_transmission!(strategy)
      each_segment do |segment|
        if segment[:sql]
          segment[:sql] = case strategy
          when :raw
            segment[:sql].to_s
          when :obfuscated
            NewRelic::Agent::Database.obfuscate_sql(segment[:sql]).to_s
          end
        end
      end
    end
  end
end
