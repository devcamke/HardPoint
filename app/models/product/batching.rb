# Decides which batches a stock movement of a batch-tracked product touches, as [batch, quantity]
# portions (a nil batch is stock not in any batch). Called inside Product#move_stock's transaction,
# with the branch's stock level locked, so batches are read and changed one movement at a time.
class Product::Batching
  def initialize(product, branch)
    @product = product
    @branch = branch
  end

  def portions(quantity, batch: nil, reverses: nil)
    return [ [ nil, quantity ] ] if quantity.zero?

    if batch
      [ [ batch_for(batch), quantity ] ]
    elsif quantity.positive?
      reverses ? putting_back(quantity, **reverses) : [ [ nil, quantity ] ]
    else
      taking_out(-quantity)
    end
  end

  private
    # Stock not in a batch goes first (it's what was on the shelf before batches were tracked),
    # then batches by expiry date, skipping expired ones unless nothing else is left.
    def taking_out(amount)
      batches = @product.stock_batches.where(branch: @branch).in_stock.by_expiry.lock.to_a
      expired, good = batches.partition(&:expired?)
      unbatched = @product.stock_at(@branch) - batches.sum(&:quantity)

      portions = []
      if unbatched.positive?
        portions << [ nil, -[ unbatched, amount ].min ]
        amount -= unbatched
      end
      (good + expired).each do |batch|
        break unless amount.positive?
        take = [ batch.quantity, amount ].min
        portions << [ batch, -take ]
        amount -= take
      end
      portions << [ nil, -amount ] if amount.positive?
      portions
    end

    # Back into the batches it was taken from (by number, so a transfer recreates them at the
    # other branch), less whatever has already gone back.
    def putting_back(amount, taken_by:, returned_by: taken_by)
      taken = batched_movements(taken_by).where("stock_movements.quantity < 0")
        .group("stock_batches.number", "stock_batches.expires_on").sum("-stock_movements.quantity")
      returned = batched_movements(returned_by).where("stock_movements.quantity > 0").group("stock_batches.number").sum(:quantity)

      portions = []
      taken.each do |(number, expires_on), quantity|
        free = quantity - returned.fetch(number, 0)
        next unless free.positive? && amount.positive?

        put = [ free, amount ].min
        portions << [ batch_for(number: number, expires_on: expires_on), put ]
        amount -= put
      end
      portions << [ nil, amount ] if amount.positive?
      portions
    end

    def batched_movements(sources)
      scopes = Array(sources).group_by { _1.class.base_class.name }.map do |type, records|
        StockMovement.where(source_type: type, source_id: records.map(&:id))
      end
      StockMovement.where(product: @product).and(scopes.reduce(:or)).joins(:stock_batch)
    end

    def batch_for(batch)
      if batch.is_a?(StockBatch)
        raise ArgumentError, "Batch #{batch.number} is another product's or branch's" unless batch.product_id == @product.id && batch.branch_id == @branch.id
        return batch.lock!
      end

      record = @product.stock_batches.create_or_find_by!(account: @product.account, branch: @branch, number: batch[:number]) do |created|
        created.expires_on = batch[:expires_on]
      end
      record.lock!
      record.update!(expires_on: batch[:expires_on]) if record.expires_on.nil? && batch[:expires_on]
      record
    end
end
