# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'grape'

class GrapeTestApiError < StandardError; end

class GrapeTestApi < Grape::API
  # namespace, group, resource, and resources all do the same thing.
  # They are aliases for namespace.

  get :self_destruct do
    raise GrapeTestApiError.new("I'm sorry Dave, I'm afraid I can't do that.")
  end

  namespace :grape_ape do
    get do
      'List grape apes!'
    end

    get 'renamed' do
      ::NewRelic::Agent.set_transaction_name('RenamedTxn')
      'Totally renamed it.'
    end

    get ':id' do
      'Show grape ape!'
    end
  end

  resource :grape_ape do
    post do
      'Create grape ape!'
    end
  end

  resources :grape_ape do
    put ':id' do
      'Update grape ape!'
    end
  end

  group :grape_ape do
    delete ':id' do
      'Destroy grape ape!'
    end
  end

  resource :grape_ape_fail do
    post do
      raise GrapeTestApiError.new("I'm sorry Dave, I'm afraid I can't do that.")
    end
  end

  resource :grape_ape_fail_rescue do
    rescue_from :all do |e|
      err = {message: "rescued from #{e.class.name}"}
      NewRelic::Helper.version_satisfied?(Grape::VERSION, '>=', '2.1.0') ? error!(err) : error_response(err)
    end

    post do
      raise GrapeTestApiError.new("I'm sorry Dave, I'm afraid I can't do that.")
    end
  end
end

if NewRelic::Helper.version_satisfied?(Grape::VERSION, '>=', '1.2.0') && NewRelic::Helper.version_satisfied?(Grape::VERSION, '<=', '1.2.4')
  class GrapeApiInstanceTestApi < Grape::API::Instance
    namespace :banjaxing do
      get do
        'List of Banjaxing'
      end
    end
  end
end

if NewRelic::Helper.version_satisfied?(Grape::VERSION, '>=', '1.2.5')
  class GrapeApiInstanceTestApi < Grape::API
    namespace :banjaxing do
      get do
        'List of Banjaxing'
      end
    end
  end
end
