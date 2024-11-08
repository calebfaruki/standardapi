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
        mod = child.classify.constantize
        prefix = child.delete_suffix('_acl').gsub('/', '_')

        [:sorts, :includes, :attributes].each do |m|
          next if !mod.instance_methods.include?(m)
          mod.send :alias_method, "#{prefix}_#{m}".to_sym, m
          mod.send :remove_method, m
        end

        if mod.instance_methods.include?(:nested)
          mod.send :alias_method, "nested_#{prefix}_attributes".to_sym, :nested
          mod.send :remove_method, :nested
        end

        if mod.instance_methods.include?(:filter)
          mod.send :alias_method, "filter_#{prefix}_params".to_sym, :filter
          mod.send :remove_method, :filter
        end

        application_controller.include mod
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

      if self.respond_to?("nested_#{model_name(model)}_attributes", true)
        self.send("nested_#{model_name(model)}_attributes").each do |relation|
          relation = model.reflect_on_association(relation)
          attributes_key = "#{relation.name}"

          if model_params.has_key?(attributes_key)
            filter_method = "filter_#{relation.klass.base_class.model_name.singular}_params"
            if model_params[attributes_key].nil?
              permitted_params[attributes_key] = nil
            elsif model_params[attributes_key].is_a?(Array) && model_params[attributes_key].all? { |a| a.keys.map(&:to_sym) == [:id] }
              permitted_params["#{relation.name.to_s.singularize}_ids"] = model_params[attributes_key].map{|a| a['id']}
            elsif self.respond_to?(filter_method, true)
              permitted_params[attributes_key] = if model_params[attributes_key].is_a?(Array)
                models = relation.klass.find(model_params[attributes_key].map { |i| i['id'] }.compact)
                model_params[attributes_key].map { |i|
                  i_params = self.send(filter_method, i, allow_id: true)
                  if i_params['id']
                    r = models.find { |r| r.id == i_params['id'] }
                    r.assign_attributes(i_params)
                    r
                  else
                    relation.klass.new(i_params)
                  end
                }
              else
                i_params = self.send(filter_method, model_params[attributes_key], allow_id: true)
                if i_params['id']
                  r = relation.klass.find(i_params['id'])
                  r.assign_attributes(i_params)
                  r
                else
                  relation.klass.new(i_params)
                end
              end
            else
              permitted_params[attributes_key] = if model_params[attributes_key].is_a?(Array)
                models = relation.klass.find(model_params[attributes_key].map { |i| i['id'] }.compact)
                model_params[attributes_key].map { |i|
                  i_params = filter_model_params(i, relation.klass.base_class, allow_id: true)
                  if i_params['id']
                    r = models.find { |r| r.id == i_params['id'] }
                    r.assign_attributes(i_params)
                    r
                  else
                    relation.klass.new(i_params)
                  end
                }
              else
                i_params = filter_model_params(model_params[attributes_key], relation.klass.base_class, allow_id: true)
                if i_params['id']
                  r = relation.klass.find(i_params['id'])
                  r.assign_attributes(i_params)
                  r
                else
                  relation.klass.new(i_params)
                end
              end
            end
          elsif relation.collection? && model_params.has_key?("#{relation.name.to_s.singularize}_ids")
            permitted_params["#{relation.name.to_s.singularize}_ids"] = model_params["#{relation.name.to_s.singularize}_ids"]
          elsif model_params.has_key?(relation.foreign_key)
            permitted_params[relation.foreign_key] = model_params[relation.foreign_key]
            permitted_params[relation.foreign_type] = model_params[relation.foreign_type] if relation.polymorphic?
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
