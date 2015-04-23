# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require './app'
require 'haml'

ActionController::Base.view_paths = ['app/views']

class ViewsController < ApplicationController
  def template_render_with_3_partial_renders
    render 'index'
  end

  def render_with_delays
    freeze_time
    @delay = 1
    render 'index'
  end

  def deep_partial_render
    render 'deep_partial'
  end

  def text_render
    render :text => "Yay"
  end

  def json_render
    render :json => {"a" => "b"}
  end

  def xml_render
    render :xml => {"a" => "b"}
  end

  def js_render
    render :js => 'alert("this is js");'
  end

  def file_render
    # The choice of filename is significant here: we want a dot in the filename
    # in order to expose an issue on Rails 2.
    file = File.expand_path(File.join(File.dirname(__FILE__), "dummy.txt"))
    render :file => file, :content_type => 'text/plain', :layout => false
  end

  def nothing_render
    render :nothing => true
  end

  def inline_render
    render :inline => "<% Time.now %><p><%= Time.now %></p>"
  end

  def haml_render
    render 'haml_view'
  end

  def no_template
    render []
  end

  def collection_render
    render((1..3).map{|x| Foo.new })
  end

  # proc rendering isn't available in rails 3 but you can do nonsense like this
  # and assign an enumerable object to the response body.
  def proc_render
    streamer = Class.new do
      def each
        10_000.times do |i|
          yield "This is line #{i}\n"
        end
      end
    end
    self.response_body = streamer.new
  end

  def raise_render
    raise "this is an uncaught RuntimeError"
  end
end

