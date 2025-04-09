module StandardAPI
  module AccessControlList

    def self.traverse(path, prefix: nil, &block)
      path.children.each do |child|
        if child.file? && child.basename('.rb').to_s.ends_with?('_acl')
          block.call([prefix, child.basename('.rb').to_s].compact.join('/'))
        elsif child.directory?
          traverse(child, prefix: [prefix, child.basename.to_s].compact.join('/'), &block)
        end
      end
    end

    def self.included(application_controller)
      acl_dir = Rails.application.root.join('app', 'controllers', 'acl')
      return if !acl_dir.exist?

      traverse(acl_dir) do |child|
        acl_module = child.classify.constantize
        acl_model = child.delete_suffix('_acl').gsub('/', '_')

        %i[sorts includes attributes context nested filter].each do |acl_method|
          next unless acl_module.instance_methods.include?(acl_method)
          alias_method = case acl_method
            when :nested then "nested_#{acl_model}_attributes"
            when :filter then "filter_#{acl_model}_params"
            else "#{acl_model}_#{acl_method}"
            end

          acl_module.send :alias_method, alias_method, acl_method
          acl_module.send :remove_method, acl_method
        end

        application_controller.include acl_module
      end
    end

    def model_sorts
      if self.respond_to?("#{model.model_name.singular}_sorts", true)
        self.send("#{model.model_name.singular}_sorts")
      else
        []
      end
    end

    def model_params
      if self.respond_to?("filter_#{model_name(model)}_params", true)
        self.send("filter_#{model_name(model)}_params", params[model_name(model)], id: params[:id])
      else
        filter_model_params(params[model_name(model)], model.base_class)
      end
    end

    def filter_model_params(model_params, model, id: nil, allow_id: nil)
      permitted_params = if model_params && self.respond_to?("#{model_name(model)}_attributes", true)
        permits = self.send("#{model_name(model)}_attributes")

        allow_id ? model_params.permit(permits, :id) : model_params.permit(permits)
      else
        ActionController::Parameters.new
      end

      # check if nested attributes defined
      if self.respond_to?("nested_#{model_name(model)}_attributes", true)
        # process allow list for nested attributes
        self.send("nested_#{model_name(model)}_attributes").each do |relation|
          association = model.reflect_on_association(relation)
          association_name = "#{association.name}"
          associated_class = association.klass
          associated_model = associated_class.base_class

          if model_params.has_key?(association_name) # has nested attributes?
            associated_filter_method = "filter_#{associated_model.model_name.singular}_params"
            associated_params = model_params[association_name]
            if associated_params.nil?
              permitted_params[association_name] = nil
            elsif associated_params.is_a?(Array) && associated_params.all? { |a| a.keys.map(&:to_sym) == [:id] }
              permitted_params["#{associated_model.model_name.singular}_ids"] = associated_params.map{|a| a['id']}
            elsif self.respond_to?(associated_filter_method, true)
              permitted_params[association_name] = if associated_params.is_a?(Array)
                models = associated_class.find(associated_params.map { |param| param['id'] }.compact)
                associated_params.map do |param|
                  association_filter_params = self.send(associated_filter_method, param, allow_id: true)
                  if association_filter_params['id']
                    record = models.find { |record| record.id == association_filter_params['id'] }
                    record.assign_attributes(association_filter_params)
                    record
                  else
                    associated_class.new(association_filter_params)
                  end
                end
              else
                association_filter_params = self.send(associated_filter_method, associated_params, allow_id: true)
                if association_filter_params['id']
                  record = associated_class.find(association_filter_params['id'])
                  record.assign_attributes(association_filter_params)
                  record
                else
                  associated_class.new(association_filter_params)
                end
              end
            else
              permitted_params[association_name] = if associated_params.is_a?(Array)
                models = associated_class.find(associated_params.map { |param| param['id'] }.compact)
                associated_params.map do |param|
                  association_filter_params = filter_model_params(param, associated_model, allow_id: true)
                  if association_filter_params['id']
                    record = models.find { |record| record.id == association_filter_params['id'] }
                    record.assign_attributes(association_filter_params)
                    record
                  else
                    associated_class.new(association_filter_params)
                  end
                end
              else
                association_filter_params = filter_model_params(associated_params, associated_model, allow_id: true)
                if association_filter_params['id']
                  record = associated_class.find(association_filter_params['id'])
                  record.assign_attributes(association_filter_params)
                  record
                else
                  associated_class.new(association_filter_params)
                end
              end
            end
          elsif association.collection? && model_params.has_key?("#{association_name.singularize}_ids") # has collection ids?
            permitted_params["#{association_name.singularize}_ids"] = model_params["#{association_name.singularize}_ids"]
          elsif model_params.has_key?(association.foreign_key) # has foreign key?
            permitted_params[association.foreign_key] = model_params[association.foreign_key]
            permitted_params[association.foreign_type] = model_params[association.foreign_type] if association.polymorphic?
          end

          permitted_params.permit!
        end
      end

      permitted_params
    end

    def model_name(model)
      if model.model_name.singular.starts_with?('habtm_')
        model.reflect_on_all_associations.map { |a| a.klass.base_class.model_name.singular }.sort.join('_')
      else
        model.model_name.singular
      end
    end
  end
end
