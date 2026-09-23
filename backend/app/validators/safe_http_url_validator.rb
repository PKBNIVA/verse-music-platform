require "uri"

class SafeHttpUrlValidator < ActiveModel::EachValidator
  ALLOWED_SCHEMES = %w[http https].freeze

  def validate_each(record, attribute, value)
    uri = URI.parse(value.to_s)
    valid = ALLOWED_SCHEMES.include?(uri.scheme&.downcase) && uri.host.present? && uri.userinfo.blank?
    record.errors.add(attribute, "must be a valid HTTP or HTTPS URL") unless valid
  rescue URI::InvalidURIError
    record.errors.add(attribute, "must be a valid HTTP or HTTPS URL")
  end
end
