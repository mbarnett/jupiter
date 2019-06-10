class JupiterCore::SolrClient
  include Singleton

  SOLR_ROLES = [:search, :sort, :facet, :exact_match, :pathing, :range_facet].freeze
  SOLR_TYPES =  [:string, :text, :path, :boolean, :date, :integer, :float, :json_array].freeze

  SOLR_CONFIG = YAML.safe_load(ERB.new(File.read(Rails.root.join('config', 'solr.yml'))).result,
                               [], [], true)[Rails.env].symbolize_keys

  def self.valid_solr_type?(type)
    SOLR_TYPES.include?(type)
  end

  def connection
    @connection ||= RSolr.connect url: SOLR_CONFIG[:url]
  end

end
