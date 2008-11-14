# Hook in the notification to merb
error_notifier = Proc.new {
  NewRelic::Agent.agent.error_collector.notice_error("#{request.controller.name}/#{params[:action]}", request.path, params, request.exceptions.first)
}
Merb::Dispatcher::DefaultException.before error_notifier
Exceptions.before error_notifier
