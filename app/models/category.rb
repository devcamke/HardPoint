class Category < ApplicationRecord
  include AccountOwned, Eventable
  tracks_lifecycle

  belongs_to :parent, class_name: "Category", optional: true
  has_many :children, class_name: "Category", foreign_key: :parent_id, dependent: :restrict_with_error
  has_many :products, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: { scope: :account_id }
  validates_same_account :parent
  validates :etims_class_code, format: { with: /\A\d{8,10}\z/, message: "must be KRA's 8–10 digit code" }, allow_blank: true
  validate { errors.add :parent, "can't be the category itself" if parent_id.present? && parent_id == id }

  scope :alphabetically, -> { order(:name) }

  def full_name
    parent ? "#{parent.name} › #{name}" : name
  end
end
