require 'new_relic/transaction_sample/segment'
require 'new_relic/transaction_sample/summary_segment'
require 'new_relic/transaction_sample/fake_segment'
require 'new_relic/transaction_sample/composite_segment'
module NewRelic
  COLLAPSE_SEGMENTS_THRESHOLD = 2

  MYSQL_EXPLAIN_COLUMNS = [
        "Id",
        "Select Type",
        "Table",
        "Type",
        "Possible Keys",
        "Key",
        "Key Length",
        "Ref",
        "Rows",
        "Extra"
      ].freeze

  class TransactionSample

    attr_accessor :params, :root_segment
    attr_accessor :profile
    attr_reader :root_segment
    attr_reader :params
    attr_reader :sample_id
    
    @@start_time = Time.now

    include TransactionAnalysis

    class << self
      def obfuscate_sql(sql)
        NewRelic::Agent.instance.obfuscator.call(sql)
      end

      def get_connection(config)
        @@connections ||= {}

        connection = @@connections[config]

        return connection if connection

        begin
          connection = ActiveRecord::Base.send("#{config[:adapter]}_connection", config)
          @@connections[config] = connection
        rescue => e
          NewRelic::Agent.agent.log.error("Caught exception #{e} trying to get connection to DB for explain. Control: #{config}")
          NewRelic::Agent.agent.log.error(e.backtrace.join("\n"))
          nil
        end
      end

      def close_connections
        @@connections ||= {}
        @@connections.values.each do |connection|
          begin
            connection.disconnect!
          rescue
          end
        end

        @@connections = {}
      end

    end

    def initialize(time = Time.now.to_f, sample_id = nil)
      @sample_id = sample_id || object_id
      @start_time = time
      @root_segment = create_segment 0.0, "ROOT"
      @params = {}
      @params[:request_params] = {}
    end

    def count_segments
      @root_segment.count_segments - 1    # don't count the root segment
    end

    def truncate(max)
      count = count_segments
      return if count < max
      @root_segment.truncate(max + 1)
      
      ensure_segment_count_set(count)
    end

    def ensure_segment_count_set(count)
      params[:segment_count] ||= count
    end

    # offset from start of app
    def timestamp
      @start_time - @@start_time.to_f
    end

    # Used in the server only
    def to_json(options = {}) #:nodoc:
      map = {:sample_id => @sample_id,
        :start_time => @start_time,
        :root_segment => @root_segment}
      if @params && !@params.empty?
        map[:params] = @params
      end
      map.to_json
    end

    def start_time
      Time.at(@start_time)
    end

    def path_string
      @root_segment.path_string
    end

    def create_segment(relative_timestamp, metric_name, segment_id = nil)
      raise TypeError.new("Frozen Transaction Sample") if frozen?
      NewRelic::TransactionSample::Segment.new(relative_timestamp, metric_name, segment_id)
    end

    def duration
      root_segment.duration
    end

    def each_segment(&block)
      @root_segment.each_segment(&block)
    end

    def to_s_compact
      @root_segment.to_s_compact
    end

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

      params.each {|k,v| sample.params[k] = v}

      delta = build_segment_with_omissions(sample, 0.0, @root_segment, sample.root_segment, regex)
      sample.root_segment.end_trace(@root_segment.exit_timestamp - delta)
      sample.profile = self.profile
      sample
    end

    # return a new transaction sample that can be sent to the RPM service.
    # this involves potentially one or more of the following options
    #
    #   :explain_sql : run EXPLAIN on all queries whose response times equal the value for this key
    #       (for example :explain_sql => 2.0 would explain everything over 2 seconds.  0.0 would explain everything.)
    #   :keep_backtraces : keep backtraces, significantly increasing size of trace (off by default)
    #   :record_sql => [ :raw | :obfuscated] : copy over the sql, obfuscating if necessary
    def prepare_to_send(options={})
      sample = TransactionSample.new(@start_time, sample_id)

      sample.params.merge! self.params

      begin
        build_segment_for_transfer(sample, @root_segment, sample.root_segment, options)
      ensure
        self.class.close_connections
      end

      sample.root_segment.end_trace(@root_segment.exit_timestamp)
      sample
    end

    def analyze
      sample = self
      original_path_string = nil
      loop do
        original_path_string = sample.path_string.to_s
        new_sample = sample.dup
        new_sample.root_segment = sample.root_segment.dup
        new_sample.root_segment.called_segments = analyze_called_segments(root_segment.called_segments)
        sample = new_sample
        return sample if sample.path_string.to_s == original_path_string
      end

    end

    def params=(params)
      @params = params
    end

  private

    def analyze_called_segments(called_segments)
      path = nil
      like_segments = []

      segments = []

      called_segments.each do |segment|
        segment = segment.dup
        segment.called_segments = analyze_called_segments(segment.called_segments)

        current_path = segment.path_string
        if path == current_path
          like_segments << segment
        else
          segments += summarize_segments(like_segments)

          like_segments.clear
          like_segments << segment
          path = current_path
        end
      end
      segments += summarize_segments(like_segments)

      segments
    end

    def summarize_segments(like_segments)
      if like_segments.length > COLLAPSE_SEGMENTS_THRESHOLD
        [CompositeSegment.new(like_segments)]
      else
        like_segments
      end
    end

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

    # see prepare_to_send for what we do with options
    def build_segment_for_transfer(new_sample, source_segment, target_segment, options)
      source_segment.called_segments.each do |source_called_segment|
        target_called_segment = new_sample.create_segment(
              source_called_segment.entry_timestamp,
              source_called_segment.metric_name,
              source_called_segment.segment_id)

        target_segment.add_called_segment target_called_segment
        source_called_segment.params.each do |k,v|
        case k
          when :backtrace
            target_called_segment[k]=v if options[:keep_backtraces]
          when :sql
            # run an EXPLAIN on this sql if specified.
            if options[:record_sql] && options[:record_sql] && options[:explain_sql] && source_called_segment.duration > options[:explain_sql].to_f
              target_called_segment[:explanation] = source_called_segment.explain_sql
            end

            target_called_segment[:sql] = case options[:record_sql]
              when :raw then v
              when :obfuscated then TransactionSample.obfuscate_sql(v)
              else raise "Invalid value for record_sql: #{options[:record_sql]}"
            end if options[:record_sql]
          when :connection_config
            # don't copy it
          else
            target_called_segment[k]=v
          end
        end

        build_segment_for_transfer(new_sample, source_called_segment, target_called_segment, options)
        target_called_segment.end_trace(source_called_segment.exit_timestamp)
      end
    end

  end
end
