class TalentShortlist < ApplicationRecord
  self.primary_key = nil
  belongs_to :employer, class_name: "User"
  belongs_to :candidate, class_name: "User"
end
