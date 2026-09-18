class CrewPlan < ApplicationRecord
  belongs_to :owner, class_name: "User"
  has_many :crew_plan_roles, dependent: :destroy
  attribute :genres, :json, default: -> { [] }
  attribute :needs, :json, default: -> { [] }
end
