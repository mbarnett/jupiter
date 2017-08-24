# Special policy for ProxiedRemoteObjects to inherit from
class ProxiedRemoteObjectPolicy < ApplicationPolicy

  def permitted_attributes
    model_class.safe_attributes
  end

  protected

  def model_class
    record.is_a?(Class) ? record : record.class
  end

  def owned?
    return false unless user.present? && user.id.present?
    record.owner == user.id
  end

  def public?
    record.public?
  end

end
