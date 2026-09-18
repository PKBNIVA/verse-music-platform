class ProfilesController < ApplicationController
  def update
    return unless authenticate!("jobseeker", "employer")
    profile = current_user.profile || current_user.build_profile
    profile.assign_attributes(profile_params)
    profile.save!
    current_user.update!(profile_complete: true)
    audit!("profile.update", current_user)
    render json: { user: public_user(current_user.reload) }
  end

  private

  def profile_params
    source = params.permit(:headline, :bio, :phone, :location, :experience, :website, :portfolioUrl, :availability,
      :companyName, :companyWebsite, :companySize, :companyDescription, :yearsExperience, :travelRadiusKm,
      :travelsNationally, :travelsInternationally, :remoteRecording, :sightReading, :passportReady,
      :hourlyRate, :sessionRate, :showRate, :tourDayRate, :dayRate, :currency,
      skills: [], genres: [], instruments: [], languages: [], credits: [], openTo: [], roles: [], gear: [], software: [])
    source.to_h.transform_keys { _1.underscore }.slice(*Profile.column_names)
  end
end
