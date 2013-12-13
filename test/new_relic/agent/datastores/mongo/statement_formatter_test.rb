# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/datastores/mongo/statement_formatter'
require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','..','test_helper'))

class NewRelic::Agent::Datastores::Mongo::StatementFormatterTest < Test::Unit::TestCase
  def test_statement_formatter_removes_documents
    statement = { :database   => "multiverse",
                  :collection =>"tribbles",
                  :operation => :insert,
                  :documents  => [ { "name" => "soterios johnson",
                                     :_id   => "BSON::ObjectId()" } ] }

    formatted = NewRelic::Agent::Datastores::Mongo::StatementFormatter.format(statement)

    refute formatted.keys.include?(:documents), "Formatted statement should not include documents: #{formatted}"
  end

  def test_statement_formatter_obfuscates_selectors
    statement = { :database   => 'multiverse',
                  :collection => 'tribbles',
                  :selector   => { 'name'      => 'soterios johnson',
                                    :operation => :find,
                                    :_id       => "BSON::ObjectId('?')" } }

    expected = { :database   => 'multiverse',
                  :collection => 'tribbles',
                  :selector   => { 'name'      => '?',
                                    :operation => :find,
                                    :_id       => '?' } }

    obfuscated = NewRelic::Agent::Datastores::Mongo::StatementFormatter.format(statement)

    assert_equal expected, obfuscated
  end
end
