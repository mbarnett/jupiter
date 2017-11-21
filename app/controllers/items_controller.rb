class ItemsController < ApplicationController

  before_action :load_item, only: [:show, :edit, :update]
  before_action :initialize_communities_and_collections, only: [:new, :edit]

  def show; end

  def new
    # TODO: Remove for Deposit Item Controller
    @item = Item.new_locked_ldp_object
    authorize @item
  end

  def create
    # TODO: Remove for Deposit Item Controller
    communities = params[:item].delete :community
    collections = params[:item].delete :collection

    @item = Item.new_locked_ldp_object(permitted_attributes(Item))
    authorize @item

    # TODO: add validations?
    @item.unlock_and_fetch_ldp_object do |unlocked_item|
      unlocked_item.owner = current_user.id
      unlocked_item.update_communities_and_collections(communities, collections)

      # see also https://github.com/samvera/hydra-works/wiki/Lesson%3A-Add-attached-files
      params[:item][:file]&.each do |file|
        fileset = FileSet.new
        Hydra::Works::AddFileToFileSet.call(fileset, file, :original_file, update_existing: false, versioning: false)
        fileset.save!
        # pull in hydra derivatives, set temp file base
        # Hydra::Works::CharacterizationService.run(fileset.characterization_proxy, filename)
        unlocked_item.members << fileset
      end

      if unlocked_item.save
        redirect_to @item, notice: t('.created')
      else
        initialize_communities_and_collections
        render :new, status: :bad_request
      end
    end
  end

  def edit
    # TODO: Remove for Deposit Item Controller
  end

  def update
    # TODO: Remove for Deposit Item Controller
    authorize @item

    communities = params[:item].delete :community
    collections = params[:item].delete :collection

    @item.unlock_and_fetch_ldp_object do |unlocked_item|
      unlocked_item.update_attributes(permitted_attributes(@item))
      unlocked_item.update_communities_and_collections(communities, collections)
      if unlocked_item.save
        redirect_to @item, notice: t('.updated')
      else
        initialize_communities_and_collections
        render :edit, status: :bad_request
      end
    end
  end

  private

  def load_item
    @item = Item.find(params[:id])
    authorize @item
  end

  def initialize_communities_and_collections
    @communities = Community.all

    @item_communities = []
    @item_collections = []
    @collection_choices = []

    return if @item.nil?
    @item.each_community_collection do |community, collection|
      @item_communities << community
      @item_collections << collection
      @collection_choices << community.member_collections
    end
  end

end
