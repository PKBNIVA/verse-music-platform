class OrganizationMember < ApplicationRecord
  self.primary_key = nil
  belongs_to :organization
  belongs_to :user
end
