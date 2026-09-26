# Daily storage housekeeping:
# - pending direct uploads not completed within STALE_AFTER (abandoned or rejected);
# - completed uploads no work sample uses after STALE_AFTER, or whose owner was deleted;
# - bucket objects under uploads/ with no Upload row that no work sample links to
#   (pre-tracking uploads that are still in use are kept).
class UploadSweepJob < ApplicationJob
  BATCH_SIZE = 500
  MAX_OBJECTS_SCANNED = 20_000

  queue_as :scheduled

  def perform(now = Time.current)
    cutoff = now - Upload::STALE_AFTER
    counts = Hash.new(0)
    Upload.pending.where(created_at: ...cutoff).find_each(batch_size: BATCH_SIZE) { purge(_1, counts, :pending) }
    Upload.where(user_id: nil).find_each(batch_size: BATCH_SIZE) { purge(_1, counts, :ownerDeleted) }
    Upload.complete.where(created_at: ...cutoff).unreferenced.find_each(batch_size: BATCH_SIZE) { purge(_1, counts, :unreferenced) }
    sweep_bucket(cutoff, counts) if UploadStorage.direct? && UploadStorage.ready?
    Rails.logger.info({ event: "upload_sweep", **counts }.to_json)
    counts
  end

  private

  def purge(upload, counts, reason)
    upload.purge!
    counts[reason] += 1
  rescue StandardError => error
    counts[:errors] += 1
    Rails.logger.warn({ event: "upload_sweep_failed", uploadId: upload.id, error: error.class.name }.to_json)
    ErrorReporter.capture(error, tags: { source: "upload_sweep_failed" }, level: :warning, uploadId: upload.id)
  end

  def sweep_bucket(cutoff, counts)
    candidates = []
    UploadStorage.each_object(max_keys: MAX_OBJECTS_SCANNED) do |key, last_modified|
      candidates << key if last_modified && last_modified < cutoff
      if candidates.size >= BATCH_SIZE
        delete_orphans(candidates, counts)
        candidates = []
      end
    end
    delete_orphans(candidates, counts) if candidates.any?
  end

  def delete_orphans(keys, counts)
    tracked = Upload.where(storage: "s3", key: keys).pluck(:key)
    (keys - tracked).each do |key|
      next if linked_from_portfolio?(key)
      UploadStorage.delete("s3", key)
      counts[:orphanObjects] += 1
    end
  end

  def linked_from_portfolio?(key)
    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(key)}"
    PortfolioItem.where("url LIKE :p OR thumbnail_url LIKE :p OR waveform_url LIKE :p", p: pattern).exists?
  end
end
