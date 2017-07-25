class Work < JupiterCore::LockedLdpObject

  ldp_object_includes Hydra::Works::WorkBehavior

  has_attribute :title, ::RDF::Vocab::DC.title, solrize_for: [:search, :facet]
  has_attribute :subject, ::RDF::Vocab::DC.subject, solrize_for: [:search, :facet]
  has_attribute :creator, ::RDF::Vocab::DC.creator, solrize_for: [:search, :facet]
  has_attribute :contributor, ::RDF::Vocab::DC.contributor, solrize_for: [:search, :facet]
  has_attribute :description, ::RDF::Vocab::DC.description, type: :text, solrize_for: :search
  has_attribute :publisher, ::RDF::Vocab::DC.publisher, solrize_for: [:search, :facet]
  has_attribute :date_created, ::RDF::Vocab::DC.created, solrize_for: [:search, :sort]
  # has_attribute :date_modified, ::RDF::Vocab::DC.modified, type: :date, solrize_for: :sort
  has_attribute :language, ::RDF::Vocab::DC.language, solrize_for: [:search, :facet]
  has_attribute :doi, ::VOCABULARY[:ualib].doi, solrize_for: :exact_match

  has_multival_attribute :member_of_paths, ::VOCABULARY[:ualib].path, solrize_for: :pathing
  has_attribute :embargo_end_date, ::RDF::Vocab::DC.modified, solrize_for: [:search, :sort]

  solr_calculated_attribute :doi_without_label, solrize_for: :exact_match do |work|
    work.doi.gsub('doi:', '') if work.doi.present?
  end

  def self.display_attribute_names
    super - [:member_of_paths]
  end

  def self.valid_visibilities
    super + ['embargo']
  end

  unlocked do
    validates :embargo_end_date, presence: true, if: ->(work) { work.visibility == :embargo }
    validates :embargo_end_date, absence: true, if: ->(work) { work.visibility != :embargo }

    def add_to_path(community_id, collection_id)
      self.member_of_paths += ["#{community_id}/#{collection_id}"]
    end
  end

end
