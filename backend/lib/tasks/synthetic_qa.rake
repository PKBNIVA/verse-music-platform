namespace :synthetic_qa do
  desc "Create a reversible synthetic QA batch (BATCH=... JOBSEEKERS=225 EMPLOYERS=75)"
  task seed: :environment do
    batch = ENV.fetch("BATCH")
    result = SyntheticQa::BatchSeeder.call(batch:, jobseekers: ENV.fetch("JOBSEEKERS", 225), employers: ENV.fetch("EMPLOYERS", 75),
      password: ENV["SYNTHETIC_QA_PASSWORD"])
    puts result.to_h.to_json
  end

  desc "Delete one synthetic QA batch and its complete relationship graph (BATCH=...)"
  task purge: :environment do
    batch = ENV.fetch("BATCH")
    result = SyntheticQa::BatchCleanup.call(batch:)
    puts result.to_h.to_json
  end

  desc "List synthetic QA batches without exposing credentials"
  task list: :environment do
    puts User.synthetic.group(:synthetic_batch, :role).count.to_json
  end
end
