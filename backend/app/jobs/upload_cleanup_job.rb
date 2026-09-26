# Deletes uploaded objects that a work sample stopped referencing (item deleted or its
# media URL replaced). An upload still used by another work sample is kept.
class UploadCleanupJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  def perform(urls)
    Upload.where(public_url: Array(urls)).find_each do |upload|
      upload.purge! unless upload.referenced?
    end
  end
end
