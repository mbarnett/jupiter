class Admin::CommunitiesAndCollectionsController < Admin::AdminController

  def index
    @communities = Community.all
  end

  def show
    @community = Community.find(params[:id])
    respond_to do |format|
      format.json { render json: @community.member_collections }
    end
  end

  def new; end

  def create; end

end
