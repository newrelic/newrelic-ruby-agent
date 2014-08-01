# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class SqlObfuscationTests < Performance::TestCase
  def setup
    require 'new_relic/agent/database'
    @long_query  = NewRelic::Agent::Database::Statement.new("SELECT DISTINCT table0.* FROM `table0` INNER JOIN `table1` ON `table1`.`metric_id` = `table0`.`id` LEFT JOIN `table3` ON table3.id_column = table0.id_column AND table3.metric_id = table0.id WHERE `table1`.`other_id` IN (92776, 49992, 61710, 84911, 90744, 40647) AND `table0`.`id_column` = 81067 AND `table0`.`col12` = '' AND ((table0.id_column=81067 )) AND ((table3.timestamp IS NULL OR table3.timestamp > 1406810459)) AND (((table0.name LIKE 'WebTransaction/%') OR ((table0.name LIKE 'OtherTransaction/%/%') AND (table0.name NOT LIKE '%/all')))) LIMIT 2250")
    @short_query = NewRelic::Agent::Database::Statement.new("SELECT * FROM `table` WHERE id=2540250 AND name LIKE 'OtherTransaction/%/%'")

    @long_query_pg = @long_query.dup
    @long_query_pg.adapter = 'postgresql'
    @short_query_pg = @short_query.dup
    @short_query_pg.adapter = 'postgresql'
  end

  def test_obfuscate_sql
    iterations.times do
      NewRelic::Agent::Database.obfuscate_sql(@long_query)
      NewRelic::Agent::Database.obfuscate_sql(@short_query)
    end
  end

  def test_obfuscate_sql_postgres
    iterations.times do
      NewRelic::Agent::Database.obfuscate_sql(@long_query_pg)
      NewRelic::Agent::Database.obfuscate_sql(@short_query_pg)
    end    
  end
end
