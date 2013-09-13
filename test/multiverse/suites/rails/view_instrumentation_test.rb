# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require './app'
require 'rails/test_help'
require 'multiverse_helpers'

ActionController::Base.view_paths = ['app/views']

class ViewsController < ApplicationController
  include Rails.application.routes.url_helpers
  def template_render_with_3_partial_renders
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
    # We need any old file that's around, preferrably with ERB embedding
    file = File.expand_path(File.join(File.dirname(__FILE__), "Envfile"))
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
    streamer = Class.new
    def each
      10_000.times do |i|
        yield "This is line #{i}\n"
      end
    end
    self.response_body = streamer.new
  end

  def raise_render
    raise "this is an uncaught RuntimeError"
  end
end

class ViewControllerTest < ActionController::TestCase
  tests ViewsController

  include MultiverseHelpers
  setup_and_teardown_agent do
    @controller = ViewsController.new
    # ActiveSupport testing keeps blowing away my subscribers on
    # teardown for some reason.  Have to keep putting it back.
    if Rails::VERSION::MAJOR.to_i == 4
      NewRelic::Agent::Instrumentation::ActionViewSubscriber \
        .subscribe(/render_.+\.action_view$/)
      NewRelic::Agent::Instrumentation::ActionControllerSubscriber \
        .subscribe(/^process_action.action_controller$/)
    end
  end
end

# SANITY TESTS - Make sure nothing raises errors,
# unless it's supposed to
class SanityTest < ViewControllerTest

  # assert we can call any of these renders with no errors
  # (except the one that does raise an error)
  (ViewsController.action_methods - ["raise_render"]).each do |method|
    test "should not raise errors on GET to #{method.inspect}" do
      get method.dup
    end

    test "should not raise errors on POST to #{method.inspect}" do
      post method.dup
    end
  end

  test "should allow an uncaught exception to propogate" do
    assert_raises RuntimeError do
      get :raise_render
    end
  end
end

# A controller action that renders 1 template and the same partial 3 times
class NormalishRenderTest < ViewControllerTest
  test "should count all the template and partial segments" do
    get :template_render_with_3_partial_renders
    sample = NewRelic::Agent.agent.transaction_sampler.last_sample
    assert_equal 5, sample.count_segments, "should be a node for the controller action, the template, and 3 partials (5)"
  end

  test "should have 3 segments with the metric name 'View/views/_a_partial.html.erb/Partial'" do
    get :template_render_with_3_partial_renders
    sample = NewRelic::Agent.agent.transaction_sampler.last_sample

    partial_segments = sample.root_segment.called_segments.first.called_segments.first.called_segments
    assert_equal 3, partial_segments.size, "sanity check"

    assert_equal ['View/views/_a_partial.html.erb/Partial'], partial_segments.map(&:metric_name).uniq
  end
end

class TextRenderTest < ViewControllerTest
  # it doesn't seem worth it to get consistent behavior here.
  if Rails::VERSION::MAJOR.to_i == 3 && Rails::VERSION::MINOR.to_i == 0
    test "should not instrument rendering of text" do
      get :text_render
      sample = NewRelic::Agent.agent.transaction_sampler.last_sample
      assert_equal [], sample.root_segment.called_segments.first.called_segments
    end
  else
    test "should create a metric for the rendered text" do
      get :text_render
      sample = NewRelic::Agent.agent.transaction_sampler.last_sample
      text_segment = sample.root_segment.called_segments.first.called_segments.first
      assert_equal 'View/text template/Rendering', text_segment.metric_name
    end
  end
end

class InlineTemplateRenderTest < ViewControllerTest
  test "should create a metric for the rendered inline template" do
    get :inline_render
    sample = NewRelic::Agent.agent.transaction_sampler.last_sample
    text_segment = sample.root_segment.called_segments.first.called_segments.first
    assert_equal 'View/inline template/Rendering', text_segment.metric_name
  end
end

class HamlRenderTest < ViewControllerTest
  test "should create a metric for the rendered haml template" do
    get :haml_render
    sample = NewRelic::Agent.agent.transaction_sampler.last_sample
    text_segment = sample.root_segment.called_segments.first.called_segments.first
    assert_equal 'View/views/haml_view.html.haml/Rendering', text_segment.metric_name
  end
end

class MissingTemplateTest < ViewControllerTest
  test "should create an proper metric when the template is unknown" do
    get :no_template
    sample = NewRelic::Agent.agent.transaction_sampler.last_sample
    text_segment = sample.root_segment.called_segments.first.called_segments.first

    # Different versions have significant difference in handling, but we're
    # happy enough with what each of them does in the unknown case
    if Rails::VERSION::MAJOR.to_i == 3 && Rails::VERSION::MINOR.to_i == 0
      assert_nil text_segment
    elsif Rails::VERSION::MAJOR.to_i == 3
      assert_equal 'View/collection/Partial', text_segment.metric_name
    else
      assert_equal 'View/(unknown)/Partial', text_segment.metric_name
    end
  end
end

class CollectionTemplateTest < ViewControllerTest
  test "should create a proper metric when we render a collection" do
    get :collection_render
    sample = NewRelic::Agent.agent.transaction_sampler.last_sample
    text_segment = sample.root_segment.called_segments.first.called_segments.first
    assert_equal "View/foos/_foo.html.haml/Partial", text_segment.metric_name
  end
end

class UninstrumentedRendersTest < ViewControllerTest
  [:js_render, :xml_render, :proc_render, :json_render ].each do |action|
    test "should not instrument rendering of #{action.inspect}" do
      get action
      sample = NewRelic::Agent.agent.transaction_sampler.last_sample
      assert_equal [], sample.root_segment.called_segments.first.called_segments
    end
  end
end

class FileRenderTest < ViewControllerTest
  test "should create a metric for rendered file that does not include the filename so it doesn't metric explode" do
    get :file_render
    sample = NewRelic::Agent.agent.transaction_sampler.last_sample
    text_segment = sample.root_segment.called_segments.first.called_segments.first
    assert_equal 'View/file/Rendering', text_segment.metric_name
  end
end
