class VerificationRequest < ApplicationRecord
  belongs_to :user
  validates :evidence_url, safe_http_url: true, allow_blank: true
end
