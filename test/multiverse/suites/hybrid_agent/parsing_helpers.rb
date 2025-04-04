# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module ParsingHelpers
  def harvest_and_verify_agent_output(agent_output)
    txns = harvest_transaction_events![1]
    spans = harvest_span_events![1]

    verify_agent_output(txns, agent_output, 'transactions')
    verify_agent_output(spans, agent_output, 'spans')
  end

  def parse_operation(operation)
    command = parse_command(operation['command'])
    parameters = parse_parameters(operation['parameters'])

    puts command if ENV['ENABLE_OUTPUT']
    puts parameters if ENV['ENABLE_OUTPUT']

    if operation['childOperations']
      send(command, **parameters) do
        operation['childOperations'].each do |o|
          parse_operation(o)
        end
      end
    else
      send(command, **parameters)
      parse_assertions(operation['assertions']) if operation['assertions']
    end
  end

  def parse_command(command)
    return 'nr_inject_headers' if command == 'NRInjectHeaders'

    snake_sub_downcase(command).to_sym
  end

  def parse_parameters(parameters)
    return {} unless parameters

    params = parameters.transform_keys { |k| snake_sub_downcase(k).to_sym }

    if params[:span_kind]
      params[:span_kind] = params[:span_kind].downcase.to_sym
    end

    params
  end

  def parse_assertions(assertions)
    assertions.each do |assertion|
      rule = assertion['rule']
      parameters = rule['parameters'].transform_values { |k| snake_sub_downcase(k) }

      puts assertion['description'] if ENV['ENABLE_OUTPUT']
      puts rule if ENV['ENABLE_OUTPUT']

      case rule['operator']
      when 'Equals'
        equals_assertion(parameters)
      when 'NotValid'
        not_valid_assertion(parameters)
      when 'Matches'
        matches_assertion(parameters)
      else
        raise "Missing rule case for assertions! Received: #{rule['operator']}"
      end
    end
  end

  def equals_assertion(parameters)
    left = parameters['left']
    left_result = evaluate_param_for_equals(left)

    right = parameters['right']
    right_result = evaluate_param_for_equals(right)

    assert_equal left_result, right_result, "Expected #{left} to equal #{right}"
  end

  def evaluate_param_for_equals(param)
    puts param if ENV['ENABLE_OUTPUT']

    case param
    when 'current_otel_span.trace_id' then current_otel_span_context&.trace_id
    when 'current_transaction.trace_id' then current_transaction&.trace_id
    when 'current_otel_span.span_id' then current_otel_span_context&.span_id
    when 'current_segment.span_id' then NewRelic::Agent::Tracer.current_segment&.guid
    when 'current_transaction.sampled' then current_transaction&.sampled?
    when 'injected.trace_id' then 'TODO'
    when 'injected.span_id' then 'TODO'
    when 'injected.sampled' then 'TODO'
    else
      raise "Missing parameter for assertion! Received: #{param}"
    end
  end

  def not_valid_assertion(parameters)
    puts parameters['object'] if ENV['ENABLE_OUTPUT']

    case parameters['object']
    when 'current_otel_span' then current_otel_span
    when 'current_transaction' then current_transaction
    else
      raise "Missing NotValid assertion object! Received: #{parameters['object']}"
    end

    assert_nil eval(parameters['object']), "Expected #{parameters['object']} to be nil"
  end

  def matches_assertion(parameters)
    object = parameters['object']
    actual = case object
    when 'current_otel_span.trace_id' then current_otel_span_context&.trace_id
    else
      raise "Missing object for matches assertion! Received: #{parameters['object']}"
    end

    expected = parameters['value']

    assert_equal expected, actual, "Expected #{object} to equal #{expected}"
  end

  def verify_agent_output(harvest, output, type)
    puts "Agent Output: #{type}: #{output[type]}" if ENV['ENABLE_OUTPUT']

    if output[type].empty?
      assert_empty harvest, "Agent output expected no #{type}. Found: #{harvest}"
    else
      h = harvest[0][1]
      output = prepare_keys(output[type])

      output&.each do |o|
        if o && h
          msg = "Agent output for #{type.capitalize} wasn't found in the harvest.\nHarvest: #{h}\nAgent output: #{o}"

          assert h >= o, msg
        end
      end
    end
  end

  def snake_sub_downcase(key)
    key.gsub(/(.)([A-Z])/, '\1_\2').downcase
  end

  def prepare_keys(output)
    output.map do |o|
      o.transform_keys do |k|
        if k == 'entryPoint'
          k = 'nr.entryPoint'
        else
          snake_sub_downcase(k)
        end
      end
    end
  end
end