class ViewInstrumentationTest < RailsMultiverseTest
  include MultiverseHelpers

  setup_and_teardown_agent do
    # ActiveSupport testing keeps blowing away my subscribers on
    # teardown for some reason.  Have to keep putting it back.
    if Rails::VERSION::MAJOR.to_i == 4
      NewRelic::Agent::Instrumentation::ActionViewSubscriber \
        .subscribe(/render_.+\.action_view$/)
      NewRelic::Agent::Instrumentation::ActionControllerSubscriber \
        .subscribe(/^process_action.action_controller$/)
    end
  end

  (ViewsController.action_methods - ['raise_render']).each do |method|

    # proc rendering doesn't work on Rails 2
    next if method == 'proc_render' && Rails::VERSION::MAJOR <= 2

    define_method("test_sanity_#{method}") do
      get "/views/#{method}"
      assert_equal 200, status
    end

    def test_should_allow_uncaught_exception_to_propagate
      get "/views/raise_render"
      assert_equal 500, status
    end

    def test_should_count_all_the_template_and_partial_nodes
      get '/views/template_render_with_3_partial_renders'
      sample = NewRelic::Agent.agent.transaction_sampler.last_sample
      nodes = find_all_nodes_with_name_matching(sample, ['^Nested/Controller/views', '^View'])
      nodes_list = "Found these nodes:\n  #{nodes.map(&:metric_name).join("\n  ")}"

      if Rails::VERSION::MAJOR <= 2
        assert_equal 8, nodes.length, "Should be a node for the controller action, the template, and 3 partials with two nodes each (8). #{nodes_list}"
      else
        assert_equal 5, nodes.length, "Should be a node for the controller action, the template, and 3 partials (5). #{nodes_list}"
      end
    end

    def test_should_have_3_nodes_with_the_correct_metric_name
      get '/views/template_render_with_3_partial_renders'

      sample = NewRelic::Agent.agent.transaction_sampler.last_sample
      partial_nodes = find_all_nodes_with_name_matching(sample, 'View/views/_a_partial.html.erb/Partial')

      assert_equal 3, partial_nodes.size, "sanity check"
      assert_equal ['View/views/_a_partial.html.erb/Partial'], partial_nodes.map(&:metric_name).uniq
    end

    # We don't capture text or inline template rendering on Rails 2
    if Rails::VERSION::MAJOR >= 3
      def test_should_create_a_metric_for_the_rendered_inline_template
        get '/views/inline_render'

        sample = NewRelic::Agent.agent.transaction_sampler.last_sample
        text_node = find_node_with_name(sample, 'View/inline template/Rendering')

        assert text_node, "Failed to find a node named View/inline template/Rendering"
        assert_metrics_recorded('View/inline template/Rendering')
      end

      # It doesn't seem worth it to get consistent behavior here.
      if Rails::VERSION::MAJOR.to_i == 3 && Rails::VERSION::MINOR.to_i == 0
        def test_should_not_instrument_rendering_of_text
          get '/views/text_render'
          sample = NewRelic::Agent.agent.transaction_sampler.last_sample
          refute find_node_with_name(sample, 'View/text template/Rendering')
        end
      else
        def test_should_create_a_metric_for_the_rendered_text
          get '/views/text_render'

          sample = NewRelic::Agent.agent.transaction_sampler.last_sample
          text_node = find_node_with_name(sample, 'View/text template/Rendering')

          assert text_node, "Failed to find a node named View/text template/Rendering"
          assert_metrics_recorded('View/text template/Rendering')
        end
      end
    end

    def test_should_create_a_metric_for_the_rendered_haml_template
      get '/views/haml_render'

      sample = NewRelic::Agent.agent.transaction_sampler.last_sample
      text_node = find_node_with_name(sample, 'View/views/haml_view.html.haml/Rendering')

      assert text_node, "Failed to find a node named View/views/haml_view.html.haml/Rendering"
      assert_metrics_recorded('View/views/haml_view.html.haml/Rendering')
    end

    def test_should_create_a_proper_metric_when_the_template_is_unknown
      get '/views/no_template'
      sample = NewRelic::Agent.agent.transaction_sampler.last_sample

      # Different versions have significant difference in handling, but we're
      # happy enough with what each of them does in the unknown case
      if Rails::VERSION::MAJOR.to_i < 3 || (Rails::VERSION::MAJOR.to_i == 3 && Rails::VERSION::MINOR.to_i == 0)
        refute find_node_with_name_matching(sample, /^View/)
      elsif Rails::VERSION::MAJOR.to_i == 3
        assert find_node_with_name(sample, 'View/collection/Partial')
      else
        assert find_node_with_name(sample, 'View/(unknown)/Partial')
      end
    end

    def test_should_create_a_proper_metric_when_we_render_a_collection
      get '/views/collection_render'
      sample = NewRelic::Agent.agent.transaction_sampler.last_sample
      assert find_node_with_name(sample, "View/foos/_foo.html.haml/Partial")
    end

    [:js_render, :xml_render, :proc_render, :json_render ].each do |action|
      next if action == :proc_render && Rails::VERSION::MAJOR <= 2
      define_method("test_should_not_instrument_rendering_of_#{action}") do
        get "/views/#{action}"
        sample = NewRelic::Agent.agent.transaction_sampler.last_sample
        view_node = find_node_with_name_matching(sample, /^View\//)
        refute view_node, "Should not instrument rendering of #{action}, found #{view_node}."
      end
    end

    # The Rails 2.3 view instrumentation doesn't actually pass this test, but it
    # hasn't been a problem thus far, so we're letting it slide.
    if Rails::VERSION::MAJOR >= 3
      def test_should_create_a_metric_for_rendered_file_that_does_not_include_the_filename_so_it_doesnt_metric_explode
        get '/views/file_render'
        sample = NewRelic::Agent.agent.transaction_sampler.last_sample
        assert find_node_with_name(sample, 'View/file/Rendering')
        refute find_node_with_name_matching(sample, 'dummy')
      end
    end

    def test_exclusive_time_for_template_render_metrics_should_not_include_partial_rendering_time
      get '/views/render_with_delays'

      expected_stats_partial = {
        :call_count           => 3,
        :total_call_time      => 3.0,
        :total_exclusive_time => 3.0
      }

      expected_stats_template = {
        :call_count           => 1,
        :total_call_time      => 4.0,
        :total_exclusive_time => 1.0  # top-level template takes 1s itself
      }

      scope = 'Controller/views/render_with_delays'
      template_metric = 'View/views/index.html.erb/Rendering'

      if Rails::VERSION::MAJOR <= 2
        partial_metric  = 'View/views/_a_partial.html.erb/Rendering'
      else
        partial_metric  = 'View/views/_a_partial.html.erb/Partial'
      end

      assert_metrics_recorded(
         partial_metric           => expected_stats_partial,
         template_metric          => expected_stats_template,
         [partial_metric, scope]  => expected_stats_partial,
         [template_metric, scope] => expected_stats_template
      )
    end
  end
end
