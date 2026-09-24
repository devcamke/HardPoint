class Etims::ItemRegistration < ApplicationRecord
  include AccountOwned

  belongs_to :device
  belongs_to :product
end
