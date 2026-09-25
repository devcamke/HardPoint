# A manager correcting a customer's points (a goodwill gesture, a mistake), always with a reason.
class Customers::LoyaltyAdjustmentsController < ApplicationController
  before_action :ensure_approver

  def create
    customer = Current.account.customers.find(params[:customer_id])
    points = params[:points].to_i
    points = -customer.points_balance if points.negative? && -points > customer.points_balance
    entry = customer.loyalty_entries.new(account: Current.account, kind: "adjusted", points: points, note: params[:note].to_s.squish.presence)

    if entry.save
      customer.track_event "points_adjusted", points: points, note: entry.note, balance: customer.points_balance
      redirect_to customer, notice: "#{points.positive? ? "Added" : "Took off"} #{points.abs} points. Balance #{customer.points_balance}."
    else
      redirect_to customer, alert: entry.errors.full_messages.to_sentence
    end
  end

  private
    def ensure_approver
      head :forbidden unless current_membership&.approver?
    end
end
