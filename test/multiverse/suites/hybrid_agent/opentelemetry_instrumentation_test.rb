# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true
require 'opentelemetry'

class HybridAgentTest < Minitest::Test
  def setup
    @tracer = OpenTelemetry.tracer_provider.tracer
  end

  i_suck_and_my_tests_are_order_dependent!()
  # def self.test_order
  #   :sorted
  # end

  # break the methods up into a command module and an assertions module
  def do_work_in_span(span_name:, span_kind:, &block)
    kind = span_kind.downcase.to_sym
    # we also have an in_span API, should that be used instead?
    span = @tracer.start_span(span_name, kind: kind)
    yield if block_given?
  ensure
    span&.finish
  end

  def do_work_in_transaction(transaction_name:, &block)
    # we also have an in_transaction API, should that be used instead?
    transaction = NewRelic::Agent::Tracer.start_transaction(name: transaction_name, category: :web)
    yield if block_given?
  ensure
    transaction&.finish
  end

  def do_work_in_segment(segment_name:, &block)
    # we also have an in_segment API (maybe?) should that be used instead?
    segment = NewRelic::Agent::Tracer.start_segment(name: segment_name)
    yield if block_given?
  ensure
    segment&.finish
  end

  def do_work_in_span_with_remote_parent(span_name:, span_kind:, &block)
    kind = span_kind.downcase.to_sym
    span = @tracer.start_span(span_name, kind: span_kind)
    span.context.instance_variable_set(:@remote, true)
    yield if block_given?
  ensure
    span&.finish
  end

  def o_tel_inject_headers
    # TODO
    yield if block_given?
  end

  def simulate_external_call(url:, &block)
    # TODO
    yield if block_given?
  end

  def add_otel_attribute(name:, value:, &block)
    current_otel_span&.set_attribute(name, value)
    yield if block_given?
  end

  def record_exception_on_span(error_message:, &block)
    # TODO
    yield if block_given?
  end

  def n_rinject_headers(&block)
    yield if block_given?
  end

  def current_otel_span
    return nil if OpenTelemetry::Trace.current_span == OpenTelemetry::Trace::Span::INVALID

    OpenTelemetry::Trace.current_span.context
  end

  def current_transaction
    NewRelic::Agent::Tracer.current_transaction
  end

  # what operations run in your work() funtion?

  def test_does_not_create_segment_without_a_transaction
    skip 'not yet implemented'
    do_work_in_span(span_name: "Bar", span_kind: "Internal") do
      # the OpenTelemetry span should not be created (span invalid)
      assert_equal OpenTelemetry::Trace.current_span, OpenTelemetry::Trace::Span::INVALID

      # there should be no transaction
      assert_nil NewRelic::Agent::Tracer.current_transaction
    end

    transactions = harvest_transaction_events![1]
    spans = harvest_span_events![1]

    assert_empty transactions
    assert_empty spans
  end

  def test_creates_opentelemetry_segment_in_a_transaction
    skip 'not yet implemented'
    do_work_in_transaction(transaction_name: "Foo") do
      do_work_in_span(span_name: "Bar", span_kind: "Internal")
      # OpenTelemetry API and New Relic API report the same trace ID
      assert_equal OpenTelemetry::Trace.current_span.context.trace_id, NewRelic::Agent::Tracer.current_transaction.guid

      # OpenTelemetry API and New Relic API report the same span ID
      assert_equal OpenTelemetry::Trace.current_span.context.span_id, NewRelic::Agent::Tracer.current_segment.guid
    end

    transactions = harvest_transaction_events![1][0]
    spans = harvest_span_events![1][0]

    assert_equal transactions[0]["name"], "Foo"
    assert_equal spans[0]["name"], "Bar"
    assert_equal spans[0]["category"], "generic"
    assert_equal spans[0]["parent_name"], "Foo"
    assert_equal spans[1]["name"], "Foo"
    assert_equal spans[1]["category"], "generic"
    assert spans[1]["nr.entryPoint"]
  end

  # TODO: define all commands in a module and include that module
  # TODO: define all assertion -> rule -> parameters as methods
  # TODO: consider defining a JSON parser that would take the entire
  # hybrid_agent.json file and turn the camel casing into snake
  # TODO: Write better error messages?
  # TODO: Reduce duplication with snake case parsing
  # TODO: Assess recursion
  test_cases = load_cross_agent_test('hybrid_agent')
  test_cases.each do |test_case|
    name = test_case["testDescription"].downcase.gsub(' ', '_')

    define_method("test_hybrid_agent_#{name}") do
      puts "TEST: #{name}"
      operations = test_case["operations"]
      operations.map do |o|
        parse_operation(o)
      end

      txns = harvest_transaction_events![1]
      spans = harvest_span_events![1]

      verify_agent_output(txns, test_case["agentOutput"], 'transactions')
      verify_agent_output(spans, test_case["agentOutput"], 'spans')
    end
  end

  def parse_operation(operation)
    # maybe make first letter lowercase?
    # to avoid some strange method names?
    command = operation["command"].gsub!(/(.)([A-Z])/,'\1_\2').downcase.to_sym
    parameters = operation['parameters']&.transform_keys {|k| k.gsub(/(.)([A-Z])/,'\1_\2').downcase.to_sym }
    puts command
    puts parameters
    # need an option for send if there aren't any parameters
    # ex. OTelInjectHeaders command has not parameters
    # is the recursion working? maybe more puts about what's coming through?
    if operation["childOperations"]
      # send with a block isn't working... the next binding is never hit
      send(command, **parameters) do
        operation['childOperations'].each do |o|
          parse_operation(o)
          # do we need to parse assertions here?
          # this isn't being reached because we'd get an arg error...
          parse_assertions if operation["assertions"]
        end

      end
    else
      send(command, **parameters)
      parse_assertions(operation["assertions"]) if operation["assertions"]
    end
  end

  def parse_assertions(assertions)
    binding.irb if self.name == "creates_new_relic_span_as_child_of_opentelemetry_span"
    # only the assertions for Does not create segment without a transaction
    # are actually being evaluated

    # we would either need to change the names to the right case
    # or define methods with casing matching the JSON file
    # for all the objects under test

    # for this one, the parameters are what would need to get
    # translated, since we're explicitly using cases for the
    # various operators
    assertions.each do |assertion|
      puts assertion['description']
      rule = assertion["rule"]
      parameters = rule["parameters"].transform_values { |k| k.gsub(/(.)([A-Z])/,'\1_\2').downcase }
      puts rule['operator']
      puts parameters
      case rule["operator"]
      when "Equals"
        # assert_equal eval(parameters["left"]), eval(parameters["right"]), "Expected #{parmeters['left']} to equal #{parameters['right']}. Result: #{parameters['left']} = #{eval(parameters['left'])}; #{parameters['right']} = #{eval(parameters['right'])}"
      when "NotValid"
        # assert_nil eval(parameters["object"]), 'NotValid failure'
      else
        raise 'missing rule case for assertions!'
      end
    end
  end

  def verify_agent_output(harvest, output, type)
    # why didn't you print?
    puts "Agent Output: #{type}: #{output[type]}"
    if output[type].empty?
      assert_empty harvest, 'Agent Output Empty failure'
    else
      harvest = harvest[0]
      # some of the keys for spans are different than the test
      # ex. entryPoint is nr.entryPoint
      # other keys will need to be translated from camel to snake case
      # ex. parentName
      output = snakeify(output[type])

      harvest.each do |h|
        break if h.empty? # is this still necessary?
        if output
          output.each do |o|
            if o && h
              # assert h >= o, "Agent output for #{type.capitalize} wasn't found in the harvest.\nharvest = #{h}\nagent output = #{o}"
            end
          end
        end
      end
    end
  end

  def snakeify(output)
    output.map do |o|
      o.transform_keys do |k|
        if k == 'entryPoint'
          k = 'nr.entryPoint'
        else
          k.gsub(/(.)([A-Z])/,'\1_\2').downcase
        end
      end
    end
  end
end
