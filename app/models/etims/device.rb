# A branch's KRA online control unit (OSCU). It's set up once with KRA, which returns the
# communication key used to sign everything after; the key is stored encrypted.
class Etims::Device < ApplicationRecord
  include AccountOwned, Eventable
  tracks_lifecycle only: %i[ create update ]

  ENVIRONMENTS = %w[ sandbox production simulator ].freeze
  VERIFY_URLS = { "production" => "https://etims.kra.go.ke/common/link/etims/receipt/indexEtimsReceiptData?Data=",
                  "sandbox" => "https://etims-sbx.kra.go.ke/common/link/etims/receipt/indexEtimsReceiptData?Data=",
                  "simulator" => "https://etims-sbx.kra.go.ke/common/link/etims/receipt/indexEtimsReceiptData?Data=" }.freeze

  belongs_to :branch
  has_many :submissions, dependent: :restrict_with_error
  has_many :item_registrations, dependent: :delete_all

  encrypts :cmc_key

  normalizes :tin, with: ->(tin) { tin.strip.upcase }

  validates :tin, format: { with: /\A[AP]\d{9}[A-Z]\z/, message: "must be a KRA PIN like P051234567X" }
  validates :bhf_id, format: { with: /\A\d{2}\z/, message: "must be the 2-digit branch ID KRA gave (00 for the head office)" }
  validates :serial_number, presence: true
  validates :environment, inclusion: { in: ENVIRONMENTS }
  validates :branch, uniqueness: { message: "already has a control unit" }
  validates :default_item_class_code, format: { with: /\A\d{8,10}\z/ }
  validate { errors.add :environment, "can't be the simulator on a live server" if environment == "simulator" && !Mpesa::Shortcode.simulator_allowed? }
  validates_same_account :branch

  scope :active, -> { where(active: true) }

  def self.for_branch(branch)
    active.find_by(branch: branch)
  end

  def simulator? = environment == "simulator"
  def initialized? = cmc_key.present?

  def name
    "#{branch.name} control unit"
  end

  def client
    Etims::Client.new(self)
  end

  def initialize_with_kra
    info = client.initialize_device
    update!(cmc_key: info["cmcKey"], sdc_id: info["sdcId"], mrc_no: info["mrcNo"], initialized_at: Time.current)
    track_event "initialized", sdc_id: sdc_id
  end

  # KRA needs every item on an invoice registered first, once per control unit.
  def register(product)
    return if item_registrations.exists?(product: product)

    client.save_item(Etims::Item.new(product, self).to_h)
    item_registrations.create!(account: account, product: product)
  end

  # Always KRA's own https address; the signature KRA returned is reduced to letters and digits.
  def verification_url(receipt_signature)
    "#{VERIFY_URLS.fetch(environment)}#{tin}#{bhf_id}#{receipt_signature.to_s.gsub(/[^A-Za-z0-9]/, "")}"
  end
end
