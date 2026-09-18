class TalentFolderMember < ApplicationRecord
  self.primary_key = nil
  belongs_to :talent_folder
  belongs_to :candidate, class_name: "User"
end
