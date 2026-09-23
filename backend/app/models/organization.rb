class Organization < ApplicationRecord
  belongs_to :owner, class_name: "User"
  has_many :organization_members, dependent: :destroy
  validates :website, safe_http_url: true, allow_blank: true
end
