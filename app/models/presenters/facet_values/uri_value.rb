class Presenters::FacetValues::URIValue < Presenters::FacetValues::DefaultPresenter

  protected

  def translate_uri(vocab, uri)
    raise ArgumentError unless vocab.is_a? Symbol
    raise ArgumentError, "Vocabulary not found: #{vocab}" unless CONTROLLED_VOCABULARIES.key?(vocab)
    label = CONTROLLED_VOCABULARIES[vocab].from_uri(uri)
    I18n.t("controlled_vocabularies.#{vocab}.#{label}")
  end

end
