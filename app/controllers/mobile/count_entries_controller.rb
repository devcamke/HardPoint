# A quantity counted. "Add" suits counting the same product in several places (the shelf, the
# store room, the yard), and two people can add to one product at once; "Set" corrects a total.
class Mobile::CountEntriesController < Mobile::BaseController
  include StockCountScoped
  before_action :ensure_can_manage_stock
  before_action :ensure_still_counting

  def create
    @line = @count.lines.includes(product: :unit).find(params[:line_id])
    amount = entered_quantity(@line.product)

    if amount.negative? || !@line.product.quantity_allowed?(amount)
      @error = "#{@line.product.unit.name.capitalize} can only be counted in whole numbers" if amount >= 0
      @error ||= "Enter a quantity of 0 or more"
    elsif params[:mode] == "set"
      @line.update!(counted_quantity: amount)
    else
      StockCountLine.where(id: @line.id).update_all([ "counted_quantity = COALESCE(counted_quantity, 0) + ?, updated_at = ?", amount, Time.current ])
    end

    @line.reload
    @added = amount unless params[:mode] == "set"
    @recent = @count.lines.counted.includes(product: :unit).order(updated_at: :desc).limit(8)
    render status: @error ? :unprocessable_entity : :ok
  end

  private
    def ensure_still_counting
      head :conflict unless @count.counting?
    end
end
