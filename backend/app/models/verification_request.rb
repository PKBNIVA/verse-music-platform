class VerificationRequest < ApplicationRecord
  belongs_to :user
  validates :kind, inclusion: { in: %w[professional organization] }
  validates :evidence_url, safe_http_url: true, allow_blank: true
end
