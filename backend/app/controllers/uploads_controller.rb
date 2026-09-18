class UploadsController < ApplicationController
  ALLOWED_TYPES = %w[audio/mpeg audio/wav audio/x-wav video/mp4 image/jpeg image/png image/webp application/pdf].freeze
  MAX_SIZE = 100.megabytes

  def presign
    return unless authenticate!
    return render_error("Unsupported file type.", :unprocessable_entity) unless ALLOWED_TYPES.include?(params[:contentType])
    return render_error("File is too large.", :unprocessable_entity) unless params[:size].to_i.between?(1, MAX_SIZE)
    if ENV["AWS_BUCKET"].present?
      key = "uploads/#{current_user.id}/#{SecureRandom.uuid}/#{params[:filename].to_s.gsub(/[^A-Za-z0-9_.-]/, "_")}"
      client = Aws::S3::Client.new(region: ENV.fetch("AWS_REGION", "ap-south-1"), endpoint: ENV["AWS_ENDPOINT_URL_S3"].presence, force_path_style: ENV["AWS_ENDPOINT_URL_S3"].present?)
      upload_url = Aws::S3::Presigner.new(client:).presigned_url(:put_object, bucket: ENV["AWS_BUCKET"], key:, content_type: params[:contentType], expires_in: 900)
      public_url = ENV["AWS_PUBLIC_BASE_URL"].present? ? "#{ENV['AWS_PUBLIC_BASE_URL'].delete_suffix('/')}/#{key}" : "https://#{ENV['AWS_BUCKET']}.s3.#{ENV.fetch('AWS_REGION', 'ap-south-1')}.amazonaws.com/#{key}"
      return render json: { mode: "direct", uploadUrl: upload_url, method: "PUT", headers: { "Content-Type" => params[:contentType] }, publicUrl: public_url }
    end
    return render_error("Object storage is not configured.", :service_unavailable) if Rails.env.production?
    render json: { mode: "proxied", uploadUrl: "/api/uploads/local" }
  end

  def local
    return unless authenticate!
    return render_error("Local uploads are disabled in production.", :forbidden) if Rails.env.production?
    content_type = request.content_type.to_s
    return render_error("Unsupported file type.", :unprocessable_entity) unless ALLOWED_TYPES.include?(content_type)
    body = request.body.read(MAX_SIZE + 1)
    return render_error("File is too large.", :unprocessable_entity) if body.bytesize > MAX_SIZE
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(body), filename: "upload-#{SecureRandom.hex(8)}", content_type:)
    render json: { url: rails_blob_url(blob, host: ENV.fetch("API_HOST", request.base_url)) }, status: :created
  end
end
