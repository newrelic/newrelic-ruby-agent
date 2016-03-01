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

        UNKNOWN_NODE_NAME = '<unknown>'.freeze

        def initialize(timestamp, metric_name)
          @entry_timestamp = timestamp
          @metric_name     = metric_name || UNKNOWN_NODE_NAME
          @called_nodes    = nil
        end

        # sets the final timestamp on a node to indicate the exit
        # point of the node
        def end_trace(timestamp)
          @exit_timestamp = timestamp
        end

        def add_called_node(s)
          @called_nodes ||= []
          @called_nodes << s
          s.parent_node = self
        end

        def to_s
          to_debug_str(0)
        end

        def to_array
          [ NewRelic::Helper.time_to_millis(@entry_timestamp),
            NewRelic::Helper.time_to_millis(@exit_timestamp),
            NewRelic::Coerce.string(@metric_name),
            (@params || {}) ] +
            [ (@called_nodes ? @called_nodes.map{|s| s.to_array} : []) ]
        end

        def path_string
          "#{metric_name}[#{called_nodes.collect {|node| node.path_string }.join('')}]"
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

        # return the total duration of this node
        def duration
          (@exit_timestamp - @entry_timestamp).to_f
        end

        # return the duration of this node without
        # including the time in the called nodes
        def exclusive_duration
          d = duration

          called_nodes.each do |node|
            d -= node.duration
          end
          d
        end

        def count_nodes
          count = 1
          called_nodes.each { | node | count  += node.count_nodes }
          count
        end

        def []=(key, value)
          # only create a parameters field if a parameter is set; this will save
          # bandwidth etc as most nodes have no parameters
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

        # call the provided block for this node and each
        # of the called nodes
        def each_node(&block)
          block.call self

          if @called_nodes
            @called_nodes.each do |node|
              node.each_node(&block)
            end
          end
        end

        # call the provided block for this node and each
        # of the called nodes while keeping track of nested nodes
        def each_node_with_nest_tracking(&block)
          summary = block.call self
          summary.current_nest_count += 1 if summary

          if @called_nodes
            @called_nodes.each do |node|
              node.each_node_with_nest_tracking(&block)
            end
          end

          summary.current_nest_count -= 1 if summary
        end

        # This is only for use by developer mode
        def find_node(id)
          return self if object_id == id
          called_nodes.each do |node|
            found = node.find_node(id)
            return found if found
          end
          nil
        end

        def explain_sql
          return params[:explain_plan] if params.key?(:explain_plan)

          statement = params[:sql]
          return nil unless statement.is_a?(Database::Statement)

          NewRelic::Agent::Database.explain_sql(statement)
        end

        def obfuscated_sql
          NewRelic::Agent::Database.obfuscate_sql(params[:sql].sql)
        end

        def called_nodes=(nodes)
          @called_nodes = nodes
        end

        protected
        def parent_node=(s)
          @parent_node = s
        end
      end
    end
  end
end
