# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require Rails.root.join('lib/custom_helpers')
require Rails.root.join('lib/which_is_which')

class AgentsController < ApplicationController
  before_action :set_agent, only: %i[show edit update destroy]
  skip_before_action :verify_authenticity_token

  # GET /agents
  def index
    @agents = Agent.all
    render @agents, formats: %i[html json]
  end

  # GET /agents/1
  def show
    ::Custom::Helpers.custom_class_method
    ::Custom::Helpers.new.custom_instance_method
    ::WhichIsWhich.samename
    ::WhichIsWhich.new.samename
  end

  # GET /agents/new
  def new
    @agent = Agent.new
  end

  # GET /agents/1/edit
  def edit; end

  # POST /agents
  def create
    @agent = Agent.new(language: agent_params[:language])
    @agent.apply_random_values

    respond_to do |format|
      if @agent.save
        format.html { redirect_to @agent, notice: 'Agent was successfully created.' }
        format.json { render json: @agent }
      else
        format.html { render :new }
        format.json { render json: @agent.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /agents/1
  def update
    if @agent.update(agent_params)
      redirect_to @agent, notice: 'Agent was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /agents/1
  def destroy
    @agent.destroy
    NotifierJob.perform_later "#{@agent.id} destroyed"

    respond_to do |format|
      format.html { redirect_to agents_url, notice: 'Agent was successfully destroyed.' }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_agent
    @agent = Agent.find(params[:id])
  end

  # Only allow a list of trusted parameters through.
  def agent_params
    params.require(:agent).permit(:name, :repository, :language, :stars, :forks)
  end
end
