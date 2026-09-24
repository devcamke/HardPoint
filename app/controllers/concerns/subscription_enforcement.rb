# A read-only or suspended shop can be looked at but not changed. Paying, exporting, signing in
# and out, and the platform's own pages stay open (allow_while_locked).
module SubscriptionEnforcement
  extend ActiveSupport::Concern

  included do
    before_action :enforce_subscription
  end

  class_methods do
    def allow_while_locked(**options)
      skip_before_action :enforce_subscription, **options
    end
  end

  private
    def enforce_subscription
      return unless Current.account&.locked? && !(request.get? || request.head?)

      message = if Current.account.closing? then "This shop is closing, so nothing can be changed. An owner can cancel the closure in Settings → Your data."
      elsif Current.account.suspended? then "This shop is suspended. Contact HardPoint support."
      else "This shop is read-only until the HardPoint invoice is paid#{" (Billing, in Settings)" if current_membership&.owner?}."
      end
      respond_to do |format|
        format.json { render json: { error: message }, status: :payment_required }
        format.any { redirect_back_or_to root_path, alert: message, status: :see_other }
      end
    end
end
