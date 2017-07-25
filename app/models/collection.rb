class Collection < JupiterCore::LockedLdpObject

  ldp_object_includes Hydra::Works::CollectionBehavior

  has_attribute :title, ::RDF::Vocab::DC.title, solrize_for: [:search, :facet]
  has_attribute :community_id, ::VOCABULARY[:ualib].path, solrize_for: :pathing

  def community
    Community.find(community_id)
  end

  def path
    "#{community_id}/#{id}"
  end

  def member_works
    Work.where(member_of_paths: path)
  end

  def as_json(_options)
    super(only: [:title, :id])
  end

end
