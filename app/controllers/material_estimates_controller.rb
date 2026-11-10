# The material calculator. The form holds the job's parts (walls, concrete, roofing…); each press works out the
# materials again, and "Make a quote" turns them into a quote for the customer at today's prices. Nothing is
# saved until then: the parts travel with the form.
class MaterialEstimatesController < ApplicationController
  MAX_PARTS = 20

  before_action :ensure_can_sell

  def new
    @parts = [ { "kind" => "wall" } ]
    @estimate = MaterialCalculator::Estimate.new(Current.account, @parts)
  end

  def create
    @parts = submitted_parts
    if (kind = params[:add].presence_in(MaterialCalculator::KINDS)) && @parts.size < MAX_PARTS
      @parts << { "kind" => kind }
    elsif params[:remove].present?
      @parts.delete_at(params[:remove].to_i)
    end
    @estimate = MaterialCalculator::Estimate.new(Current.account, @parts)
    @customer = Current.account.customers.find_by(id: params[:customer_id])

    params[:make_quote].present? ? make_quote : render(:new)
  end

  private
    def submitted_parts
      params.fetch(:parts, {}).to_unsafe_h.values.first(MAX_PARTS).map { |values| values.slice("kind", *part_fields(values["kind"])) }
    end

    def part_fields(kind)
      MaterialCalculator.part_class(kind)&.fields&.map(&:name) || []
    end

    def make_quote
      @quote_errors = []
      @quote_errors << "Choose the customer the quote is for" unless @customer
      @quote_errors << "Fill in at least one part" if @estimate.filled_parts.empty?
      @quote_errors << "None of these materials is linked to a product yet" if @estimate.filled_parts.any? && @estimate.lines.none?(&:mapped?)
      return render(:new, status: :unprocessable_entity) if @quote_errors.any?

      quote = @estimate.to_quote(customer: @customer, branch: current_till&.branch || selected_branch || visible_branches.first)
      if quote.save
        redirect_to quote, notice: "Quote #{quote.reference} made from the calculator. Check it, then send it to #{@customer.name}."
      else
        @quote_errors = quote.errors.full_messages
        render :new, status: :unprocessable_entity
      end
    end
end
