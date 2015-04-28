# encoding: utf-8
# This file is distributed under New Relic"s license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

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
      ::NewRelic::Agent.set_transaction_name("RenamedTxn")
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
      error_response({ message: "rescued from #{e.class.name}" })
    end

    post do
      raise GrapeTestApiError.new("I'm sorry Dave, I'm afraid I can't do that.")
    end
  end
end
