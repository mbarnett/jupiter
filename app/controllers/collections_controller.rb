class CollectionsController < ApplicationController

  before_action -> { authorize :application, :admin? }, except: [:index, :show]

  def show
    @collection = Collection.find(params[:id])
    authorize @collection
    @community = Community.find(@collection.community_id)
  end

  def new
    @collection = Collection.new_cached_remote_object(community_id: params[:community_id])
    authorize @collection
    @community = Community.find(params[:community_id])
  end

  def create
    @collection =
      Collection.new_cached_remote_object(permitted_attributes(Collection)
                                        .merge(owner: current_user&.id))
    authorize @collection
    @collection.flush_cache_and_mutate_remote(&:save!)

    @community = Community.find(params[:community_id])
    redirect_to community_collection_path(@community, @collection)
  end

  def edit
    @community = Community.find(params[:community_id])
    authorize @community
    @collection = Collection.find(params[:id])
    authorize @collection
  end

  def update
    @collection = Collection.find(params[:id])
    authorize @collection
    @collection.flush_cache_and_mutate_remote do |unlocked_collection|
      unlocked_collection.update!(permitted_attributes(Collection))
    end
    flash[:notice] = I18n.t('application.collections.updated')
    redirect_to admin_communities_and_collections_path
  end

  def destroy
    collection = Collection.find(params[:id])
    authorize collection
    collection.flush_cache_and_mutate_remote do |uo|
      if uo.destroy
        flash[:notice] = I18n.t('application.collections.deleted')
      else
        flash[:alert] = I18n.t('application.collections.not_empty_error')
      end

      redirect_to admin_communities_and_collections_path
    end
  end

end
