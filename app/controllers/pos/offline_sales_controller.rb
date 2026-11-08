# Sales rung up while the till was offline, sent when it's back. Each is recorded once however
# many times it's sent; the answer says what happened to each, so the till can let them go.
class Pos::OfflineSalesController < ApplicationController
  allow_while_locked
  before_action :ensure_can_sell
  rate_limit to: 60, within: 1.minute, only: :create, by: -> { cookies.signed[:session_id] || request.remote_ip } # per till, not per shop

  MAX_PER_REQUEST = 50

  # A fresh form token for the upload: the page the till was offline with may be hours old.
  def new
    render json: { token: form_authenticity_token }
  end

  def create
    return render(json: { error: "Choose this device's till first" }, status: :unprocessable_entity) unless current_till

    sales = Array(params.to_unsafe_h[:sales]).first(MAX_PER_REQUEST)
    results = sales.map { Current.account.sales.record_offline(_1, register: current_till) }
    render json: { results: results }
  end
end
