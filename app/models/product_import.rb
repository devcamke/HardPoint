# Loads or updates products from a CSV in two background steps: check (validate every row and
# show a preview) and, once someone confirms, run. Rows are matched to existing products by SKU.
# The optional stock column sets the quantity on hand at the chosen branch.
class ProductImport < ApplicationRecord
  include AccountOwned, Eventable

  MAX_SIZE = 10.megabytes
  MAX_PROBLEMS = 200
  BATCH_SIZE = 500

  belongs_to :creator, class_name: "User", default: -> { Current.user }, optional: true
  belongs_to :branch, optional: true

  enum :status, %w[ checking needs_fixing ready importing completed failed ].index_by(&:itself), default: :checking

  validates :csv, presence: true
  validates :csv, length: { maximum: MAX_SIZE, message: "file is too big (10 MB at most)" }
  validates_same_account :branch
  validate :has_name_column, on: :create

  after_create_commit :check_later
  scope :chronologically, -> { order(created_at: :desc, id: :desc) }

  def name
    filename.presence || "Import ##{id}"
  end

  def check_later
    ProductImportCheckJob.perform_later(self)
  end

  def run_later
    ProductImportRunJob.perform_later(self) if ready? && update(status: :importing)
  end

  def check
    Check.new(self).perform
  end

  def run
    Run.new(self).perform
  rescue => error
    update_columns status: "failed", problems: [ { "line" => nil, "messages" => [ "Import stopped: #{error.message}" ] } ]
    raise
  end

  def rows
    CSV.parse(csv, headers: true, header_converters: ->(header) { header.to_s.strip.downcase.tr(" ", "_") }, skip_blanks: true)
  end

  private
    def has_name_column
      headers = CSV.parse_line(csv.to_s.lines.first.to_s)&.map { _1.to_s.strip.downcase } || []
      errors.add :csv, "needs at least “name” and “price” columns (see the template)" unless (%w[ name price ] - headers).empty?
    rescue CSV::MalformedCSVError => error
      errors.add :csv, "couldn't be read: #{error.message}"
    end
end
