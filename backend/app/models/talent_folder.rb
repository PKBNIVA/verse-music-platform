class TalentFolder < ApplicationRecord
  belongs_to :owner, class_name: "User"
  has_many :talent_folder_members, dependent: :destroy
end
