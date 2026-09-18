if Rails.env.production? && (ENV["ADMIN_EMAIL"].blank? || ENV.fetch("ADMIN_PASSWORD", "").length < 14)
  raise "Production requires ADMIN_EMAIL and an ADMIN_PASSWORD of at least 14 characters"
end

admin = User.find_or_initialize_by(email: ENV.fetch("ADMIN_EMAIL", "admin@verse.local").downcase)
admin.assign_attributes(name: "Verse Admin", role: "admin", status: "active", profile_complete: true)
admin.password = ENV.fetch("ADMIN_PASSWORD", "Admin@12345") if admin.new_record? || ENV["ADMIN_PASSWORD"].present?
admin.save!
admin.create_profile! unless admin.profile

unless Rails.env.production? || ENV["SEED_DEMO_DATA"] == "false"
  employer = User.find_or_initialize_by(email: "studio@verse.local")
  employer.assign_attributes(name: "YRF Studios", role: "employer", status: "active", profile_complete: true, password: "Employer@123")
  employer.save!
  employer.create_profile!(company_name: "YRF Studios", company_description: "Film and music production studio", verified: true, location: "Mumbai, Maharashtra") unless employer.profile

  artist = User.find_or_initialize_by(email: "artist@verse.local")
  artist.assign_attributes(name: "Aditya Sharma", role: "jobseeker", status: "active", profile_complete: true, password: "Artist@123")
  artist.save!
  artist.create_profile!(headline: "Playback Singer", bio: "Versatile vocalist with studio and live experience.", location: "Mumbai, Maharashtra", skills: ["Playback Singing", "Studio Recording", "Hindi"], genres: ["Bollywood", "Pop"], instruments: ["Vocals"]) unless artist.profile
end

[
  ["How music credits actually work", "Industry fundamentals", "A practical guide to documenting releases, roles and contribution credits.", "https://www.allmusic.com/"],
  ["Rights, royalties & metadata basics", "Music business", "Understand publishing, master rights, neighbouring rights and why metadata matters.", "https://www.iprs.org/"],
  ["Build a hiring-ready music portfolio", "Career", "How to present credits, reels, session work and proof of execution for different roles.", nil]
].each do |title, category, description, url|
  CareerResource.find_or_create_by!(title:) { _1.assign_attributes(category:, description:, url:, status: "published") }
end
