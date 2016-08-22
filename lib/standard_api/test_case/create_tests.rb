module StandardAPI
  module TestCase
    module CreateTests
      extend ActiveSupport::Testing::Declarative

      def setup
        @request.content_type="application/json"
        super
      end
      
      test '#create.json' do
        attrs = attributes_for(singular_name, :nested).select{|k,v| !model.readonly_attributes.include?(k.to_s) }
        create_webmocks(attrs)

        assert_difference("#{model.name}.count") do
          post :create, params: {singular_name => attrs}, format: :json
          assert_response :created
          assert assigns(singular_name)

          json = JSON.parse(response.body)
          assert json.is_a?(Hash)

          m = assigns(singular_name)
          view_attributes(m.reload).select { |x| attrs.keys.map(&:to_s).include?(x) }.each do |key, value|
            message = "Model / Attribute: #{m.class.name}##{key}"
            if value.is_a?(BigDecimal)
              assert_equal normalize_to_json(m, key, attrs[key.to_sym]).to_s.to_f, json[key.to_s].to_s.to_f, message
            else
              assert_equal normalize_to_json(m, key, attrs[key.to_sym]), json[key.to_s], message
            end
          end
        end
      end

      test '#create.json with nested attributes' do
        attrs = attributes_for(singular_name, :nested).select{|k,v| !model.readonly_attributes.include?(k.to_s) }
        create_webmocks(attrs)

        assert_difference("#{model.name}.count") do
          post :create, params: {singular_name => attrs}, format: :json
          assert_response :created
          assert assigns(singular_name)

          json = JSON.parse(response.body)
          assert json.is_a?(Hash)
          m = assigns(singular_name).reload
          view_attributes(m).select { |x| attrs.keys.map(&:to_s).include?(x) }.each do |key, value|
            message = "Model / Attribute: #{m.class.name}##{key}"
            assert_equal normalize_attribute(m, key, attrs[key.to_sym]), value, message
          end
        end
      end

      test '#create.json with invalid attributes' do
        trait = FactoryGirl.factories[singular_name].definition.defined_traits.any? { |x| x.name.to_s == 'invalid' }

        if !trait
          Rails.logger.try(:warn, "No invalid trait for #{model.name}. Skipping invalid tests")
          warn("No invalid trait for #{model.name}. Skipping invalid tests")
          return
        end

        attrs = attributes_for(singular_name, :invalid).select{|k,v| !model.readonly_attributes.include?(k.to_s) }
        create_webmocks(attrs)

        assert_difference("#{model.name}.count", 0) do
          post :create, params: {singular_name => attrs}, format: :json
          assert_response :bad_request
          json = JSON.parse(response.body)
          assert json.is_a?(Hash)
          assert json['errors']
        end
      end
      
      test '#create.html with invalid attributes renders edit action' do
        trait = FactoryGirl.factories[singular_name].definition.defined_traits.any? { |x| x.name.to_s == 'invalid' }

        if !trait
          Rails.logger.try(:warn, "No invalid trait for #{model.name}. Skipping invalid tests")
          warn("No invalid trait for #{model.name}. Skipping invalid tests")
          return
        end

        attrs = attributes_for(singular_name, :invalid).select{|k,v| !model.readonly_attributes.include?(k.to_s) }
        create_webmocks(attrs)

        assert_difference("#{model.name}.count", 0) do
          post :create, params: {singular_name => attrs}, format: :html
          assert_response :bad_request
          assert_equal response.body, 'properties#edit.html'
        end
      end

      test '#create.json params[:include]' do
        travel_to Time.now do
          attrs = attributes_for(singular_name, :nested).select{ |k,v| !model.readonly_attributes.include?(k.to_s) }
          create_webmocks(attrs)

          assert_difference("#{model.name}.count") do
            post :create, params: {singular_name => attrs, :include => includes}, format: :json
            assert_response :created
            assert assigns(singular_name)

            json = JSON.parse(response.body)
            assert json.is_a?(Hash)
            includes.each do |included|
              assert json.key?(included.to_s), "#{included.inspect} not included in response"

              association = assigns(singular_name).class.reflect_on_association(included)
              next if !association

              if ['belongs_to', 'has_one'].include?(association.macro.to_s)
                view_attributes(assigns(singular_name).send(included)) do |key, value|
                  assert_equal json[included.to_s][key.to_s], normalize_to_json(assigns(singular_name), key, value)
                end
              else
                m = assigns(singular_name).send(included).first.try(:reload)

                m_json = if m && m.has_attribute?(:id)
                  json[included.to_s].find { |x| x['id'] == normalize_to_json(m, :id, m.id) }
                elsif m
                  json[included.to_s].find { |x| x.keys.all? { |key| x[key] == normalize_to_json(m, key, m[key]) } }
                else
                  nil
                end

                view_attributes(m).each do |key, value|
                  message = "Model / Attribute: #{m.class.name}##{key}"
                  assert_equal m_json[key.to_s], normalize_to_json(m, key, value)
                end

              end
            end
          end
        end
      end

    end
  end
end
