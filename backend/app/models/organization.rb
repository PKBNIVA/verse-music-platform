class Organization < ApplicationRecord
  belongs_to :owner, class_name: "User"
  has_many :organization_members, dependent: :destroy
end
