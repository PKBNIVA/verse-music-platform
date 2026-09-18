class UrgentRequest < ApplicationRecord
  belongs_to :requester, class_name: "User"
  has_many :urgent_request_responses, dependent: :destroy
end
