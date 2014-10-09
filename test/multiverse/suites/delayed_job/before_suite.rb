require 'active_record'
require 'delayed_job'
Delayed::Worker.guess_backend

# TODO: Currently assumes the ActiveRecord backend and creates database.
# That'll need to get updated if we choose to support the mongoid backend
$database_name = "testdb.#{ENV["MULTIVERSE_ENV"]}.sqlite3"
$db_connection = ActiveRecord::Base.establish_connection(:adapter => 'sqlite3',
                                                         :database => $database_name)

begin
  require 'generators/delayed_job/templates/migration'
rescue MissingSourceFile
  # Back on DJ v2 the generators aren't in the lib folder so we have to do some
  # sneaky stuff to get them loaded. Still better than dup'ing them, though.
  dj_dir = ($:).grep(/delayed_job-/).first
  require "#{dj_dir}/../generators/delayed_job/templates/migration"
end

class CreateDelayedJobs
  @connection = $db_connection
end

CreateDelayedJobs.up
