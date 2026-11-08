# Subscribed to Rails.error in production when Sentry isn't configured: every unhandled exception in a request
# or a job, every exhausted retry, every failed scheduled task and everything the app reports itself as an error
# becomes an email to the operators. Warnings and expected errors (a missing record, a bad route) don't.
class Alerts::ErrorSubscriber
  # By name: some of these classes aren't loaded until the first request that needs them.
  IGNORED = %w[ ActionController::RoutingError ActiveRecord::RecordNotFound ActionController::InvalidAuthenticityToken
                ActionController::BadRequest ActionController::UnknownFormat ActionDispatch::Http::MimeNegotiation::InvalidType ].freeze

  def report(error, handled:, severity:, context:, source: nil)
    return if severity != :error || (error.class.ancestors.map(&:name) & IGNORED).any?

    Alerts.notify key_for(error), "#{error.class}: #{error.message.to_s.truncate(120)}", body_for(error, handled:, context:, source:)
  end

  private
    # One email an hour per error class and place it was raised, not per message (ids and amounts vary).
    def key_for(error)
      "error:#{error.class.name}:#{Digest::SHA256.hexdigest(error.backtrace&.first.to_s).first(12)}"
    end

    def body_for(error, handled:, context:, source:)
      <<~TEXT
        #{error.class}: #{error.message}

        #{handled ? "Reported by the app" : "Unhandled"}#{" in #{source}" if source.present?}, version #{Rails.configuration.x.release}, #{Time.current.utc.iso8601}.
        #{context.presence && "Context: #{context.map { "#{_1}=#{_2.inspect.truncate(200)}" }.join(", ")}"}
        #{Array(error.backtrace).first(15).join("\n")}
      TEXT
    end
end
