class TalentFoldersController < ApplicationController
  before_action -> { authenticate!("jobseeker", "employer") }
  def index = render(json: { folders: TalentFolder.where(owner: current_user).order(updated_at: :desc).map { _1.attributes.merge(count: _1.talent_folder_members.count) } })
  def create
    folder = TalentFolder.create!(owner: current_user, name: params[:name], description: params[:description]); render json: { id: folder.id }, status: :created
  end
  def show
    folder = TalentFolder.where(owner: current_user).find(params[:id]); render json: { folder:, candidates: folder.talent_folder_members.includes(candidate: :profile).map { public_profile(_1.candidate).merge(note: _1.note) } }
  end
  def add_candidate
    folder = TalentFolder.where(owner: current_user).find(params[:id]); member = folder.talent_folder_members.find_or_initialize_by(candidate_id: params[:candidateId]); member.note = params[:note]; member.save!; render json: { ok: true }, status: :created
  end
  def destroy
    TalentFolder.where(owner: current_user).find(params[:id]).destroy!; render json: { ok: true }
  end
end
