record.attributes.each do |name, value|
  # Skip if attribute is included in excludes
  next if defined?(excludes) && excludes[record.model_name.singular.to_sym].try(:find) { |x| x.to_s == name.to_s }
  json.set! name, value
end

includes.each do |inc, subinc|
  association = record.class.reflect_on_association(inc)
  if association
    json.set! inc do
      collection = [:has_many, :has_and_belongs_to_many].include?(association.macro)

      if collection
        partial = model_partial(association.klass)
        json.array! record.send(inc), partial: partial, as: partial.split('/').last, locals: { includes: subinc }
      else
        if record.send(inc).nil?
          json.null!
        else
          partial = model_partial(record.send(inc))
          json.partial! partial, partial.split('/').last.to_sym => record.send(inc), includes: subinc
        end
      end
    end
  else
    json.set! inc do
      if record.send(inc).nil?
        json.null!
      else
        record.send(inc).as_json
      end
    end
  end
end

if !record.errors.blank?
  json.set! 'errors', record.errors.to_hash
end