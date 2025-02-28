# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'opentelemetry'

class HybridAgentTest < Minitest::Test
  def setup
    @tracer = OpenTelemetry.tracer_provider.tracer
  end

  # Questions:
  # Should we use the in_span and in_transaction apis instead of start_*?
  # Should I move the span kind coercion into an earlier helper method, mirroring what Chris did for .NET?
  # What operations run in your work() funtion?

  # TODO: break the methods up into a command module and an assertions module

  # Commands
  def do_work_in_span(span_name:, span_kind:, &block)
    kind = span_kind.downcase.to_sym
    span = @tracer.start_span(span_name, kind: kind)
    yield if block
  ensure
    span&.finish
  end

  def do_work_in_span_with_remote_parent(span_name:, span_kind:, &block)
    kind = span_kind.downcase.to_sym
    span = @tracer.start_span(span_name, kind: span_kind)
    span.context.instance_variable_set(:@remote, true)
    yield if block
  ensure
    span&.finish
  end

  def do_work_in_transaction(transaction_name:, &block)
    transaction = NewRelic::Agent::Tracer.start_transaction(name: transaction_name, category: :web)
    yield if block
  ensure
    transaction&.finish
  end

  def do_work_in_segment(segment_name:, &block)
    segment = NewRelic::Agent::Tracer.start_segment(name: segment_name)
    yield if block
  ensure
    segment&.finish
  end

  def add_otel_attribute(name:, value:, &block)
    OpenTelemetry::Trace.current_span&.set_attribute(name, value)
    yield if block
  end

  def record_exception_on_span(error_message:, &block)
    exception = StandardError.new(error_message)
    OpenTelemetry::Trace.current_span.record_exception(exception)
    yield if block
  end

  def simulate_external_call(url:, &block)
    # TODO
    yield if block
  end

  def o_tel_inject_headers
    # TODO
    yield if block_given?
  end

  def n_rinject_headers(&block)
    # TODO
    yield if block
  end

  ## Assertions

  # provides the context to help with the assertions
  # which access trace_id and span_id
  def current_otel_span
    return nil if OpenTelemetry::Trace.current_span == OpenTelemetry::Trace::Span::INVALID

    OpenTelemetry::Trace.current_span.context
  end

  def current_transaction
    NewRelic::Agent::Tracer.current_transaction
  end

  # this needs some finagling
  # we don't have a span_id on our segment
  # the segment id should be equal to the span id
  # and both are accessed with guid, not id
  def current_segment
    NewRelic::Agent::Tracer.current_segment
  end

  def injected
    # TODO
    # should be able to return
    # injected.trace_id
    # inject.span_id
    # injected.sampled
    # maybe use a struct?
  end

  # TODO: define all commands in a module and include that module
  # TODO: define all assertion -> rule -> parameters as methods
  # TODO: Write better error messages?
  # TODO: Reduce duplication with snake case parsing
  test_cases = load_cross_agent_test('hybrid_agent')
  test_cases.each do |test_case|
    name = test_case['testDescription'].downcase.tr(' ', '_')

    define_method("test_hybrid_agent_#{name}") do
      puts "TEST: #{name}"
      operations = test_case['operations']
      operations.map do |o|
        parse_operation(o)
      end

      harvest_and_verify_agent_output(test_case['agent_output'])
    end
  end

  def harvest_and_verify_agent_output(agent_output)
    txns = harvest_transaction_events![1]
    spans = harvest_span_events![1]

    verify_agent_output(txns, agent_output, 'transactions')
    verify_agent_output(spans, agent_output, 'spans')
  end

  def parse_operation(operation)
    # maybe make first letter lowercase?
    # to avoid some strange method names?
    # or use case statement?
    command = operation['command'].gsub!(/(.)([A-Z])/, '\1_\2').downcase.to_sym
    parameters = operation['parameters']&.transform_keys { |k| k.gsub(/(.)([A-Z])/, '\1_\2').downcase.to_sym }
    puts command
    puts parameters
    # need an option for send if there aren't any parameters
    # ex. OTelInjectHeaders command has not parameters
    # is the recursion working? maybe more puts about what's coming through?
    if operation['childOperations']
      # send with a block isn't working... the next binding is never hit
      send(command, **parameters) do
        operation['childOperations'].each do |o|
          parse_operation(o)
          # do we need to parse assertions here?
          # this isn't being reached because we'd get an arg error...
          parse_assertions if operation['assertions']
        end
      end
    else
      send(command, **parameters)
      parse_assertions(operation['assertions']) if operation['assertions']
    end
  end

  def parse_assertions(assertions)
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
      rule = assertion['rule']
      parameters = rule['parameters'].transform_values { |k| k.gsub(/(.)([A-Z])/, '\1_\2').downcase }
      puts rule['operator']
      puts parameters
      case rule['operator']
      when 'Equals'
        # TODO: Re-enable assertions
        # msg = "Expected #{parmeters['left']} to equal #{parameters['right']}.\nResult:\b#{parameters['left']} = #{eval(parameters['left'])};\n#{parameters['right']} = #{eval(parameters['right'])}"
        # assert_equal eval(parameters["left"]), eval(parameters["right"]), msg
      when 'NotValid'
        # TODO: Re-enable assertions
        # assert_nil eval(parameters["object"]), "Expected #{parameters['object']} to be nil"
      else
        raise 'missing rule case for assertions!'
      end
    end
  end

  def verify_agent_output(harvest, output, type)
    puts "Agent Output: #{type}: #{output[type]}"
    if output[type].empty?
      assert_empty harvest, "Agent output expected no transactions or spans. Found: #{harvest}"
    else
      harvest = harvest[0]
      output = snakeify(output[type])

      harvest.each do |h|
        # maybe we do want this b/c of the extra empty hashes that appear sometimes?
        # break if h.empty?
        # or if that's not right:
        # raise 'Agent Output: Found harvest empty when agent output expected data.' if h.empty?

        output&.each do |o|
          if o && h
            # msg =  "Agent output for #{type.capitalize} wasn't found in the harvest.\nharvest = #{h}\nagent output = #{o}"
            # TODO: Re-enable assertions
            # assert h >= o, msg
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
          k.gsub(/(.)([A-Z])/, '\1_\2').downcase
        end
      end
    end
  end
end
