class Report < ApplicationRecord
  belongs_to :reporter, class_name: "User", optional: true
  belongs_to :resolved_by, class_name: "User", optional: true
end
