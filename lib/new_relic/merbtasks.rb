# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

namespace :newrelic do
  desc "Install the developer mode newrelic.yml file"
  task :default do
    load File.expand_path(File.join(__FILE__,"..","..","install.rb"))
  end
end
