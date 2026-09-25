# Tagging the sale on the till with one of the customer's open jobs, so it counts towards that job.
class Pos::JobsController < ApplicationController
  include PosSale

  def update
    job = params[:job_id].presence && Current.account.jobs.open.where(customer: @sale.customer).find(params[:job_id])

    if @sale.customer_order&.job && job != @sale.customer_order.job
      render_cart alert: "This sale is for order #{@sale.customer_order.reference}, which is for #{@sale.customer_order.job.label}", status: :unprocessable_entity
    elsif @sale.update(job: job)
      render_cart message: job ? "For #{job.label}#{budget_note(job)}" : "Not for a job"
    else
      render_cart alert: @sale.errors.full_messages.to_sentence, status: :unprocessable_entity
    end
  end

  private
    def budget_note(job)
      left = job.budget_left_cents
      return "" unless left
      left.negative? ? " · #{Money.format(-left)} over budget" : " · #{Money.format(left)} of budget left"
    end
end
