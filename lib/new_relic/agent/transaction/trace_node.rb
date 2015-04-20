# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    class Transaction
      class TraceNode
        attr_reader :entry_timestamp
        # The exit timestamp will be relative except for the outermost sample which will
        # have a timestamp.
        attr_reader :exit_timestamp
        attr_reader :parent_node

        attr_accessor :metric_name

        UNKNOWN_SEGMENT_NAME = '<unknown>'.freeze

        def initialize(timestamp, metric_name)
          @entry_timestamp = timestamp
          @metric_name     = metric_name || UNKNOWN_SEGMENT_NAME
        end

        # sets the final timestamp on a segment to indicate the exit
        # point of the segment
        def end_trace(timestamp)
          @exit_timestamp = timestamp
        end

        def add_called_segment(s)
          @called_nodes ||= []
          @called_nodes << s
          s.parent_node = self
        end

        def to_s
          to_debug_str(0)
        end

        include NewRelic::Coerce

        def to_array
          [ NewRelic::Helper.time_to_millis(@entry_timestamp),
            NewRelic::Helper.time_to_millis(@exit_timestamp),
            string(@metric_name),
            (@params || {}) ] +
            [ (@called_nodes ? @called_nodes.map{|s| s.to_array} : []) ]
        end

        def path_string
          "#{metric_name}[#{called_nodes.collect {|segment| segment.path_string }.join('')}]"
        end

        def to_s_compact
          str = ""
          str << metric_name
          if called_nodes.any?
            str << "{#{called_nodes.map { | cs | cs.to_s_compact }.join(",")}}"
          end
          str
        end

        def to_debug_str(depth)
          tab = "  " * depth
          s = tab.clone
          s << ">> #{'%3i ms' % (@entry_timestamp*1000)} [#{self.class.name.split("::").last}] #{metric_name} \n"
          unless params.empty?
            params.each do |k,v|
              s << "#{tab}    -#{'%-16s' % k}: #{v.to_s[0..80]}\n"
            end
          end
          called_nodes.each do |cs|
            s << cs.to_debug_str(depth + 1)
          end
          s << tab + "<< "
          s << case @exit_timestamp
          when nil then ' n/a'
          when Numeric then '%3i ms' % (@exit_timestamp*1000)
          else @exit_timestamp.to_s
          end
          s << " #{metric_name}\n"
        end

        def called_nodes
          @called_nodes || []
        end

        # return the total duration of this segment
        def duration
          (@exit_timestamp - @entry_timestamp).to_f
        end

        # return the duration of this segment without
        # including the time in the called segments
        def exclusive_duration
          d = duration

          called_nodes.each do |segment|
            d -= segment.duration
          end
          d
        end

        def count_segments
          count = 1
          called_nodes.each { | seg | count  += seg.count_segments }
          count
        end

        def []=(key, value)
          # only create a parameters field if a parameter is set; this will save
          # bandwidth etc as most segments have no parameters
          params[key] = value
        end

        def [](key)
          params[key]
        end

        def params
          @params ||= {}
        end

        def params=(p)
          @params = p
        end

        # call the provided block for this segment and each
        # of the called segments
        def each_segment(&block)
          block.call self

          if @called_nodes
            @called_nodes.each do |segment|
              segment.each_segment(&block)
            end
          end
        end

        # call the provided block for this segment and each
        # of the called segments while keeping track of nested segments
        def each_segment_with_nest_tracking(&block)
          summary = block.call self
          summary.current_nest_count += 1 if summary

          if @called_nodes
            @called_nodes.each do |segment|
              segment.each_segment_with_nest_tracking(&block)
            end
          end

          summary.current_nest_count -= 1 if summary
        end

        # This is only for use by developer mode
        def find_segment(id)
          return self if object_id == id
          called_nodes.each do |segment|
            found = segment.find_segment(id)
            return found if found
          end
          nil
        end

        def explain_sql
          return params[:explain_plan] if params.key?(:explain_plan)

          statement = params[:sql]
          return nil unless statement.respond_to?(:config) &&
            statement.respond_to?(:explainer)

          NewRelic::Agent::Database.explain_sql(statement,
                                                statement.config,
                                                &statement.explainer)
        end

        def obfuscated_sql
          NewRelic::Agent::Database.obfuscate_sql(params[:sql])
        end

        def called_nodes=(segments)
          @called_nodes = segments
        end

        protected
        def parent_node=(s)
          @parent_node = s
        end
      end
    end
  end
end
