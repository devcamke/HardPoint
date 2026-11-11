# The choices that tune how HardPoint works for this shop (Account::Preferences): quotes and customers, the till's
# payment buttons, stock warnings, and what quotes, invoices and statements say.
class PreferencesController < ApplicationController
  before_action :ensure_can_manage_account

  FIELDS = %w[ quote_validity_days customer_payment_terms_days expiry_warning_days dead_stock_days reorder_lookback_days
               supplier_lead_time_days document_terms payment_details credit_hold_after_days weekly_reminders ].freeze

  def edit
    @account = Current.account
  end

  def update
    @account = Current.account
    submitted = params.expect(account: [ *FIELDS, till_tenders: [] ])
    FIELDS.each { |field| @account.public_send(:"#{field}=", submitted[field]) if submitted.key?(field) }
    @account.till_tenders = submitted[:till_tenders] || []

    if @account.save
      redirect_to edit_preferences_path, notice: "Preferences saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end
end
