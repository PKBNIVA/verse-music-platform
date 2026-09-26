# Object storage for user uploads.
#
# Two backends, recorded per Upload row in `storage` so deletes keep working after the
# configuration changes:
# - "s3":   S3-compatible bucket (AWS S3 or Cloudflare R2) when AWS_BUCKET is set. The
#           browser uploads directly with a presigned POST policy (or a presigned PUT
#           with signed Content-Type and Content-Length, see .upload_method); the API
#           then verifies the stored object before it can be used.
# - "disk": Active Storage Disk service, streamed through the API. Development/test, or
#           production with PERSISTENT_UPLOADS=true on a volume.
class UploadStorage
  class NotConfigured < StandardError; end

  KEY_PREFIX = "uploads/"
  PRESIGN_TTL = 15.minutes
  R2_HOST_SUFFIX = ".r2.cloudflarestorage.com"

  class << self
    def direct? = ENV["AWS_BUCKET"].present?

    def local_allowed? = !Rails.env.production? || ENV["PERSISTENT_UPLOADS"] == "true"

    def ready? = direct? ? configuration_problems.empty? : local_allowed?

    # Stable, secret-free codes describing why direct uploads cannot work.
    def configuration_problems
      return [] unless direct?
      problems = []
      problems << "missing_credentials" unless ENV["AWS_ACCESS_KEY_ID"].present? && ENV["AWS_SECRET_ACCESS_KEY"].present?
      problems << "missing_public_base_url" if endpoint && public_base_url.nil?
      if Rails.env.production?
        problems << "insecure_endpoint" if endpoint && !endpoint.start_with?("https://")
        problems << "insecure_public_base_url" if public_base_url && !public_base_url.start_with?("https://")
      end
      problems
    end

    def bucket = ENV.fetch("AWS_BUCKET")
    def endpoint = ENV["AWS_ENDPOINT_URL_S3"].presence
    def public_base_url = ENV["AWS_PUBLIC_BASE_URL"].presence&.delete_suffix("/")
    # R2 expects "auto"; AWS keeps the historical default.
    def region = ENV["AWS_REGION"].presence || (endpoint ? "auto" : "ap-south-1")

    # "post" (policy-enforced size range, exact type and key) unless overridden.
    # Cloudflare R2 does not document browser POST-policy uploads, so R2 endpoints default
    # to a presigned PUT whose Content-Type and Content-Length are part of the signature.
    # Either way UploadsController#complete re-checks size and magic bytes.
    def upload_method
      configured = ENV["AWS_UPLOAD_METHOD"].to_s.downcase
      return configured if %w[post put].include?(configured)
      endpoint && URI.parse(endpoint).host.to_s.end_with?(R2_HOST_SUFFIX) ? "put" : "post"
    rescue URI::InvalidURIError
      "post"
    end

    def client
      require "aws-sdk-s3"
      options = { region: }
      options.merge!(endpoint:, force_path_style: true) if endpoint
      Aws::S3::Client.new(**options)
    end

    def public_url_for(key)
      return "#{public_base_url}/#{key}" if public_base_url
      raise NotConfigured, "AWS_PUBLIC_BASE_URL is required with a custom S3 endpoint." if endpoint
      "https://#{bucket}.s3.#{region}.amazonaws.com/#{key}"
    end

    def build_key(user_id, filename) = "#{KEY_PREFIX}#{user_id}/#{SecureRandom.uuid}/#{filename}"

    # Browser upload instructions for a pending Upload.
    def presign(upload)
      raise NotConfigured, "Direct uploads are misconfigured." unless ready?
      if upload_method == "put"
        url = Aws::S3::Presigner.new(client:).presigned_url(:put_object, bucket:, key: upload.key, content_type: upload.content_type,
          content_length: upload.byte_size, expires_in: PRESIGN_TTL.to_i, whitelist_headers: ["content-length"])
        { method: "PUT", uploadUrl: url, headers: { "Content-Type" => upload.content_type }, fields: {} }
      else
        post = Aws::S3::Bucket.new(name: bucket, client:).presigned_post(
          key: upload.key, content_type: upload.content_type, content_length_range: upload.byte_size..upload.byte_size,
          signature_expiration: PRESIGN_TTL.from_now, success_action_status: "201"
        )
        { method: "POST", uploadUrl: post.url, headers: {}, fields: post.fields }
      end
    end

    # => { size:, content_type:, header: } or nil when the object does not exist.
    def inspect_object(key)
      head = client.head_object(bucket:, key:)
      header = head.content_length.to_i.positive? ? client.get_object(bucket:, key:, range: "bytes=0-#{MediaTypeSniffer::HEADER_BYTES - 1}").body.read : "".b
      { size: head.content_length.to_i, content_type: head.content_type.to_s, header: }
    rescue Aws::S3::Errors::NotFound, Aws::S3::Errors::NoSuchKey
      nil
    end

    def delete(storage, key)
      case storage
      when "s3" then client.delete_object(bucket:, key:)
      when "disk"
        # Upload blobs have no attachments or variants (and the schema has no variant
        # table), so delete the file and the row directly instead of Blob#purge.
        # (Blob#delete only removes the file, hence the explicit delete_all.)
        blob = ActiveStorage::Blob.find_by(key:)
        if blob
          blob.delete
          ActiveStorage::Blob.where(id: blob.id).delete_all
        end
      end
      true
    end

    # Yields [key, last_modified] for stored objects under the upload prefix.
    def each_object(max_keys: 10_000)
      seen = 0
      client.list_objects_v2(bucket:, prefix: KEY_PREFIX).each_page do |page|
        page.contents.each do |object|
          return if (seen += 1) > max_keys
          yield object.key, object.last_modified
        end
      end
    end
  end
end
