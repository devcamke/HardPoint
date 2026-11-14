class Pos::LinesController < ApplicationController
  include PosSale

  # A scan or a tap. Pack barcodes add the pack; everything else adds one of the product.
  def create
    product, product_unit = find_product
    return render_cart(alert: "Nothing found for “#{params[:code]}”", status: :unprocessable_entity) unless product

    line = @sale.add(product, product_unit: product_unit, **quantity_and_cut(product, product_unit))
    if line.errors.any?
      render_cart alert: line.errors.full_messages.to_sentence, status: :unprocessable_entity
    else
      render_cart message: stock_warning(line)
    end
  end

  def update
    line = @sale.lines.find(params[:id])
    line.assign_attributes(line_params)
    line.reprice if line.quantity_changed? || line.product_unit_id_changed?
    if (takes_more_stock?(line) || line.cut_length_changed?) && (shortage = @sale.stock_shortfall(@sale.lines.map { _1.id == line.id ? line : _1 }, only: line))
      shortage.record
      return render_cart alert: shortage.message, status: :unprocessable_entity
    end

    SaleLine.transaction do
      line.save!
      @sale.recalculate
      keep_what_is_paid!
      approve_discount!
    end
    render_cart message: stock_warning(line)
  rescue ActiveRecord::RecordInvalid, ApprovalMissing, PaidAlready => error
    render_cart alert: error.message, status: :unprocessable_entity
  end

  def destroy
    line = @sale.lines.find(params[:id])
    SaleLine.transaction do
      line.destroy!
      @sale.recalculate
      keep_what_is_paid!
      approve_discount!
    end
    render_cart message: "Removed #{line.product.name}"
  rescue ApprovalMissing, PaidAlready => error
    render_cart alert: error.message, status: :unprocessable_entity
  end

  private
    def find_product
      code = params[:code].to_s.strip
      if params[:product_id].present?
        product = Current.account.products.active.find(params[:product_id])
        [ product, product.product_units.find_by(id: params[:product_unit_id]) ]
      elsif (barcode = Current.account.barcodes.includes(:product, :product_unit).find_by(code: code))
        [ barcode.product, barcode.product_unit ]
      else
        [ Current.account.products.active.find_by(sku: code.upcase), nil ]
      end
    end

    # A product cut to length goes on as so many pieces of a length each: one full length unless the cashier says.
    # Anything else is a plain quantity.
    def quantity_and_cut(product, product_unit)
      return { quantity: params[:quantity].presence || 1 } unless product.cut_to_length? && product_unit.nil? && (params[:cut_length].present? || params[:quantity].blank?)

      cut_length = params[:cut_length].presence&.to_d || product.stock_length
      { quantity: pieces_param(params[:pieces]) * cut_length, cut_length: cut_length }
    end

    def pieces_param(value)
      [ value.to_i, 1 ].max
    end

    def line_params
      permitted = params.expect(sale_line: %i[ quantity product_unit_id discount serial_number cut_length ])
      if permitted.key?(:product_unit_id)
        permitted[:product_unit_id] = permitted[:product_unit_id].presence && Current.account.product_units.find(permitted[:product_unit_id]).id
      end
      # "3 pieces of 2.5 m" is a quantity of 7.5.
      if permitted[:cut_length].to_d.positive?
        permitted[:quantity] = pieces_param(params.dig(:sale_line, :pieces)) * permitted[:cut_length].to_d
      elsif permitted.key?(:cut_length)
        permitted[:cut_length] = nil
      end
      permitted
    end

    # Raising the quantity, or switching to a bigger pack, takes more off the shelf; lowering it never needs stock.
    def takes_more_stock?(line)
      return false unless line.quantity_changed? || line.product_unit_id_changed?

      pack_was = Current.account.product_units.find_by(id: line.product_unit_id_was)&.quantity || 1
      line.base_quantity > line.quantity_was.to_d * pack_was
    end

    def stock_warning(line)
      return unless line.product.track_stock? || line.product.kit?

      on_hand, available = line.stock_on_hand, line.stock_available
      if available < line.quantity && available < on_hand
        "Only #{helpers.quantity(available)} #{line.product.name} free here: #{helpers.quantity(on_hand - available)} of the #{helpers.quantity(on_hand)} in stock are promised to orders"
      elsif on_hand < line.quantity
        "Only #{helpers.quantity(on_hand)} #{line.product.name} in stock here"
      end
    end
end
