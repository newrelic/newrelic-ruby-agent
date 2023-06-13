
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'git'
require 'octokit'
require_relative '../../../lib/new_relic/version.rb'

branch_name = "prerelease_#{NewRelic::VERSION::MAJOR}_#{NewRelic::VERSION::MINOR}_#{NewRelic::VERSION::TINY}_#{Time.now.to_i}"
puts branch_name


puts File.expand_path('.')
git = Git.open('.')
# binding.irb
git.add_remote('fork','git@github.com:newrelic-ruby-agent-bot/newrelic-ruby-agent.git') unless git.remotes.map{|remote| remote.name}.include?('fork')

git.checkout(branch_name, new_branch: true, starting_point: 'dev')

git.add(all: true)
git.commit('Update version for release')
git.push('fork')

# ########
client = Octokit::Client.new(:access_token => ENV['GITHUB_TOKEN'])

title = "TEST: DONT MERGE ONLY IGNORE   // Prerelease #{NewRelic::VERSION::STRING}"
repo = 'newrelic/newrelic-ruby-agent'
fork_branch = "newrelic-ruby-agent-bot:#{branch_name}"

pr = client.create_pull_request(repo, 'dev', fork_branch, title, body)
client.add_labels_to_an_issue(repo, pr[:number], ['prerelease'])
