# Giving up on a debt: the amount comes off what the customer owes with a reason, approved by a manager
# (at their own screen, or by PIN for an accountant), and it's on the statement and in Activity. It can be
# put against the particular sales being written off, or left to come off the oldest first.
class Customers::WriteOffsController < ApplicationController
  include CustomerPaymentEntries
  before_action :ensure_can_manage_receivables, :set_customer

  def new
    @write_off = @customer.customer_payments.new(kind: "write_off", paid_on: Date.current, amount_cents: [ @customer.balance_cents, 0 ].max)
  end

  def create
    @write_off = build_entry(kind: "write_off", permitted: %i[ paid_on amount reason ])
    @write_off.approver = approver_for_action

    if @write_off.save
      redirect_to @customer, notice: "#{Money.format(@write_off.amount_cents)} written off. #{owed_now}"
    else
      render :new, status: :unprocessable_entity
    end
  end
end
