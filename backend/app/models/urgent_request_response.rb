class UrgentRequestResponse < ApplicationRecord
  self.primary_key = nil
  belongs_to :urgent_request
  belongs_to :user
end
