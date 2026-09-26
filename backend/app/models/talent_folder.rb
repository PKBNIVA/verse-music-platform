class TalentFolder < ApplicationRecord
  belongs_to :owner, class_name: "User"
  # Members have no primary key, so they are removed in one statement rather than one by one.
  has_many :talent_folder_members, dependent: :delete_all
  normalizes :name, with: -> { _1.to_s.strip }
  validates :name, presence: true, length: { maximum: 80 }
end
