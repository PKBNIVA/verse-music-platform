class SavedJob < ApplicationRecord
  self.primary_key = nil
  belongs_to :user
  belongs_to :job
end
