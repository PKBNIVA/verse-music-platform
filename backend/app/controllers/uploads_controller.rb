require "tempfile"

# Upload flow
#
# Direct (S3/R2, AWS_BUCKET set):
#   1. POST /api/uploads/presign   -> pending Upload + browser POST policy (or signed PUT)
#   2. browser sends the file straight to the bucket
#   3. POST /api/uploads/:id/complete -> API HEADs the object and reads its first bytes;
#      a size or content mismatch deletes the object. Only then is the URL usable.
# Proxied (Disk): POST presign -> { mode: "proxied" }, then PUT /api/uploads/local streams
#   the body to a temp file, checks magic bytes, stores it and returns a complete Upload.
class UploadsController < ApplicationController
  ALLOWED_TYPES = MediaTypeSniffer::ALLOWED_TYPES
  MAX_SIZE = Upload::MAX_SIZE
  CHUNK_SIZE = 1.megabyte

  before_action -> { authenticate! }

  def presign
    content_type = MediaTypeSniffer.canonical(params[:contentType])
    return render_error("Unsupported file type. Upload MP3, WAV, MP4, JPEG, PNG, WebP or PDF.", :unprocessable_entity, "UNSUPPORTED_TYPE") unless ALLOWED_TYPES.include?(content_type)
    return render_error("File is too large. The limit is #{MAX_SIZE / 1.megabyte} MB.", :unprocessable_entity, "FILE_TOO_LARGE") unless params[:size].to_i.between?(1, MAX_SIZE)

    if UploadStorage.direct?
      return render_error("Upload storage is misconfigured.", :service_unavailable, "STORAGE_MISCONFIGURED") unless UploadStorage.ready?
      filename = Upload.sanitize_filename(params[:filename])
      key = UploadStorage.build_key(current_user.id, filename)
      upload = Upload.create!(user: current_user, storage: "s3", key:, filename:, content_type:, byte_size: params[:size].to_i,
        status: "pending", public_url: UploadStorage.public_url_for(key))
      instructions = UploadStorage.presign(upload)
      return render json: {
        mode: "direct", id: upload.id, **instructions, publicUrl: upload.public_url,
        completeUrl: "/api/uploads/#{upload.id}/complete", expiresIn: UploadStorage::PRESIGN_TTL.to_i
      }
    end
    return render_error("Persistent upload storage is not configured.", :service_unavailable, "STORAGE_DISABLED") unless UploadStorage.local_allowed?
    render json: { mode: "proxied", uploadUrl: "/api/uploads/local" }
  end

  def complete
    upload = Upload.where(user: current_user).find(params[:id])
    return render json: { upload: upload.api_json, url: upload.public_url } if upload.complete?

    object = UploadStorage.inspect_object(upload.key)
    return render_error("The file has not reached storage yet. Try the upload again.", :conflict, "UPLOAD_NOT_FOUND") unless object

    problem = if object[:size] != upload.byte_size then "File size does not match the prepared upload."
    elsif MediaTypeSniffer.canonical(object[:content_type]) != upload.content_type then "Stored file type does not match the prepared upload."
    elsif MediaTypeSniffer.detect(object[:header]) != upload.content_type then "File contents do not match the declared type."
    end
    if problem
      upload.purge!
      return render_error(problem, :unprocessable_entity, "UPLOAD_REJECTED")
    end

    upload.update!(status: "complete", completed_at: Time.current)
    render json: { upload: upload.api_json, url: upload.public_url }
  end

  # Discards an upload the user no longer needs (e.g. replaced before saving).
  def destroy
    upload = Upload.where(user: current_user).find(params[:id])
    return render_error("This file is used by a work sample. Delete the work sample instead.", :conflict, "UPLOAD_IN_USE") if upload.referenced?
    upload.purge!
    render json: { ok: true }
  end

  def local
    return render_error("Persistent uploads are disabled.", :forbidden) unless UploadStorage.local_allowed?
    declared = MediaTypeSniffer.canonical(request.content_type)
    return render_error("Unsupported file type. Upload MP3, WAV, MP4, JPEG, PNG, WebP or PDF.", :unprocessable_entity, "UNSUPPORTED_TYPE") unless ALLOWED_TYPES.include?(declared)
    return render_error("File is too large. The limit is #{MAX_SIZE / 1.megabyte} MB.", :unprocessable_entity, "FILE_TOO_LARGE") if request.content_length.to_i > MAX_SIZE

    Tempfile.create(["verse-upload", ".bin"], binmode: true) do |file|
      size = stream_body_to(file)
      return render_error("File is too large. The limit is #{MAX_SIZE / 1.megabyte} MB.", :unprocessable_entity, "FILE_TOO_LARGE") if size > MAX_SIZE
      return render_error("File is empty.", :unprocessable_entity, "FILE_EMPTY") if size.zero?

      file.rewind
      detected = MediaTypeSniffer.detect(file.read(MediaTypeSniffer::HEADER_BYTES))
      unless detected && detected == declared
        return render_error("File contents do not match the declared type.", :unprocessable_entity, "UPLOAD_REJECTED")
      end

      file.rewind
      filename = Upload.sanitize_filename(request.headers["X-Filename"])
      blob = ActiveStorage::Blob.create_and_upload!(io: file, filename:, content_type: detected, identify: false)
      url = rails_blob_url(blob, host: ENV.fetch("API_HOST", request.base_url))
      upload = Upload.create!(user: current_user, storage: "disk", key: blob.key, filename:, content_type: detected, byte_size: size,
        status: "complete", completed_at: Time.current, public_url: url)
      render json: { id: upload.id, url:, upload: upload.api_json }, status: :created
    end
  end

  private

  # Copies at most MAX_SIZE + 1 bytes in CHUNK_SIZE pieces; never holds the file in memory.
  def stream_body_to(file)
    input = request.body
    input.rewind if input.respond_to?(:rewind)
    size = 0
    while (chunk = input.read(CHUNK_SIZE))
      size += chunk.bytesize
      break if size > MAX_SIZE
      file.write(chunk)
    end
    file.flush
    size
  end
end
