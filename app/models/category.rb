class Category < ApplicationRecord
  include AccountOwned, Eventable
  tracks_lifecycle

  belongs_to :parent, class_name: "Category", optional: true
  has_many :children, class_name: "Category", foreign_key: :parent_id, dependent: :restrict_with_error
  has_many :products, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: { scope: :account_id }
  validates_same_account :parent
  validate { errors.add :parent, "can't be the category itself" if parent_id.present? && parent_id == id }

  scope :alphabetically, -> { order(:name) }

  def full_name
    parent ? "#{parent.name} › #{name}" : name
  end
end
