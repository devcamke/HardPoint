# Resolves the shop from the request's subdomain (acme.hardpoint.app → "acme") and scopes
# the request to it. Tenant data must always be reached through Current.account's
# associations; row-level security in Postgres backs this up.
module AccountScoped
  extend ActiveSupport::Concern

  included do
    before_action :require_account
    around_action :use_account_time_zone, if: -> { Current.account }
  end

  class_methods do
    def allow_unscoped_access(**options)
      skip_before_action :require_account, **options
    end
  end

  private
    def require_account
      if account = Account.find_by(subdomain: request.subdomain)
        Current.account = account
      else
        render file: Rails.public_path.join("404.html"), status: :not_found, layout: false
      end
    end

    def use_account_time_zone(&)
      Time.use_zone(Current.account.time_zone, &)
    end
end
