class CommunitiesController < ApplicationController

  def index
    @communities = Community.all
  end

  def new
    @community = Community.new_locked_ldp_object
  end

  def show
    @community = community = Community.find(params[:id])
    respond_to do |format|
      format.html
      format.json { render json: @community.member_collections }
    end
  end

  def edit
    @community = Community.find(params[:id])
  end

  def update
    @community = Community.find(params[:id])
    @community.unlock_and_fetch_ldp_object do |unlocked_community|
      unlocked_community.update!(community_params)
    end
    redirect_to @community
  end

  def create
    @community = Community.new_locked_ldp_object(community_params)
    @community.unlock_and_fetch_ldp_object(&:save!)

    redirect_to @community
  end

  def destroy
    community = Community.find(params[:id])
    community.unlock_and_fetch_ldp_object do |uo|
      (flash[:error] = 'Cannot delete a non-empty Community') unless uo.destroy
      redirect_to admin_communities_and_collections_path
    end
  end

  protected

  def community_params
    params[:community].permit(Community.attribute_names)
  end

end
