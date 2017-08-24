class CollectionPolicy < CachedRemoteObjectPolicy

  def index?
    true
  end

  def create?
    admin?
  end

end
