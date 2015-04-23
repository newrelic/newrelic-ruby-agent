# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
require 'rack/request'
require 'rack/response'
require 'rack/file'

require 'conditional_vendored_metric_parser'
require 'new_relic/collection_helper'
require 'new_relic/metric_parser/metric_parser'
require 'new_relic/rack/agent_middleware'
require 'new_relic/agent/instrumentation/middleware_proxy'

module NewRelic
  module Rack
    # This middleware provides the 'developer mode' feature of newrelic_rpm,
    # which allows you to see data about local web transactions in development
    # mode immediately without needing to send this data to New Relic's servers.
    #
    # Enabling developer mode has serious performance and security impact, and
    # thus you should never use this middleware in a production or non-local
    # environment.
    #
    # This middleware should be automatically inserted in most contexts, but if
    # automatic middleware insertion fails, you may manually insert it into your
    # middleware chain.
    #
    # @api public
    #
    class DeveloperMode < AgentMiddleware

      VIEW_PATH   = File.expand_path('../../../../ui/views/'  , __FILE__)
      HELPER_PATH = File.expand_path('../../../../ui/helpers/', __FILE__)
      require File.join(HELPER_PATH, 'developer_mode_helper.rb')
      require 'new_relic/rack/developer_mode/segment_summary'

      include NewRelic::DeveloperModeHelper

      class << self
        attr_writer :profiling_enabled
      end

      def self.profiling_enabled?
        @profiling_enabled
      end

      def traced_call(env)
        return @app.call(env) unless /^\/newrelic/ =~ ::Rack::Request.new(env).path_info
        dup._call(env)
      end

      protected

      def _call(env)
        NewRelic::Agent.ignore_transaction

        @req = ::Rack::Request.new(env)
        @rendered = false
        case @req.path_info
        when /profile/
          profile
        when /file/
          ::Rack::File.new(VIEW_PATH).call(env)
        when /index/
          index
        when /threads/
          threads
        when /reset/
          reset
        when /show_sample_detail/
          show_sample_data
        when /show_sample_summary/
          show_sample_data
        when /show_sample_sql/
          show_sample_data
        when /explain_sql/
          explain_sql
        when /^\/newrelic\/?$/
          index
        else
          @app.call(env)
        end
      end

      private

      def index
        get_samples
        render(:index)
      end

      def reset
        NewRelic::Agent.instance.transaction_sampler.reset!
        NewRelic::Agent.instance.sql_sampler.reset!
        ::Rack::Response.new{|r| r.redirect('/newrelic/')}.finish
      end

      def explain_sql
        get_segment

        return render(:sample_not_found) unless @sample

        @sql = @segment[:sql]
        @trace = @segment[:backtrace]

        if NewRelic::Agent.agent.record_sql == :obfuscated
          @obfuscated_sql = @segment.obfuscated_sql
        end

        _headers, explanations = @segment.explain_sql
        if explanations
          @explanation = explanations
          if !@explanation.blank?
            first_row = @explanation.first
            # Show the standard headers if it looks like a mysql explain plan
            # Otherwise show blank headers
            if first_row.length < NewRelic::MYSQL_EXPLAIN_COLUMNS.length
              @row_headers = nil
            else
              @row_headers = NewRelic::MYSQL_EXPLAIN_COLUMNS
            end
          end
        end
        render(:explain_sql)
      end

      def profile
        should_be_on = (params['start'] == 'true')
        NewRelic::Rack::DeveloperMode.profiling_enabled = should_be_on

        index
      end

      def threads
        render(:threads)
      end

      def render(view, layout=true)
        add_rack_array = true
        if view.is_a? Hash
          layout = false
          if view[:object]
            # object *is* used here, as it is capture in the binding below
            object = view[:object]
          end

          if view[:collection]
            return view[:collection].map do |obj|
              render({:partial => view[:partial], :object => obj})
            end.join(' ')
          end

          if view[:partial]
            add_rack_array = false
            view = "_#{view[:partial]}"
          end
        end
        binding = Proc.new {}.binding
        if layout
          body = render_with_layout(view) do
            render_without_layout(view, binding)
          end
        else
          body = render_without_layout(view, binding)
        end
        if add_rack_array
          ::Rack::Response.new(body, 200, {'Content-Type' => 'text/html'}).finish
        else
          body
        end
      end

      # You have to call this with a block - the contents returned from
      # that block are interpolated into the layout
      def render_with_layout(view)
        body = ERB.new(File.read(File.join(VIEW_PATH, 'layouts/newrelic_default.rhtml')))
        body.result(Proc.new {}.binding)
      end

      # you have to pass a binding to this (a proc) so that ERB can have
      # access to helper functions and local variables
      def render_without_layout(view, binding)
        ERB.new(File.read(File.join(VIEW_PATH, 'newrelic', view.to_s + '.rhtml')), nil, nil, 'frobnitz').result(binding)
      end

      def content_tag(tag, contents, opts={})
        opt_values = opts.map {|k, v| "#{k}=\"#{v}\"" }.join(' ')
        "<#{tag} #{opt_values}>#{contents}</#{tag}>"
      end

      def sample
        @sample || @samples[0]
      end

      def params
        @req.params
      end

      def segment
        @segment
      end

      def show_sample_data
        get_sample

        return render(:sample_not_found) unless @sample

        @request_params = request_attributes_for(@sample)
        @custom_params = custom_attributes_for(@sample)

        controller_metric = @sample.transaction_name

        metric_parser = NewRelic::MetricParser::MetricParser.for_metric_named controller_metric
        @sample_controller_name = metric_parser.controller_name
        @sample_action_name = metric_parser.action_name

        @sql_segments = sql_segments(@sample)
        if params['d']
          @sql_segments.sort!{|a,b| b.duration <=> a.duration }
        end

        sort_method = params['sort'] || :total_time
        @profile_options = {:min_percent => 0.5, :sort_method => sort_method.to_sym}

        render(:show_sample)
      end

      def get_samples
        @samples = NewRelic::Agent.instance.transaction_sampler.dev_mode_sample_buffer.samples.select do |sample|
          sample.transaction_name != nil
        end

        return @samples = @samples.sort_by(&:duration).reverse                   if params['h']
        return @samples = @samples.sort{|x,y| x.params[:uri] <=> y.params[:uri]} if params['u']
        @samples = @samples.reverse
      end

      def get_sample
        get_samples
        id = params['id']
        sample_id = id.to_i
        @samples.each do |s|
          if s.sample_id == sample_id
            @sample = s
            return
          end
        end
      end

      def get_segment
        get_sample
        return unless @sample

        segment_id = params['segment'].to_i
        @segment = @sample.root_node.find_node(segment_id)
      end

      def custom_attributes_for(sample)
        sample.attributes.custom_attributes_for(NewRelic::Agent::AttributeFilter::DST_DEVELOPER_MODE)
      end

      REQUEST_PARAMETERS_PREFIX = "request.parameters".freeze

      def request_attributes_for(sample)
        agent_attributes = sample.attributes.agent_attributes_for(NewRelic::Agent::AttributeFilter::DST_DEVELOPER_MODE)
        agent_attributes.inject({}) do |memo, (key, value)|
          memo[key] = value if key.to_s.start_with?(REQUEST_PARAMETERS_PREFIX)
          memo
        end
      end

      def breakdown_data(sample, limit = nil)
        metric_hash = {}
        sample.each_node_with_nest_tracking do |node|
          unless node == sample.root_node
            metric_name = node.metric_name
            metric_hash[metric_name] ||= SegmentSummary.new(metric_name, sample)
            metric_hash[metric_name] << node
            metric_hash[metric_name]
          end
        end

        data = metric_hash.values

        data.sort! do |x,y|
          y.exclusive_time <=> x.exclusive_time
        end

        if limit && data.length > limit
          data = data[0..limit - 1]
        end

        # add one last node for the remaining time if any
        remainder = sample.duration
        data.each do |node|
          remainder -= node.exclusive_time
        end

        if (remainder*1000).round > 0
          remainder_summary = SegmentSummary.new('Remainder', sample)
          remainder_summary.total_time = remainder_summary.exclusive_time = remainder
          remainder_summary.call_count = 1
          data << remainder_summary
        end

        data
      end

      # return an array of sql statements executed by this transaction
      # each element in the array contains [sql, parent_segment_metric_name, duration]
      def sql_segments(sample, show_non_sql_segments = true)
        segments = []
        sample.each_node do |segment|
          segments << segment if segment[:sql] || segment[:sql_obfuscated] || (show_non_sql_segments && segment[:key])
        end
        segments
      end

    end
  end
end
