# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# This class is used to test Sidekiq's Delayed Extensions
# which give the framework an interface like Delayed Job.
# The Delayed Extensions cannot be used to operate directly
# on a Sidekiq Worker.
class TestModel
  def self.do_work
  end
end
