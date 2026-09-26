class CrewPlan < ApplicationRecord
  belongs_to :owner, class_name: "User"
  has_many :crew_plan_roles, dependent: :destroy
  attribute :genres, :json, default: -> { [] }
  attribute :needs, :json, default: -> { [] }
  validates :title, :city, :event_type, :currency, presence: true
  validates :title, :city, :event_type, length: { maximum: 160 }
  # Bounds keep values inside the 32-bit integer columns.
  validates :audience_size, :budget, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than: 2**31 }, allow_nil: true
end
