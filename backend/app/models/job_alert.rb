class JobAlert < ApplicationRecord
  belongs_to :user
  has_many :job_alert_deliveries, dependent: :destroy

  validates :frequency, inclusion: { in: %w[daily weekly saved] }
  before_validation :schedule_next_delivery, if: :schedule_changed?

  scope :due_at, ->(time) { where(active: true).where.not(next_run_at: nil).where(next_run_at: ..time) }

  def matching_jobs(window_start:, window_end:)
    relation = Job.published.where(published_at: window_start...window_end)
    if query.present?
      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
      relation = relation.where(<<~SQL.squish, pattern:)
        jobs.title ILIKE :pattern OR jobs.company ILIKE :pattern OR jobs.description ILIKE :pattern OR
        jobs.requirements ILIKE :pattern OR jobs.genre ILIKE :pattern OR jobs.function_area ILIKE :pattern OR
        jobs.opportunity_kind ILIKE :pattern OR jobs.skills::text ILIKE :pattern
      SQL
    end
    relation = relation.where("jobs.location ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(location)}%") if location.present?
    relation = relation.where(opportunity_kind:) if opportunity_kind.present?
    relation = relation.where(function_area:) if function_area.present?
    relation = relation.where(workplace: "remote") if remote_only?
    relation.order(published_at: :asc, id: :asc)
  end

  def next_delivery_after(time)
    return unless active? && frequency.in?(%w[daily weekly])

    time + (frequency == "daily" ? 1.day : 1.week)
  end

  private

  def schedule_changed?
    new_record? || will_save_change_to_frequency? || will_save_change_to_active?
  end

  def schedule_next_delivery
    self.next_run_at = next_delivery_after(Time.current)
  end
end
