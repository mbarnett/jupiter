class JupiterCore::Search

  # Performs a solr search using the given query and filtered query strings.
  # Returns an instance of +SearchResult+ providing result counts, +CachedRemoteObject+ representing results, and
  # access to result facets.
  def self.search(q: '', fq: '', models: [], as: nil)
    raise ArgumentError, 'as: must specify a user!' if as.present? && !as.is_a?(User)
    raise ArgumentError, 'must provide at least one model to search for!' unless models.present?
    models = [models] unless models.is_a?(Array)

    base_query = []
    ownership_query = calculate_ownership_query(as)

    # Our query permissions are white-list based. You only get public results unless the results of +calculate_ownership_query+
    # assign you additional permissions based on the user passed to it.
    base_query << %Q((_query_:"{!raw f=visibility_ssim}public"#{ownership_query}))
    base_query << q if q.present?

    results_count, results, facets = perform_solr_query(q: base_query, fq: fq, facet: true,
                                                        facet_fields: models.map(&:facets).flatten.uniq,
                                                        restrict_to_model: models.map { |m| m.send(:derived_af_class) })

    JupiterCore::SearchResults.new(construct_facet_map(models), results_count, facets,
                                   results.map { |res| JupiterCore::CachedRemoteObject.reify_solr_doc(res) })
  end

  # derive additional restriction or broadening of the visibilitily query on top of the default
  # "where visibility is public" restriction
  def self.calculate_ownership_query(user)
    # non-logged-in users don't get anything else
    return '' unless user.present?

    # You can see what you own, regardless of visibility
    # TODO: owner is...? db id? ccid? email?
    return %Q( OR _query_:"{!raw f=owner_ssim}#{user.id}") unless user.admin?

    # make any visibility setting, including a missing visibility specifier, visible to admins
    #
    # this translates into non-insane query language as "OR visibility is null ([* TO *] AND *:*") OR visibility
    # is any non-null value (*)
    ' OR _query_:"-visibility_ssim:[* TO *] AND *:*" OR _query_:"visibility_ssim:*"'
  end

  def self.perform_solr_query(q:, fq: '', facet: false, facet_fields: [],
                              restrict_to_model: nil, rows: nil, start: nil, sort: nil)
    query = []
    restrict_to_model = [restrict_to_model] unless restrict_to_model.is_a?(Array)

    model_scopes = []

    restrict_to_model.each do |model|
      model_scopes << %Q(_query_:"{!raw f=has_model_ssim}#{model.name}")
    end

    query << "(#{model_scopes.join(' OR ')})"

    query.append(q) if q.present?

    params = {
      q: query.join(' AND '),
      fq: fq,
      facet: facet,
      'facet.field': facet_fields
    }

    params[:rows] = rows if rows.present?
    params[:start] = start if start.present?
    params[:sort] = sort if sort.present?

    response = ActiveFedora::SolrService.instance.conn.get('select', params: params)

    raise SearchFailed unless response['responseHeader']['status'] == 0

    [response['response']['numFound'], response['response']['docs'], response['facet_counts']]
  end

  class << self

    private

    # combine the facet maps (solr_name => attribute_name) of all of the models being searched
    def construct_facet_map(models)
      models.map(&:reverse_solr_name_cache).reduce(&:merge)
    end

  end

end
