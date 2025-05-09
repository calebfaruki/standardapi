if model.nil? && controller_name == "application"
  routes = Rails.application.routes.routes.reject(&:internal).collect do |route|
    { name: route.name,
      verb: route.verb,
      path: route.path.spec.to_s.gsub(/\(\.format\)\Z/, ''),
      controller: route.requirements[:controller],
      action: route.requirements[:action],
      array: ['index'].include?(route.requirements[:action]) }
  end

  json.set! 'comment', ::ActiveRecord::Base.connection.database_comment

  json.set! 'routes' do
    json.array!(routes) do |route|
      controller = if controller_name = route[:controller]
        begin
          controller_param = controller_name.underscore
          const_name = "#{controller_param.camelize}Controller"
          const = ActiveSupport::Dependencies.constantize(const_name)
          if const.ancestors.include?(StandardAPI::Controller)
            const
          else
            nil
          end
        rescue NameError
        end
      end

      next if controller.nil?

      resource_limit = controller.resource_limit if controller.respond_to?(:resource_limit)

      json.set! 'path', route[:path]
      json.set! 'method', route[:verb]
      json.set! 'model', controller.model&.name
      json.set! 'array', route[:array]
      json.set! 'limit', resource_limit
    end
  end

  json.set! 'models' do
    models.each do |model|
      json.set! model.name do
        json.partial! partial: schema_partial(model), model: model
      end
    end
  end

else

  json.set! 'attributes' do
    model.columns.each do |column|
      default = column.default ? model.connection.lookup_cast_type_from_column(column).deserialize(column.default) : nil
      type = case model.type_for_attribute(column.name)
      when ::ActiveRecord::Enum::EnumType
        default = model.defined_enums[column.name].key(default)
        "string"
      else
        json_column_type(column.sql_type)
      end

      json.set! column.name do
        json.set! 'type', type
        json.set! 'default', default
        json.set! 'primary_key', column.name == model.primary_key
        json.set! 'null', column.null
        json.set! 'array', column.array
        json.set! 'comment', column.comment
        # TODO: it would be nice if rails responded with a true or false here
        # instead of the function itself
        json.set! 'auto_populated', !!column.auto_populated? if column.respond_to?(:auto_populated?)

        json.set! 'readonly', (if controller.respond_to?("#{ model.model_name.singular }_attributes")
          !controller.send("#{ model.model_name.singular }_attributes").map(&:to_s).include?(column.name)
        else
          model.readonly_attribute?(column.name)
        end)

        validations = model.validators.
          select { |v| v.attributes.include?(column.name.to_sym) }.
          map { |v|
            { v.kind => v.options.empty? ? true : v.options.as_json }
          }.compact
        json.set! 'validations', validations
       end
    end
  end

  json.set! 'limit', resource_limit # This should be removed?
  json.set! 'comment', model.connection.table_comment(model.table_name)

end
