class BandProjectRole < ApplicationRecord
  belongs_to :band_project
  belongs_to :opportunity, class_name: "Job", optional: true
  validates :role_name, presence: true, length: { maximum: 120 }
  validates :count_needed, numericality: { only_integer: true, in: 1..100 }
end
