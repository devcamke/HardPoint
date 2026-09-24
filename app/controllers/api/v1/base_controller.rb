# The public API: JSON over HTTPS on api.<domain>, authenticated by a shop's API key (Bearer token).
# The key decides the shop, so every request runs as that shop, under row-level security like the app.
#
# Lists are paged by cursor (?after=<last id>&limit=, up to 100) and most take ?updated_since=<ISO 8601>.
# Amounts are integer cents in the shop's currency; quantities are decimal strings. Errors look like
# { "error": { "code": "not_found", "message": "…", "details": { … } } }.
class Api::V1::BaseController < ActionController::API
  include ActionController::HttpAuthentication::Token::ControllerMethods

  # Bodies name what they're about ({ "product": { … } }); nothing is guessed from the controller.
  wrap_parameters false

  PAGE_SIZE = 50
  MAX_PAGE_SIZE = 100

  before_action :authenticate
  around_action :within_shop
  before_action :require_api_plan
  before_action :require_write_access, unless: -> { request.get? || request.head? }
  rate_limit to: 600, within: 1.minute, by: -> { @api_key.id }, name: "key",
    with: -> { render_error :too_many_requests, "rate_limited", "At most 600 requests a minute per key; slow down and retry." }

  rescue_from ActiveRecord::RecordNotFound do
    render_error :not_found, "not_found", "No such #{controller_name.singularize.humanize(capitalize: false)} in this shop."
  end
  rescue_from ActionController::ParameterMissing, ActionController::BadRequest do |error|
    render_error :bad_request, "bad_request", error.message
  end
  rescue_from ActiveRecord::RecordInvalid do |error|
    render_invalid error.record
  end

  private
    def authenticate
      @api_key = authenticate_with_http_token { |token, _| ApiKey.authenticate(token) }
      render_error(:unauthorized, "unauthorized", "Send a valid API key: Authorization: Bearer hp_…") unless @api_key
    end

    def within_shop(&)
      Current.set(account: @api_key.account, api_key: @api_key) do
        @api_key.used_from(request.remote_ip)
        Time.use_zone("UTC", &) # times in answers are UTC, whatever the shop's zone
      end
    end

    def require_api_plan
      render_error :forbidden, "plan", "The API is on the Business and Enterprise plans." unless Current.account.subscription_plan.api?
    end

    def require_write_access
      if !@api_key.writable?
        render_error :forbidden, "read_only_key", "This key can only read. Make a read-and-write key in Settings › Developers."
      elsif Current.account.locked?
        render_error :payment_required, "shop_locked", "This shop is read-only, so nothing can be changed."
      end
    end

    def render_error(status, code, message, details: nil)
      render json: { error: { code: code, message: message, details: details }.compact }, status: status
    end

    def render_invalid(record)
      render_error :unprocessable_entity, "invalid", record.errors.full_messages.to_sentence, details: record.errors.to_hash(true)
    end

    # Cursor paging by id: stable while rows are added, unlike page numbers.
    def paginate(scope)
      limit = params.fetch(:limit, PAGE_SIZE).to_i.clamp(1, MAX_PAGE_SIZE)
      scope = scope.where(scope.arel_table[:id].gt(params[:after].to_i)) if params[:after].present?
      records = scope.reorder(:id).limit(limit + 1).to_a
      @next_cursor = records[limit - 1].id if records.size > limit
      response.headers["Link"] = %(<#{url_for(request.query_parameters.merge(after: @next_cursor, only_path: false))}>; rel="next") if @next_cursor
      records.first(limit)
    end

    def updated_since(scope, column = :updated_at)
      return scope if params[:updated_since].blank?

      scope.where(column => Time.iso8601(params[:updated_since])..)
    rescue ArgumentError
      raise ActionController::BadRequest, "updated_since must be an ISO 8601 time, like 2026-09-24T08:00:00Z"
    end

    # With an Idempotency-Key header, a repeated create gets the first answer back instead of doing it again.
    def idempotently
      key = request.headers["Idempotency-Key"].to_s.strip
      return yield if key.empty?

      digest = OpenSSL::Digest::SHA256.hexdigest([ request.method, request.path, request.raw_post ].join("\n"))
      if (earlier = @api_key.idempotency_keys.find_by(key: key))
        return render_error(:unprocessable_entity, "idempotency_key_reused", "This Idempotency-Key was used for a different request.") if earlier.request_digest != digest

        return render(json: earlier.response_body, status: earlier.response_status)
      end

      yield
      @api_key.idempotency_keys.create!(account: Current.account, key: key.first(255), request_digest: digest,
        response_status: response.status, response_body: JSON.parse(response.body)) if response.status < 500
    rescue ActiveRecord::RecordNotUnique
      render_error :conflict, "in_progress", "A request with this Idempotency-Key is already being handled; retry shortly."
    end
end
