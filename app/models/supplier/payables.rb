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

  class_methods do
    # { supplier id => balance } for the shop's suppliers, in three grouped queries rather than three per supplier.
    def balances_by_id(account: Current.account)
      invoiced = account.supplier_invoices.group(:supplier_id).sum(:total_cents)
      credited = account.supplier_payments.group(:supplier_id).sum(:amount_cents)
        .merge(account.supplier_returns.group(:supplier_id).sum(:total_cents)) { |_, a, b| a + b }
      (invoiced.keys | credited.keys).index_with { invoiced[_1].to_i - credited[_1].to_i }
    end

    # { supplier id => ageing buckets }, from one query for these suppliers' invoices; settled oldest first, as #open_invoices.
    def ageing_by_id(suppliers, as_of: Date.current, account: Current.account)
      ids = suppliers.map(&:id)
      credited = account.supplier_payments.where(supplier_id: ids).group(:supplier_id).sum(:amount_cents)
        .merge(account.supplier_returns.where(supplier_id: ids).group(:supplier_id).sum(:total_cents)) { |_, a, b| a + b }
      invoices = account.supplier_invoices.where(supplier_id: ids).order(:invoice_date, :id).to_a.group_by(&:supplier_id)

      ids.to_h do |id|
        unapplied = credited[id].to_i
        open = (invoices[id] || []).filter_map do |invoice|
          applied = [ unapplied, invoice.total_cents ].min
          unapplied -= applied
          OpenInvoice.new(invoice, invoice.total_cents - applied) if applied < invoice.total_cents
        end
        [ id, Ageing.buckets_for(open, as_of: as_of) ]
      end
    end
  end

  # Set when balances were worked out for many suppliers at once, so it isn't asked again.
  attr_writer :balance_cents

  # Debit notes for goods sent back count like payments: they come off the oldest invoices.
  def credits_cents
    supplier_payments.sum(:amount_cents) + supplier_returns.sum(:total_cents)
  end

  def balance_cents
    @balance_cents || (supplier_invoices.sum(:total_cents) - credits_cents)
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
