class TalentFoldersController < ApplicationController
  before_action -> { authenticate!("jobseeker", "employer") }
  def index = render(json: { folders: TalentFolder.where(owner: current_user).order(updated_at: :desc).map { _1.attributes.merge(count: _1.talent_folder_members.count) } })
  def create
    folder = TalentFolder.create!(owner: current_user, name: params[:name], description: params[:description]); render json: { id: folder.id }, status: :created
  end
  def show
    folder = TalentFolder.where(owner: current_user).find(params[:id])
    # Profiles that stopped being discoverable (suspended, hidden, incomplete) drop out of folders.
    members = folder.talent_folder_members.where(candidate_id: User.discoverable_talent.select(:id)).includes(candidate: :profile)
    render json: { folder:, candidates: members.map { public_profile(_1.candidate).merge(note: _1.note) } }
  end
  def add_candidate
    folder = TalentFolder.where(owner: current_user).find(params[:id])
    candidate = User.discoverable_talent.find(params[:candidateId].to_s)
    members = folder.talent_folder_members.where(candidate_id: candidate.id)
    # TalentFolderMember has no primary key, so an existing row is updated through the relation.
    if members.exists?
      members.update_all(note: params[:note])
    else
      begin
        folder.talent_folder_members.create!(candidate:, note: params[:note])
      rescue ActiveRecord::RecordNotUnique
        members.update_all(note: params[:note])
      end
    end
    render json: { ok: true }, status: :created
  end
  def destroy
    TalentFolder.where(owner: current_user).find(params[:id]).destroy!; render json: { ok: true }
  end
end
