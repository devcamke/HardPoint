# Settings › Loyalty points: switching the scheme on, how points are earned and what they're worth,
# when they expire and whether customers are texted about them.
class LoyaltyProgramsController < ApplicationController
  before_action :ensure_approver
  before_action :set_program

  def edit
    @members = Current.account.loyalty_entries.distinct.count(:customer_id)
    @top = Current.account.customers.joins(:loyalty_entries).group("customers.id").order(Arel.sql("SUM(loyalty_entries.points) DESC"))
      .limit(10).pluck("customers.id", "customers.name", Arel.sql("SUM(loyalty_entries.points)"))
    @expired = Current.account.loyalty_entries.where(kind: "expired", created_at: 1.year.ago..).sum(:points).abs
    @expiring = @program.expires? ? @program.points_expiring_this_month.values.sum : 0
  end

  def update
    if @program.update(program_params)
      redirect_to edit_loyalty_program_path, notice: @program.enabled? ? "Loyalty points are on." : "Loyalty points are off. Balances are kept."
    else
      edit
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def ensure_approver
      head :forbidden unless current_membership&.approver?
    end

    def set_program
      @program = Current.account.loyalty_program || Current.account.build_loyalty_program
    end

    def program_params
      params.expect(loyalty_program: %i[ enabled points_per_100 point_value min_redeem_points expiry_months text_points ])
    end
end
