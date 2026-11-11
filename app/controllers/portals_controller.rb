# A customer's own page at the shop (see PortalLink): what they owe, their open invoices and quotes, recent payments,
# statements, and paying with M-Pesa (PortalPaymentsController). Every document is looked up among this customer's own.
class PortalsController < ApplicationController
  include PortalAccess

  PERIODS = { "this_month" => "This month", "last_month" => "Last month", "last_3_months" => "The last 3 months", "this_year" => "This year" }.freeze

  def show
    @customer.remember_balance
    @open_invoices = @customer.open_invoices
    @overdue_cents = @customer.overdue_cents(invoices: @open_invoices)
    @quotes = @customer.customer_orders.where(status: "quote").chronologically.limit(10).reject(&:expired?)
    @orders = @customer.customer_orders.open.chronologically.limit(10)
    @payments = @customer.customer_payments.payments.chronologically.limit(5)
    @waiting = @customer.stk_requests.pending.where(created_at: Mpesa::StkRequest::EXPIRES_AFTER.ago..).last
  end

  def statement
    from, to = period(params[:period])
    pdf = StatementPdf.new(@customer.statement(from: from, to: to), branch: Current.account.branches.alphabetically.first)
    send_data pdf.render, filename: pdf.filename, type: :pdf, disposition: :inline
  end

  def invoice
    sale = @customer.sales.where(status: "completed").find(params[:id])
    pdf = SaleInvoicePdf.new(sale)
    send_data pdf.render, filename: pdf.filename, type: :pdf, disposition: :inline
  end

  def quote
    order = @customer.customer_orders.where(status: %w[ quote ordered ready ]).find(params[:id])
    pdf = CustomerOrderPdf.new(order)
    send_data pdf.render, filename: pdf.filename, type: :pdf, disposition: :inline
  end

  private
    def period(key)
      today = Date.current
      case key
      when "last_month" then [ today.prev_month.beginning_of_month, today.prev_month.end_of_month ]
      when "last_3_months" then [ (today << 2).beginning_of_month, today ]
      when "this_year" then [ today.beginning_of_year, today ]
      else [ today.beginning_of_month, today ]
      end
    end
end
