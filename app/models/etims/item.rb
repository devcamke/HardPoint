# A product as KRA registers it. Item codes follow KRA's pattern: country, item type (2 goods,
# 3 services), packaging unit, quantity unit, then a 7-digit number (the product's ID).
class Etims::Item
  def initialize(product, device)
    @product = product
    @device = device
  end

  def self.code_for(product)
    unit = (product.unit.etims_code.presence || "U").ljust(2, "X").first(2)
    "KE#{type_for(product)}NT#{unit}#{product.id.to_s.rjust(7, "0")}"
  end

  def self.type_for(product)
    product.track_stock? || product.kit? ? "2" : "3"
  end

  def to_h
    { itemCd: self.class.code_for(@product), itemClsCd: class_code, itemTyCd: self.class.type_for(@product), itemNm: @product.name,
      orgnNatCd: "KE", pkgUnitCd: "NT", qtyUnitCd: @product.unit.etims_code.presence || "U",
      taxTyCd: Etims.tax_type_for(@product.account, @product.effective_tax_rate&.rate || 0),
      bcd: @product.barcodes.first&.code, dftPrc: @product.price_cents / 100.0, isrcAplcbYn: "N", useYn: "Y",
      regrId: "HardPoint", regrNm: "HardPoint", modrId: "HardPoint", modrNm: "HardPoint" }
  end

  private
    def class_code
      @product.category&.etims_class_code.presence || @device.default_item_class_code
    end
end
