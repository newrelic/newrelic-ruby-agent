# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/datastores/mongo/obfuscator'
require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','..','test_helper'))

class NewRelic::Agent::Datastores::Mongo::ObfuscatorTest < Test::Unit::TestCase
  def test_obfuscator_removes_values_from_statement
    statement = { :database   => 'multiverse',
                  :collection => 'tribbles',
                  :selector   => { 'name'      => 'soterios johnson',
                                    :operation => :find,
                                    :_id       => "BSON::ObjectId('?')" } }

    expected = { :database   => 'multiverse',
                 :collection => 'tribbles',
                 :selector   => { 'name'     => '?',
                                  :operation => '?',
                                  :_id       => '?' } }

    obfuscated = NewRelic::Agent::Datastores::Mongo::Obfuscator.obfuscate_statement(statement)

    assert_equal expected, obfuscated
  end
end
