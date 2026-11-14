# Decides what each piece of a cut-to-length product is cut from, at one branch. Called inside
# Product#move_stock's transaction with the branch's stock level locked, so the rack is read and changed one
# movement at a time.
#
# A piece comes from the shortest offcut (or part length) that's long enough, so short pieces get used up, and
# only then from a full length. What's left of the piece it was cut from stays as an offcut, or is scrap when it's
# shorter than the product's scrap_below. Longer pieces are placed first.
class Product::Cutting
  # One cut, or `count` identical ones: `length` taken from a :full length, an :offcut or the :part length that was
  # `from_length` long, leaving `kept` on the rack or `scrap` in the bin. :unlisted is a piece nothing on record
  # was long enough for (an offline till's sale, already made).
  Cut = Data.define(:length, :from, :from_length, :kept, :scrap, :count) do
    def quantity = length * count
    def whole? = from == :full && length == from_length
  end

  Lengths = Data.define(:full, :part, :offcuts) do
    def longest(stock_length) = full.positive? ? stock_length : [ part, *offcuts ].max
  end

  # A piece nothing on the rack is long enough for.
  TooLong = Data.define(:product, :branch, :length, :longest) do
    def message
      return Product.shortage_message(product, 0, branch) unless longest.to_d.positive?

      "No piece of #{product.name} at #{branch.name} is long enough to cut #{product.length_words(length)}: the longest is #{product.length_words(longest)}"
    end

    def record
      branch.account.stock_refusals.create!(branch: branch, product: product, user: Current.user, quantity: length, on_hand: longest.to_d)
    end
  end

  Stick = Struct.new(:record, :length, :kind)

  def initialize(product, branch)
    @product = product
    @branch = branch
  end

  def lengths
    offcuts = @product.offcuts.where(branch: @branch).shortest_first.pluck(:length)
    full, part = [ @product.stock_at(@branch) - offcuts.sum, 0 ].max.divmod(@product.stock_length)
    Lengths.new(full.to_i, part, offcuts)
  end

  # The first piece that can't be cut from what's here, or nil when they all can. Nothing changes.
  def shortfall(pieces)
    plan(pieces).second
  end

  # Cuts the pieces: offcuts are used, shortened and made, and the cuts come back for the ledger. A piece nothing
  # is long enough for raises Product::NoPieceLongEnough, unless `unlisted` lets it through as it is.
  def take(pieces, unlisted: false)
    cuts, short, sticks, records = plan(pieces, unlisted: unlisted)
    raise Product::NoPieceLongEnough, short.message if short

    (records - sticks.filter_map(&:record)).each(&:destroy!)
    sticks.select { _1.kind == :offcut }.each do |stick|
      if stick.record
        stick.record.update!(length: stick.length) if stick.record.length != stick.length
      else
        @product.offcuts.create!(account: @product.account, branch: @branch, length: stick.length)
      end
    end
    cuts
  end

  # Pieces coming back (a void, a return) go on the rack as they are: anything shorter than a full length is an offcut.
  def put_back(pieces)
    pieces.select { _1 < @product.stock_length }.each do |length|
      @product.offcuts.create!(account: @product.account, branch: @branch, length: length)
    end
  end

  # After stock left some other way (a transfer, a count, a write-off): the offcuts can't add up to more than is
  # there, so the shortest are dropped from the list until they fit.
  def trim(on_hand)
    offcuts = @product.offcuts.where(branch: @branch).shortest_first.to_a
    excess = offcuts.sum(&:length) - [ on_hand, 0 ].max
    offcuts.each do |offcut|
      break unless excess.positive?
      offcut.destroy!
      excess -= offcut.length
    end
  end

  # For the ledger and the yard: "2.5 m cut from a 6 m length, leaving a 3.5 m offcut".
  def describe(cut)
    words = ->(length) { @product.length_words(length) }
    text = if cut.whole?
      "#{cut.count} full #{"length".pluralize(cut.count)} of #{words.(cut.length)}"
    elsif cut.from == :unlisted
      "#{words.(cut.length)}: no piece on record was long enough"
    elsif cut.length == cut.from_length
      "the #{words.(cut.length)} #{cut.from == :part ? "part length" : "offcut"}"
    else
      "#{words.(cut.length)} cut from a #{words.(cut.from_length)} #{{ full: "length", offcut: "offcut", part: "part length" }[cut.from]}"
    end
    text += ", leaving a #{words.(cut.kept)} #{cut.from == :part ? "part length" : "offcut"}" if cut.kept.positive?
    text += ", #{words.(cut.scrap)} scrap" if cut.scrap.positive?
    cut.count > 1 && !cut.whole? ? "#{cut.count} × #{text}" : text.upcase_first
  end

  private
    # [ cuts, the first piece that doesn't fit (or nil), the rack afterwards, the offcut records it started with ]
    def plan(pieces, unlisted: false)
      records = @product.offcuts.where(branch: @branch).shortest_first.lock.to_a
      full, part = [ @product.stock_at(@branch) - records.sum(&:length), 0 ].max.divmod(@product.stock_length)
      full = full.to_i
      sticks = records.map { Stick.new(_1, _1.length, :offcut) }
      sticks << Stick.new(nil, part, :part) if part.positive?
      cuts = []

      pieces.map(&:to_d).sort.reverse_each do |piece|
        stick = sticks.select { _1.length >= piece }.min_by(&:length) unless piece == @product.stock_length && full.positive?
        if stick
          from, left = stick.length, stick.length - piece
          kept = left >= @product.scrap_below ? left : 0
          stick.length = kept
          sticks.delete(stick) if kept.zero?
          cuts << [ piece, stick.kind, from, kept, left - kept ]
        elsif full.positive?
          full -= 1
          left = @product.stock_length - piece
          kept = left >= @product.scrap_below ? left : 0
          sticks << Stick.new(nil, kept, :offcut) if kept.positive?
          cuts << [ piece, :full, @product.stock_length, kept, left - kept ]
        elsif unlisted
          cuts << [ piece, :unlisted, 0, 0, 0 ]
        else
          longest = [ *sticks.map(&:length), 0 ].max
          return [ cuts, TooLong.new(@product, @branch, piece, longest), sticks, records ]
        end
      end

      grouped = cuts.tally.map { |cut, count| Cut.new(*cut, count) }
      [ grouped, nil, sticks, records ]
    end
end
