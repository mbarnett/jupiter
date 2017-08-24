class WorkPolicy < ProxiedRemoteObjectPolicy

  def index?
    true
  end

  def show?
    owned? || admin? || public?
  end

  def new?
    user.present?
  end

  def create?
    owned? || admin?
  end

  def update?
    create?
  end

  def destroy?
    create?
  end

end
