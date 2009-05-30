# Hook in the notification to merb
error_notifier = Proc.new {
  NewRelic::Agent.agent.error_collector.notice_error(request.exceptions.first, request, "#{request.controller.name}/#{params[:action]}", params)
}
Merb::Dispatcher::DefaultException.before error_notifier
Exceptions.before error_notifier
