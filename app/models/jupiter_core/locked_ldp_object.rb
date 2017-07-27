# JupiterCore::LockedLdpObject classes are lightweight, read-only objects
# TODO: this file could benefit from some reorganization, possibly into several
# files
module JupiterCore
  class ObjectNotFound < StandardError; end
  class PropertyInvalidError < StandardError; end
  class MultipleIdViolationError < StandardError; end
  class AlreadyDefinedError < StandardError; end
  class LockedInstanceError < StandardError; end

  class LockedLdpObject

    include ActiveModel::Model
    include ActiveModel::Serializers::JSON

    # Prefix added to subclass names to derive the name of their corresponding +ActiveFedora+ LDP object
    AF_CLASS_PREFIX = 'IR'.freeze

    # Maps semantically meaningful, easily understandable names for solr index behaviours
    # into the sometimes inscrutable and opaque descriptors used by Solrizer. See:
    # https://github.com/mbarnett/solrizer/blob/e5dd2bd571b9ebdb8a8ab214574075c28951e53e/lib/solrizer/default_descriptors.rb
    SOLR_DESCRIPTOR_MAP = {
      search: :stored_searchable,
      sort: :stored_sortable,
      facet: :facetable,
      exact_match: :symbol,
      pathing: :descendent_path
    }.freeze

    # we reserve .new for internal use in constructing LockedLDPObjects. Use the public interface
    # +new_locked_ldp_object+ for constructing new objects externally.
    private_class_method :new

    # inheritable class attributes (not all class-level attributes in this class should be inherited,
    # these are the inheritance-safe attributes)
    class_attribute :af_parent_class, :attribute_cache, :attribute_names, :facets,
                    :reverse_solr_name_cache, :solr_calc_attributes

    # Returns the id of the object in LDP as a String
    def id
      return ldp_object.send(:id) if ldp_object.present?
      solr_representation['id'] if solr_representation
    end

    # Provides structured, mediated interaction for mutating the underlying LDP object
    #
    # yields the underlying mutable +ActiveFedora+ object to the block and returns self for chaining
    #
    #  locked_obj.unlock_and_fetch_ldp_object do |ldp_object|
    #    ldp_object.title = 'asdf'
    #    ldp_object.save
    #  end
    def unlock_and_fetch_ldp_object
      self.ldp_object = self.class.send(:derived_af_class).find(self.id) unless @ldp_object.present?
      yield @ldp_object
      self
    end

    # Returns name-value pairs for all of the LDP Object's attributes as a Hash
    def attributes
      self.class.attribute_names.map do |name|
        [name.to_s, self.send(name)]
      end.to_h
    end

    # Returns name-value pairs for the LDP Object's attributes named by +display_attribute_names+ as a Hash
    def display_attributes
      self.class.display_attribute_names.map do |name|
        [name.to_s, self.send(name)]
      end.to_h
    end

    # A better debug representation for LDP Objects
    def inspect
      "#<#{self.class.name || 'AnonymousClass'} " + self.class.attribute_names.map do |name|
        val = self.send(name)
        val_display = if val.is_a?(String)
                        %Q("#{val}")
                      elsif val.nil?
                        'nil'
                      elsif val.is_a?(Enumerable) && val.empty?
                        '[]'
                      else
                        val.to_s
                      end
        "#{name}: #{val_display}"
      end.join(', ') + '>'
    end

    # Has this object been persisted? (Defined for ActiveModel compatibility)
    def persisted?
      # if we haven't had to load the internal ldp_object, by definition we must by synced to disk
      return true unless ldp_object.present?
      ldp_object.persisted?
    end

    # Has this object been changed since being loaded? (Defined for ActiveModel compatibility)
    def changed?
      return false unless ldp_object.present?
      ldp_object.changed?
    end

    # Do this object's validations pass? (Defined for ActiveModel compatibility)
    def valid?(*args)
      return super(*args) unless ldp_object.present?
      ldp_object.valid?(*args)
    end

    # Do this object's validations pass? (Defined for ActiveModel compatibility)
    def errors
      return super unless ldp_object.present?
      ldp_object.errors
    end

    # Use this to create a new +LockedLDPObjects+ and its underlying LDP instance. attrs populate the new object's
    # attributes
    def self.new_locked_ldp_object(*attrs)
      new(ldp_obj: derived_af_class.new(*attrs))
    end

    # Override this in your subclasses to control what attributes are automatically listed in the attributes list
    def self.display_attribute_names
      self.attribute_names - [:id]
    end

    # An array of attribute names that are safe to be used for safe_params calls in controllers. ID is _never_ a safe
    # attribute for forms to modify. Subclasses should override this and remove any other sensitive attributes from
    # this array
    #
    # a Work +LockedLDPObject+ might choose to protect its +owner+ attribute by overriding this method:
    #
    #  def self.safe_attributes
    #    super - [:owner]
    #  end
    #
    # and then enforce that in a controller like works_controller.rb:
    #    def work_params
    #      params[:work].permit(Work.safe_attributes)
    #    end
    def self.safe_attributes
      self.attribute_names - [:id]
    end

    # Accepts a symbol representing the attribute name, and returns a Hash containing
    # metadata about an object's attributes.
    #
    # Given a subclass +Work+ with an attribute declaration:
    #   has_attribute :title, ::RDF::Vocab::DC.title, solrize_for: [:search, :facet]
    #
    # then the Hash returned by <tt>Work.attribute_metadata(:title)</tt> would be:
    #   {
    #      :predicate => #<RDF::Vocabulary::Term:0x3fe32a1d1a30 URI:http://purl.org/dc/terms/title>,
    #      :multiple => false,
    #      :solrize_for => [:search, :facet],
    #      :type => :string,
    #      :solr_names => ["title_tesim", "title_sim"]
    #   }
    def self.attribute_metadata(attribute_name)
      self.attribute_cache[attribute_name]
    end

    # Accepts a String name of a name-mangled solr field, and returns the symbol of the attribute that corresponds to it
    #
    # Given a subclass +Work+ with an attribute declaration:
    #   has_attribute :title, ::RDF::Vocab::DC.title, solrize_for: [:search, :facet]
    #
    # then:
    #   Work.solr_name_to_attribute_name('title_tesim')
    #   => :title
    def self.solr_name_to_attribute_name(solr_name)
      self.reverse_solr_name_cache[solr_name]
    end

    # Accepts a string id of an object in the LDP, and returns a +LockedLDPObjects+ representation of that object
    # or raises <tt>JupiterCore::ObjectNotFound</tt> if there is no object corresponding to that id
    def self.find(id)
      results_count, results, = perform_solr_query(%Q(_query_:"{!raw f=id}#{id}"), '', false)
      raise ObjectNotFound, "Couldn't find #{self} with id='#{id}'" if results_count == 0
      raise MultipleIdViolationError if results_count > 1

      new(solr_doc: results.first)
    end

    # Returns an array of all +LockedLDPObject+ in the LDP
    def self.all
      _, results, = perform_solr_query('', '', false)
      results.map { |res| new(solr_doc: res) }
    end

    # Accepts a hash of name-value pairs to query for, and returns an Array of matching +LockedLDPObject+
    #
    # For example:
    #   Work.where(title: 'Test upload')
    #    => [#<Work id: "e5f4a074-5bcb-48a4-99ee-12bc83cef291", title: "Test upload", subject: "", creator: "", contributor: "", description: "", publisher: "", date_created: "", language: "", doi: "", member_of_paths: ["98124366-c8b2-487a-95f0-a1c18c805ddd/799e2eee-5435-4f08-bf3d-fc256fee9447"]>
    def self.where(attributes)
      attr_queries = []
      attr_queries << attributes.map do |k, v|
        solr_key = self.attribute_metadata(k)[:solr_names].first
        %Q(_query_:"{!field f=#{solr_key}}#{v}")
      end

      _, results = perform_solr_query(attr_queries, '', false)
      results.map { |res| new(solr_doc: res) }
    end

    # Performs a solr search using the given query and filtered query strings.
    # Returns an instance of +SearchResult+ providing result counts, +LockedLDPObject+ representing results, and
    # access to result facets.
    def self.search(q: '', fq: '', as: nil)
      raise ArgumentError, 'as: must specify a user!' if as.present? && !as.is_a?(User)
      base_query = []
      ownership_query = calculate_ownership_query(as)

      # Our query permissions are white-list based. You only get public results unless the results of +calculate_ownership_query+
      # assign you additional permissions based on the user passed to it.
      base_query << %Q((_query_:"{!raw f=visibility_ssim}public"#{ownership_query}))
      base_query << q if q.present?

      results_count, results, facets = perform_solr_query(base_query, fq, true, self.facets.map(&:to_s))

      SearchResults.new(self, results_count, facets, results.map { |res| new(solr_doc: res) })
    end

    def self.valid_visibilities
      ['public', 'private', 'authenticated']
    end

    private

    attr_reader :ldp_object
    attr_accessor :solr_representation

    def initialize(solr_doc: nil, ldp_obj: nil)
      raise ArgumentError if solr_doc.present? && ldp_obj.present?
      self.solr_representation = solr_doc if solr_doc.present?
      self.ldp_object = ldp_obj if ldp_obj.present?
    end

    def method_missing(name, *args, &block)
      return super unless self.class.send(:derived_af_class).instance_methods.include?(name)
      raise LockedInstanceError, 'This is a locked cache instance and does not respond to the method you attempted '\
                                 "to call (##{name}). However, the locked instance DOES respond to ##{name}. Use "\
                                 'unlock_and_fetch_ldp_object to load a writable copy (SLOW).'
    end

    # Looks pointless, but keeps rubocop happy because of the error-message refining +method_missing+ above
    def respond_to_missing?(*_args); super; end

    def ldp_object=(obj)
      @ldp_object = obj
      @solr_representation = @ldp_object.to_solr
      @ldp_object.owning_object = self
      @ldp_object
    end

    # private class methods
    class << self

      private

      def perform_solr_query(q, fq, facet, facet_fields = [])
        query = []
        query << %Q(_query_:"{!raw f=has_model_ssim}#{derived_af_class_name}")
        query.append(q) if q.present?

        response = ActiveFedora::SolrService.instance.conn.get('select', params: { q: query.join(' AND '),
                                                                                   fq: fq,
                                                                                   facet: facet,
                                                                                   'facet.field': facet_fields })

        raise SearchFailed unless response['responseHeader']['status'] == 0

        [response['response']['numFound'], response['response']['docs'], response['facet_counts']]
      end

      # Clones inherited arrays/maps so that local mutation doesn't propogate to the parent
      # also sets up basic attributes that every child class has: +id+, +owner+, and +visibility+
      def inherited(child)
        super
        child.attribute_names = self.attribute_names ? self.attribute_names.dup : [:id]
        child.reverse_solr_name_cache = self.reverse_solr_name_cache ? self.reverse_solr_name_cache.dup : {}
        child.attribute_cache = self.attribute_cache ? self.attribute_cache.dup : {}
        child.facets = self.facets ? self.facets.dup : []
        child.solr_calc_attributes = self.solr_calc_attributes.present? ? self.solr_calc_attributes.dup : {}
        # child.derived_af_class

        # If there's no class between +LockedLdpObject+ and this child that's
        # already had +visibility+ and +owner+ defined, define them.
        child.class_eval do
          unless attribute_names.include?(:visibility)
            has_attribute :visibility, ::VOCABULARY[:jupiter_core].visibility, solrize_for: [:exact_match, :facet]
          end
          unless attribute_names.include?(:owner)
            has_attribute :owner, ::VOCABULARY[:jupiter_core].owner, solrize_for: [:exact_match]
          end
        end
      end

      def ldp_object_includes(module_name)
        derived_af_class.send(:include, module_name)
      end

      # derive additional restriction or broadening of the visibilitily query on top of the default
      # "where visibility is public" restriction
      def calculate_ownership_query(user)
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

      def derived_af_class_name
        return AF_CLASS_PREFIX + self.to_s if self.name.present?
        "AnonymousDerivedClass#{self.object_id}"
      end

      def unlocked(&block)
        derived_af_class.class_eval(&block)
      end

      # for a class Book, this would generate an ActiveFedora subclass "IRBook"
      def generate_af_class
        if const_defined? derived_af_class_name
          raise AlreadyDefinedError, "The attempted ActiveFedora class generation name '#{derived_af_class_name}' is"\
                                     'already defined'
        end
        self.af_parent_class ||= ActiveFedora::Base

        af_class = Class.new(self.af_parent_class) do
          attr_accessor :owning_object

          validate :visibility_must_be_known

          def visibility_must_be_known
            return true if visibility.present? && owning_object.class.valid_visibilities.include?(visibility)
            errors.add(:visibility, "#{visibility} is not a known visibility")
          end

          def owning_class
            self.class.owning_class
          end

          def self.owning_class
            @owning_class
          end

          # a single common indexer for all subclasses which leverages stored property metadata to DRY up indexing
          def self.indexer
            JupiterCore::Indexer
          end

          # Methods defined on the +owning_object+ can be called by the "unlocked" methods defined on the ActiveFedora
          # object
          def method_missing(name, *args, &block)
            if owning_object.respond_to?(name, true)
              owning_object.send(name, *args, &block)
            else
              super
            end
          end

          def respond_to_missing?(name, include_private = false)
            owning_object.respond_to?(name, include_private) || super
          end
        end

        af_class.instance_variable_set(:@owning_class, self)
        Object.const_set(derived_af_class_name, af_class)
        self.af_parent_class = af_class
        af_class
      end

      def derived_af_class
        @derived_af_class ||= generate_af_class
      end

      def solr_calculated_attribute(name, solrize_for:, &callable)
        raise PropertyInvalidError unless callable.respond_to?(:call)
        raise PropertyInvalidError unless name.present?
        raise PropertyInvalidError unless solrize_for.present? && solrize_for.is_a?(Symbol)

        self.solr_calc_attributes ||= {}
        self.solr_calc_attributes[name] = { type: SOLR_DESCRIPTOR_MAP[solrize_for], callable: callable }
      end

      def has_multival_attribute(name, predicate, solrize_for: [], type: :string)
        has_attribute(name, predicate, multiple: true, solrize_for: solrize_for, type: type)
      end

      # a utility DSL for declaring attributes which allows us to store knowledge of them.
      def has_attribute(name, predicate, multiple: false, solrize_for: [], type: :string)
        raise PropertyInvalidError unless name.is_a? Symbol
        raise PropertyInvalidError unless predicate.present?

        # TODO: keep this conveinience, or push responsibility for [] onto the callsite?
        solrize_for = [solrize_for] unless solrize_for.is_a? Array

        # index should contain only some combination of :search, :sort, :facet, :symbol, and :path
        # this isn't an exhaustive layering over this mess
        # https://github.com/mbarnett/solrizer/blob/e5dd2bd571b9ebdb8a8ab214574075c28951e53e/lib/solrizer/default_descriptors.rb
        # but it helps
        raise PropertyInvalidError if solrize_for.count { |item| !SOLR_DESCRIPTOR_MAP.keys.include?(item) } > 0

        # TODO: type validation

        self.attribute_names << name

        solr_name_cache ||= []
        solrize_for.each do |descriptor|
          solr_name = Solrizer.solr_name(name, SOLR_DESCRIPTOR_MAP[descriptor], type: type)
          solr_name_cache << solr_name
          self.reverse_solr_name_cache[solr_name] = name
        end

        self.facets << Solrizer.solr_name(name, SOLR_DESCRIPTOR_MAP[:facet], type: type) if solrize_for.include?(:facet)
        self.facets << Solrizer.solr_name(name, SOLR_DESCRIPTOR_MAP[:path], type: type) if solrize_for.include?(:path)

        self.attribute_cache[name] = {
          predicate: predicate,
          multiple: multiple,
          solrize_for: solrize_for,
          type: type,
          solr_names: solr_name_cache
        }

        define_method name do
          return ldp_object.send(name).freeze if ldp_object.present?
          val = solr_representation[solr_name_cache.first]
          return val.freeze if val.nil? || multiple
          return val.first.freeze
        end

        define_method "#{name}=" do |*_args|
          raise LockedInstanceError, 'The Locked LDP object cannot be mutated outside of an unlocked block or without'\
                                     'calling unlock_and_fetch_ldp_object to load a writable copy (SLOW).'
        end

        derived_af_class.class_eval do
          property name, predicate: predicate, multiple: multiple do |index|
            index.type type if type.present?
            index.as(*(solrize_for.map { |idx| SOLR_DESCRIPTOR_MAP[idx] }))
          end
        end
      end

    end

  end
end
