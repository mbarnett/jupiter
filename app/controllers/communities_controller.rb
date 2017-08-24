class CommunitiesController < ApplicationController

  before_action -> { authorize :application, :admin? }, except: [:index, :show]

  def show
    @community = Community.find(params[:id])
    authorize @community
    respond_to do |format|
      format.html
      format.json { render json: @community.member_collections }
    end
  end

  def index
    authorize Community
    @communities = Community.all
  end

  def new
    @community = Community.new_cached_remote_object
    authorize @community
  end

  def edit
    @community = Community.find(params[:id])
    authorize @community
  end

  def create
    @community =
      Community.new_cached_remote_object(permitted_attributes(Community)
                                       .merge(owner: current_user&.id))
    authorize @community
    @community.flush_cache_and_perform_remote_write(&:save!)

    redirect_to @community
  end

  def update
    @community = Community.find(params[:id])
    authorize @community
    @community.flush_cache_and_perform_remote_write do |unlocked_community|
      unlocked_community.update!(permitted_attributes(Community))
    end
    flash[:notice] = I18n.t('application.communities.updated')
    redirect_to @community
  end

  def destroy
    community = Community.find(params[:id])
    authorize community
    community.flush_cache_and_perform_remote_write do |uo|
      if uo.destroy
        flash[:notice] = I18n.t('application.communities.deleted')
      else
        flash[:alert] = I18n.t('application.communities.not_empty_error')
      end

      redirect_to admin_communities_and_collections_path
    end
  end

end
