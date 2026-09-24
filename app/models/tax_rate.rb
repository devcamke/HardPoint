class TaxRate < ApplicationRecord
  include AccountOwned, Eventable
  tracks_lifecycle

  has_many :products, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: { scope: :account_id }
  validates :rate, numericality: { greater_than_or_equal_to: 0, less_than: 100 }

  after_save :clear_other_defaults, if: -> { saved_change_to_default? && default? }

  scope :alphabetically, -> { order(:name) }

  def to_s
    "#{name} (#{rate.to_s("F").delete_suffix(".0")}%)"
  end

  private
    def clear_other_defaults
      account.tax_rates.where.not(id: id).update_all(default: false)
    end
end
