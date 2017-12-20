class UriValidator < ActiveModel::EachValidator

  def validate_each(record, attr, value)
    raise ArgumentError, "#{attr} must specify a vocabulary to validate against!" if options[:in_vocabulary].blank?
    return if value.blank?
    value = [value] unless value.is_a?(Array) || value.is_a?(ActiveTriples::Relation)
    value.each do |v|
      if ::CONTROLLED_VOCABULARIES[options[:in_vocabulary]].from_uri(v).blank?
        record.errors.add(attr, :not_recognized)
      end
    end
  end

end
