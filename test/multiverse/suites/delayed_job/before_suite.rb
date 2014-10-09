
$database_name = "testdb.#{ENV["MULTIVERSE_ENV"]}.sqlite3"
$db_connection = ActiveRecord::Base.establish_connection(:adapter => 'sqlite3',
                                                         :database => $database_name)

# TODO: This will almost certainly have to get more version/gem aware as wel
# test other backends and versions, but for now it does the job!
require 'generators/delayed_job/templates/migration'
class CreateDelayedJobs
  @connection = $db_connection
end

CreateDelayedJobs.up
