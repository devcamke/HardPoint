# What the shop owes a supplier. Payments and debit notes for returns settle the oldest invoices
# first (FIFO), which is how suppliers read their statements and what the ageing report is based on.
module Supplier::Payables
  extend ActiveSupport::Concern
  include Ageing

  OpenInvoice = Data.define(:invoice, :outstanding_cents) do
    def days_overdue(as_of = Date.current) = (as_of - invoice.due_date).to_i
  end

  included do
    has_many :supplier_invoices, dependent: :restrict_with_error
    has_many :supplier_payments, dependent: :restrict_with_error
    has_many :supplier_returns, dependent: :restrict_with_error
  end

  # Debit notes for goods sent back count like payments: they come off the oldest invoices.
  def credits_cents
    supplier_payments.sum(:amount_cents) + supplier_returns.sum(:total_cents)
  end

  def balance_cents
    supplier_invoices.sum(:total_cents) - credits_cents
  end

  def open_invoices
    unapplied = credits_cents

    supplier_invoices.order(:invoice_date, :id).filter_map do |invoice|
      applied = [ unapplied, invoice.total_cents ].min
      unapplied -= applied
      OpenInvoice.new(invoice, invoice.total_cents - applied) if applied < invoice.total_cents
    end
  end
end
