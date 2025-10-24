# frozen_string_literal: true

Rails.application.routes.draw do
  resources :agents
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Defines the root path route ("/")
  # root "articles#index"

  namespace :admin, path: '/admin' do
    root to: 'settings#index'
  end

  root 'agents#index'

  get "/predictable/custom-event", to: "predictable#custom_event"
end
