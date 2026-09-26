module Admin
  # Lets an admin populate the live marketplace with clearly badged demo data and remove
  # all of it again with one action. Only users tagged with a "demo-*" synthetic_batch are
  # ever created or deleted here; seeding and purging run as background jobs.
  class DemoDataController < BaseController
    def index
      render json: {
        batches: batch_summaries,
        jobs: SyntheticQa::DemoJobs.recent,
        busy: SyntheticQa::DemoJobs.busy?,
        demoUsers: SyntheticQa::Demo.users.count,
        maxUsers: SyntheticQa::Demo::MAX_USERS,
        sizes: SyntheticQa::Demo::SIZES.transform_values { { artists: _1[:jobseekers], employers: _1[:employers] } }
      }
    end

    def job_status
      job = SyntheticQa::DemoJobs.find(params[:id])
      return render_error("Demo data job not found.", :not_found) unless job
      render json: { job: }
    end

    def create
      size = params[:size].to_s
      counts = SyntheticQa::Demo::SIZES[size]
      return render_error("Choose a size: #{SyntheticQa::Demo::SIZES.keys.join(', ')}.", :unprocessable_entity, "INVALID_SIZE") unless counts

      requested = counts.values.sum
      existing = SyntheticQa::Demo.users.count
      if existing + requested > SyntheticQa::Demo::MAX_USERS
        return render_error("Demo data is capped at #{SyntheticQa::Demo::MAX_USERS} users; #{existing} exist and #{size} adds #{requested}. Delete demo data first or choose a smaller size.",
          :unprocessable_entity, "DEMO_CAP_EXCEEDED")
      end

      batch = SyntheticQa::Demo.next_batch_name
      enqueue(DemoDataSeedJob.new(batch:, size:, admin_id: current_user.id), kind: "seed", batch:, size:)
    end

    def destroy
      batch = params[:batch].to_s
      return render_error("Only demo-* batches can be deleted here.", :unprocessable_entity, "NOT_A_DEMO_BATCH") unless SyntheticQa::Demo.batch?(batch)
      return render_error("Demo batch not found.", :not_found) unless User.exists?(synthetic_batch: batch)

      enqueue(DemoDataPurgeJob.new(admin_id: current_user.id, batches: [batch]), kind: "purge", batch:)
    end

    def destroy_all
      enqueue(DemoDataPurgeJob.new(admin_id: current_user.id), kind: "purge_all", batches: SyntheticQa::Demo.batch_names)
    end

    private

    def enqueue(job, kind:, **details)
      outcome = SyntheticQa::Demo.with_admin_lock do
        next :busy if SyntheticQa::DemoJobs.busy?

        SyntheticQa::DemoJobs.record!(job.job_id, "queued", actor_id: current_user.id, kind:, **details)
        audit!("demo_data.#{kind}", nil, details.merge(jobId: job.job_id))
        job.enqueue
        :queued
      end
      if outcome == :queued
        render json: { jobId: job.job_id, job: SyntheticQa::DemoJobs.find(job.job_id) }, status: :accepted
      else
        render_error("Another demo data job is still running. Wait for it to finish.", :conflict, "DEMO_JOB_RUNNING")
      end
    end

    def batch_summaries
      rows = User.synthetic.group(:synthetic_batch, :role).count
      created = User.synthetic.group(:synthetic_batch).minimum(:created_at)
      rows.group_by { |(batch, _role), _count| batch }.map do |batch, entries|
        roles = entries.to_h { |(_batch, role), count| [role, count] }
        demo = SyntheticQa::Demo.batch?(batch)
        {
          name: batch, demo:, visibility: demo ? "public" : "hidden",
          artists: roles.fetch("jobseeker", 0), employers: roles.fetch("employer", 0), users: roles.values.sum,
          createdAt: created[batch]
        }
      end.sort_by { _1[:createdAt] }.reverse
    end
  end
end
