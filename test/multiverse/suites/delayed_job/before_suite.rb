require 'delayed_job'
Delayed::Worker.guess_backend

if Delayed::Worker.backend.to_s == "Delayed::Backend::ActiveRecord::Job"
  require 'active_record'

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
end
