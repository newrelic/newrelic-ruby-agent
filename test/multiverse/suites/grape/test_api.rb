# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'grape'

class TestApi < Grape::API
  namespace :grape_ape
    get do
      'List grape apes!'
    end

    get ':id' do
      'Show grape ape!'
    end

    post do
      'Create grape ape!'
    end

    put ':id' do
      'Update grape ape!'
    end

    delete ':id' do
      'Destroy grape ape!'
    end
end
