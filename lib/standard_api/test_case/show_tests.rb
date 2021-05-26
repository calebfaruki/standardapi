module StandardAPI
  module TestCase
    module ShowTests
      extend ActiveSupport::Testing::Declarative

      test '#show.json' do
        m = create_model

        get resource_path(:show, id: m.id, format: :json)
        assert_response :ok
        assert_equal m, @controller.instance_variable_get("@#{singular_name}")
        assert JSON.parse(response.body).is_a?(Hash)
      end

      test '#show.json params[:include]' do
        m = create_model
        get resource_path(:show, id: m.id, include: includes, format: :json)
        assert_response :ok

        json = JSON.parse(response.body)
        includes.each do |included|
          assert json.key?(included.to_s), "#{included.inspect} not included in response"

          association = @controller.instance_variable_get("@#{singular_name}").class.reflect_on_association(included)
          next if !association

          if ['belongs_to', 'has_one'].include?(association.macro.to_s)
            view_attributes(@controller.instance_variable_get("@#{singular_name}").send(included)) do |key, value|
              assert_equal json[included.to_s][key.to_s], value
            end
          else
            m = @controller.instance_variable_get("@#{singular_name}").send(included).first.try(:reload)
            
            m_json = if m && m.has_attribute?(:id)
              json[included.to_s].find { |x| x['id'] == normalize_to_json(m, :id, m.id) }
            elsif m
              json[included.to_s].find { |x| x.keys.all? { |key| x[key] == normalize_to_json(m, key, m[key]) } }
            else
              nil
            end

            view_attributes(m).each do |key, value|
              message = "Model / Attribute: #{m.class.name}##{key}"
              if m_json[key.to_s].nil?
                assert_nil normalize_to_json(m, key, value), message
              else
                assert_equal m_json[key.to_s], normalize_to_json(m, key, value), message
              end
            end
            
          end
        end
      end

      test '#show.json mask_for' do
        m = create_model

        # This is just to instance @controller
        get resource_path(:show, id: m.id, format: :json)

        # If #mask_for isn't defined by StandardAPI we don't know how to
        # test other's implementation of #mask_for. Return and don't test.
        return if @controller.method(:mask_for).owner != StandardAPI

        @controller.define_singleton_method(:mask_for) do |table_name|
          { id: m.id + 1 }
        end
        assert_raises(ActiveRecord::RecordNotFound) do
          get resource_path(:show, id: m.id, format: :json)
        end
      end

    end
  end
end
