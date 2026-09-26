class PortfolioItem < ApplicationRecord
  MEDIA_URL_ATTRIBUTES = %w[url thumbnail_url waveform_url].freeze
  # Hosts that serve bucket objects directly; links there must be the user's own upload.
  STORAGE_HOST_SUFFIXES = %w[.r2.cloudflarestorage.com .r2.dev .amazonaws.com].freeze

  belongs_to :user
  attribute :tags, :json, default: -> { [] }
  attribute :genres, :json, default: -> { [] }
  attribute :roles, :json, default: -> { [] }
  attribute :instruments, :json, default: -> { [] }
  attribute :media_metadata, :json, default: -> { {} }
  validates :title, :kind, :url, presence: true
  validates :url, :thumbnail_url, :waveform_url, safe_http_url: true, allow_blank: true
  validate :media_urls_are_external_or_own_uploads

  # Uploaded objects are deleted once no work sample refers to them any more.
  after_update_commit -> { release_uploads(previous_changes.slice(*MEDIA_URL_ATTRIBUTES).values.map(&:first)) }
  after_destroy_commit -> { release_uploads(attributes.values_at(*MEDIA_URL_ATTRIBUTES)) }

  def api_json = attributes.transform_keys { _1.camelize(:lower) }.merge(type: kind)

  def self.storage_url?(value)
    uri = URI.parse(value.to_s)
    host = uri.host.to_s.downcase
    return false if host.empty?
    base_host = UploadStorage.public_base_url && URI.parse(UploadStorage.public_base_url).host.to_s.downcase
    api_host = ENV["API_HOST"].present? ? URI.parse(ENV["API_HOST"]).host.to_s.downcase : nil
    host == base_host ||
      (uri.path.to_s.start_with?("/rails/active_storage/") && (api_host.nil? || host == api_host)) ||
      (STORAGE_HOST_SUFFIXES.any? { host.end_with?(_1) } && uri.path.to_s.include?("/#{UploadStorage::KEY_PREFIX}"))
  rescue URI::InvalidURIError
    false
  end

  private

  def media_urls_are_external_or_own_uploads
    MEDIA_URL_ATTRIBUTES.each do |attribute|
      value = self[attribute].to_s
      next if value.blank? || !will_save_change_to_attribute?(attribute)
      next unless value.match?(%r{\Ahttps?://}i) # other schemes are rejected by SafeHttpUrlValidator

      upload = Upload.find_by(public_url: value)
      if upload || self.class.storage_url?(value)
        next if upload && upload.user_id == user_id && upload.complete?
        errors.add(attribute, "must be one of your own completed uploads")
      elsif !value.match?(%r{\Ahttps://}i)
        errors.add(attribute, "must be an HTTPS link (YouTube, Spotify, SoundCloud or another secure page)")
      end
    end
  end

  def release_uploads(urls)
    urls = urls.compact_blank.uniq
    UploadCleanupJob.perform_later(urls) if urls.any? && Upload.where(public_url: urls).exists?
  end
end
