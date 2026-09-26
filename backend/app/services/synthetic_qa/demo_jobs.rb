# Durable, adapter-independent state for demo-data jobs. Each state change is an
# audit_logs row (entity_type "DemoDataJob", entity_id = ActiveJob job_id), so the
# admin UI can poll progress whether the queue is GoodJob, async or inline, and the
# history stays in the audit trail after the demo users are purged.
module SyntheticQa
  module DemoJobs
    ENTITY = "DemoDataJob".freeze
    ACTIVE_STATES = %w[queued running].freeze

    module_function

    def record!(job_id, state, actor_id: nil, **details)
      AuditLog.create!(actor_id:, action: "demo_data.job.#{state}", entity_type: ENTITY, entity_id: job_id,
        metadata: details.merge(state:).compact.as_json)
    end

    def find(job_id)
      rows = AuditLog.where(entity_type: ENTITY, entity_id: job_id.to_s).order(:created_at).to_a
      rows.any? ? summarize(rows) : nil
    end

    def recent(limit = 8)
      ids = AuditLog.where(entity_type: ENTITY).group(:entity_id).order(Arel.sql("MAX(created_at) DESC")).limit(limit).pluck(:entity_id)
      rows = AuditLog.where(entity_type: ENTITY, entity_id: ids).order(:created_at).to_a.group_by(&:entity_id)
      ids.map { summarize(rows.fetch(_1)) }
    end

    def active
      ids = AuditLog.where(entity_type: ENTITY).where("created_at > ?", Demo::STALE_AFTER.ago).distinct.pluck(:entity_id)
      ids.filter_map { find(_1) }.select { ACTIVE_STATES.include?(_1[:state]) }
    end

    def busy? = active.any?

    def summarize(rows)
      details = rows.each_with_object({}) { |row, memo| memo.merge!(row.metadata.to_h) }
      latest = rows.last
      state = details["state"]
      if ACTIVE_STATES.include?(state) && latest.created_at < Demo::STALE_AFTER.ago
        state = "failed"
        details["error"] ||= "The job stopped reporting progress (the server may have restarted). It is safe to retry."
      end
      {
        id: latest.entity_id, kind: details["kind"], state:, batch: details["batch"], batches: details["batches"],
        size: details["size"], error: details["error"], result: details["result"],
        createdAt: rows.first.created_at, updatedAt: latest.created_at
      }.compact
    end
  end
end
