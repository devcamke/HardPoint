# Name → record tables for one import, loaded once instead of per row.
class ProductImport::Lookups
  attr_reader :units, :tax_rates, :default_unit

  def initialize(account)
    @units = index(account.units)
    @units.merge!(account.units.to_h { [ _1.abbreviation.downcase, _1 ] }) { |_, name_match, _| name_match }
    @tax_rates = index(account.tax_rates)
    @default_unit = account.default_unit
  end

  private
    def index(scope)
      scope.to_h { [ _1.name.downcase, _1 ] }
    end
end
