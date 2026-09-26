# Demo batches are synthetic batches whose name starts with "demo-". Unlike other
# synthetic QA batches they are shown in public listings (with a "Demo" badge) so the
# owner can preview a populated marketplace, and they can be created and purged from
# the admin UI. They are never loginable with a known password.
module SyntheticQa
  module Demo
    PREFIX = "demo-".freeze
    MAX_USERS = 300
    SIZES = {
      "small" => { jobseekers: 20, employers: 8 },
      "medium" => { jobseekers: 60, employers: 20 },
      "large" => { jobseekers: 150, employers: 50 }
    }.freeze
    # A queued or running demo job older than this is treated as dead (e.g. the process
    # restarted mid-run) so it never blocks the admin forever.
    STALE_AFTER = 30.minutes
    ADVISORY_LOCK_KEY = 0x0de30da7a

    module_function

    def batch?(name) = name.to_s.start_with?(PREFIX)

    def user?(user) = user.present? && batch?(user.synthetic_batch)

    # Untagged users plus demo batches; every other synthetic batch stays hidden.
    def publicly_listed(scope)
      scope.where("users.synthetic_batch IS NULL OR users.synthetic_batch LIKE ?", "#{PREFIX}%")
    end

    def users = User.where("synthetic_batch LIKE ?", "#{PREFIX}%")

    def batch_names = users.distinct.order(:synthetic_batch).pluck(:synthetic_batch)

    def next_batch_name(now = Time.current)
      base = "#{PREFIX}#{now.utc.strftime('%Y%m%d-%H%M')}"
      return base unless User.exists?(synthetic_batch: base)
      "#{base}#{now.utc.strftime('%S')}-#{SecureRandom.alphanumeric(4).downcase}"
    end

    # Serialises the "is another demo job running?" check with the enqueue, across processes.
    # Returns :locked when another request holds the lock.
    def with_admin_lock
      connection = ApplicationRecord.connection
      locked = connection.select_value("SELECT pg_try_advisory_lock(#{ADVISORY_LOCK_KEY})")
      return :locked unless locked
      yield
    ensure
      connection.select_value("SELECT pg_advisory_unlock(#{ADVISORY_LOCK_KEY})") if locked
    end
  end
end
