# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

Rails.application.routes.draw do
  # This allows us to use the repository as the slug for the URL
  # for more predictable URLs related to seed data
  resources :agents, param: :repository
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Defines the root path route ("/")
  # root "articles#index"

  namespace :admin, path: '/admin' do
    root to: 'settings#index'
  end

  root 'agents#index'

  get "/predictable/custom-event", to: "predictable#custom_event"
end
