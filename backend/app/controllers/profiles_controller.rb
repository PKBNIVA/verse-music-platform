class ProfilesController < ApplicationController
  def update
    return unless authenticate!("jobseeker", "employer")
    attributes = profile_params
    if (message = invalid_number_message(attributes))
      return render_error(message, :unprocessable_content)
    end
    if attributes["currency"].present? && !CURRENCIES.include?(attributes["currency"])
      return render_error("Currency must be one of #{CURRENCIES.join(', ')}", :unprocessable_content)
    end
    profile = current_user.profile || current_user.build_profile
    profile.assign_attributes(attributes)
    profile.save!
    current_user.update!(profile_complete: true)
    audit!("profile.update", current_user)
    render json: { user: public_user(current_user.reload) }
  end

  private

  CURRENCIES = %w[INR USD EUR GBP].freeze
  # Integer columns: values outside 0..MAX_NUMBER used to raise ActiveModel::RangeError (HTTP 500).
  NUMBER_FIELDS = {
    "years_experience" => "Years of experience", "travel_radius_km" => "Travel radius",
    "hourly_rate" => "Hourly rate", "session_rate" => "Session rate", "show_rate" => "Show rate",
    "tour_day_rate" => "Tour day rate", "day_rate" => "Day rate"
  }.freeze
  MAX_NUMBER = 2_000_000_000

  def invalid_number_message(attributes)
    NUMBER_FIELDS.each do |field, label|
      raw = attributes[field]
      next if raw.blank?
      number = Float(raw.to_s, exception: false)
      return "#{label} must be a number" if number.nil? || !number.finite?
      return "#{label} cannot be negative" if number.negative?
      return "#{label} is too large" if number > MAX_NUMBER
    end
    nil
  end

  def profile_params
    source = params.permit(:headline, :bio, :phone, :location, :experience, :website, :portfolioUrl, :availability,
      :companyName, :companyWebsite, :companySize, :companyDescription, :yearsExperience, :travelRadiusKm,
      :travelsNationally, :travelsInternationally, :remoteRecording, :sightReading, :passportReady,
      :hourlyRate, :sessionRate, :showRate, :tourDayRate, :dayRate, :currency,
      skills: [], genres: [], instruments: [], languages: [], credits: [], openTo: [], roles: [], gear: [], software: [])
    source.to_h.transform_keys { _1.underscore }.slice(*Profile.column_names)
  end
end
