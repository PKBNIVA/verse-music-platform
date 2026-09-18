class BandProjectRole < ApplicationRecord
  belongs_to :band_project
  belongs_to :opportunity, class_name: "Job", optional: true
end
