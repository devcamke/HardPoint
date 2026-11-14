# Stands in for KRA on a "simulator" device (demo shops and development), answering like OSCU.
class Etims::Simulator
  def initialize(device)
    @device = device
  end

  def request(_method, url, json: {}, **)
    data = case URI(url).path.delete_prefix("/etims-api")
    when "/selectInitOsdcInfo"
      { info: { tin: @device.tin, bhfId: @device.bhf_id, sdcId: "KRACU0300000#{@device.id.to_s.rjust(3, "0")}", mrcNo: "WIS01000#{@device.id.to_s.rjust(4, "0")}",
                cmcKey: SecureRandom.hex(16).upcase } }
    when "/saveTrnsSalesOsdc"
      { curRcptNo: json[:invcNo], totRcptNo: json[:invcNo], intrlData: SecureRandom.alphanumeric(26).upcase,
        rcptSign: SecureRandom.alphanumeric(16).upcase, sdcDateTime: Time.current.in_time_zone("Nairobi").strftime("%Y%m%d%H%M%S") }
    when "/selectTrnsPurchaseSalesList"
      { saleList: purchases }
    end
    JsonHttp::Response.new(200, { "resultCd" => "000", "resultMsg" => "It is succeeded", "data" => data&.deep_stringify_keys })
  end

  private
    # Two invoices a day, made up from the shop's own catalogue so they look like its buying: one from a supplier it
    # knows (by KRA PIN, when one has a PIN) for things it stocks, and one from a stranger with a line that matches
    # nothing. Numbered by the day, so asking twice brings nothing new.
    def purchases
      account = @device.account
      today = Time.current.in_time_zone("Nairobi")
      supplier = account.suppliers.where.not(tax_pin: [ nil, "" ]).order(:id).first
      products = (supplier&.products&.where(track_stock: true, kit: false, tracks_batches: false)&.order(:id)&.limit(3).to_a.presence ||
        account.products.active.where(track_stock: true, kit: false, tracks_batches: false).order(:id).limit(3).to_a)
      stocked = products.each_with_index.map { |product, index| item(index + 1, product.name, [ 20, 50, 10 ][index], (product.cost_cents * 1.16).round, barcode: product.barcodes.first&.code) }
      delivery = [ item(1, "Transport to site", 1, 3_500_00), item(2, "Binding wire 25kg roll", 4, 4_800_00) ]

      [ invoice(supplier&.tax_pin || "P051999888Z", supplier&.name || "Simba Cement Ltd", "SIM-#{today.strftime("%y%m%d")}-1", today, stocked),
        invoice("P052777666K", "Rift Valley Steel Mills Ltd", "SIM-#{today.strftime("%y%m%d")}-2", today, delivery) ].select { _1[:itemList].any? }
    end

    def item(sequence, name, quantity, price_cents, barcode: nil)
      total = price_cents * quantity
      tax = (total * 16 / 116.0).round
      { itemSeq: sequence, itemCd: "KE2NTU#{name.hash.abs.to_s.first(7).rjust(7, "0")}", itemNm: name, bcd: barcode, qtyUnitCd: "U", qty: quantity, prc: price_cents / 100.0,
        splyAmt: total / 100.0, taxTyCd: "B", taxblAmt: total / 100.0, taxAmt: tax / 100.0, totAmt: total / 100.0 }
    end

    def invoice(tin, name, number, time, items)
      { spplrTin: tin, spplrNm: name, spplrBhfId: "00", spplrInvcNo: number, rcptTyCd: "S", pmtTyCd: "02", cfmDt: time.strftime("%Y%m%d%H%M%S"), salesDt: time.strftime("%Y%m%d"),
        totItemCnt: items.size, totTaxblAmt: items.sum { _1[:taxblAmt] }.round(2), totTaxAmt: items.sum { _1[:taxAmt] }.round(2), totAmt: items.sum { _1[:totAmt] }.round(2), itemList: items }
    end
end
