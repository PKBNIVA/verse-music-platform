class BandProject < ApplicationRecord
  belongs_to :owner, class_name: "User"
  has_many :band_project_roles, dependent: :destroy
  attribute :genres, :json, default: -> { [] }
end
