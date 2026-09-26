# One stored upload object. Direct (S3/R2) uploads start "pending" and become
# "complete" only after UploadsController#complete has verified the stored object;
# streamed (Disk) uploads are verified before they are stored and start "complete".
class Upload < ApplicationRecord
  STATUSES = %w[pending complete].freeze
  STORAGES = %w[s3 disk].freeze
  MAX_SIZE = 100.megabytes
  STALE_AFTER = 24.hours

  belongs_to :user, optional: true

  validates :storage, inclusion: { in: STORAGES }
  validates :status, inclusion: { in: STATUSES }
  validates :key, :filename, presence: true
  validates :content_type, inclusion: { in: MediaTypeSniffer::ALLOWED_TYPES }
  validates :byte_size, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_SIZE }

  scope :complete, -> { where(status: "complete") }
  scope :pending, -> { where(status: "pending") }

  def self.sanitize_filename(name)
    base = File.basename(name.to_s).gsub(/[^A-Za-z0-9_.-]/, "_").gsub(/\A[._]+/, "").last(120)
    base.presence || "upload-#{SecureRandom.hex(6)}"
  end

  # Uploads no portfolio item points at (by url, thumbnail or waveform).
  def self.unreferenced
    where(<<~SQL.squish)
      uploads.public_url IS NULL OR NOT EXISTS (
        SELECT 1 FROM portfolio_items p
        WHERE p.url = uploads.public_url OR p.thumbnail_url = uploads.public_url OR p.waveform_url = uploads.public_url
      )
    SQL
  end

  def complete? = status == "complete"

  def referenced?
    public_url.present? && PortfolioItem.where(url: public_url).or(PortfolioItem.where(thumbnail_url: public_url)).or(PortfolioItem.where(waveform_url: public_url)).exists?
  end

  # Deletes the stored object, then the row. Safe to repeat.
  def purge!
    UploadStorage.delete(storage, key)
    destroy!
  end

  def api_json = { id:, url: public_url, status:, contentType: content_type, byteSize: byte_size, filename: }
end
