class AuditLog < ApplicationRecord
  belongs_to :actor, class_name: "User", optional: true
  attribute :metadata, :json, default: -> { {} }
end
