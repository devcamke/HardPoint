# A full copy of a shop's data for its owner: a ZIP of CSV files (one per kind of record) plus
# product images and delivery photos. Built in the background, kept for a week.
class AccountExport < ApplicationRecord
  RETENTION = 7.days

  belongs_to :account, default: -> { Current.account }
  belongs_to :requested_by, class_name: "User", default: -> { Current.user }
  has_one_attached :file

  enum :status, %w[ pending ready failed expired ].index_by(&:itself), default: "pending"

  scope :chronologically, -> { order(created_at: :desc) }

  after_create_commit -> { AccountExportJob.perform_later(self) }

  def build
    Tempfile.create([ "export", ".zip" ], binmode: true) do |zip_file|
      AccountExport::Archive.new(account).write(zip_file.path)
      file.attach(io: File.open(zip_file.path), filename: filename, content_type: "application/zip")
    end
    update!(status: :ready, expires_at: RETENTION.from_now)
    AccountExportsMailer.with(export: self).ready.deliver_later
  rescue StandardError => error
    update!(status: :failed, failure: error.message.first(250))
    raise
  end

  def filename
    "hardpoint-#{account.subdomain}-#{created_at.in_time_zone(account.time_zone).to_date.iso8601}.zip"
  end

  def downloadable?
    ready? && file.attached? && expires_at&.future?
  end

  # Deletes exports past their week. Runs daily, across shops.
  def self.expire_old
    Account.without_isolation do
      ready.where(expires_at: ..Time.current).includes(:account).find_each do |export|
        Current.set(account: export.account) do
          export.file.purge
          export.update!(status: :expired)
        end
      end
    end
  end
end
