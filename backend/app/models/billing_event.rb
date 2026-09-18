class BillingEvent < ApplicationRecord
  belongs_to :user, optional: true
  attribute :payload, :json, default: -> { {} }
end
