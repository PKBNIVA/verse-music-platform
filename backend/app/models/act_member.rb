class ActMember < ApplicationRecord
  belongs_to :act
  belongs_to :user, optional: true
  def api_json = { id:, userId: user_id, displayName: display_name, roleName: role_name, instrument:, isLeader: is_leader, memberStatus: member_status }
  def public_json = { id:, displayName: display_name, roleName: role_name, instrument:, isLeader: is_leader }
end
