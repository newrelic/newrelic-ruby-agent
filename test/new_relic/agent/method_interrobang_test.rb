# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'test/unit'
require 'newrelic_rpm'
require 'new_relic/agent/method_tracer'

class MethodInterrobangTest < Test::Unit::TestCase
	include NewRelic::Agent::MethodTracer

	def interrogate?
		"say what?"
	end

	def mutate!
		"oh yeah!"
	end

	add_method_tracer :interrogate?
	add_method_tracer :mutate!

	def test_alias_method_ending_in_question_mark
		assert_respond_to self, :interrogate?
		assert_equal "say what?", interrogate?
	end

	def test_aliase_method_ending_in_exclamation_makr
		assert_respond_to self, :mutate!
		assert_equal "oh yeah!", mutate!
	end
end
