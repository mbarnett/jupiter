class CollectionPolicy < ProxiedRemoteObjectPolicy

  def index?
    true
  end

  def create?
    admin?
  end

end
