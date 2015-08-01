require 'active_support/test_case'

module ActionController
  class StandardAPI < ActionController::Base
    module TestCase
    end
  end
end

require File.expand_path(File.join(__FILE__, '../test_case/calculate_tests'))
require File.expand_path(File.join(__FILE__, '../test_case/create_tests'))
require File.expand_path(File.join(__FILE__, '../test_case/destroy_tests'))
require File.expand_path(File.join(__FILE__, '../test_case/index_tests'))
require File.expand_path(File.join(__FILE__, '../test_case/show_tests'))
require File.expand_path(File.join(__FILE__, '../test_case/update_tests'))

module ActionController::StandardAPI::TestCase
      
  def self.included(klass)
    [:filters, :orders, :includes].each do |attribute|
      klass.send(:class_attribute, attribute)
    end
    klass.extend(ClassMethods)
    
    klass.controller_class.action_methods.each do |action|
      klass.include("ActionController::StandardAPI::TestCase::#{action.capitalize}Tests".constantize)
    end
  end

  def model
    self.class.model
  end

  def setup
    @api_key = set_api_key
    @account = login(create(:admin))
  end

  def create_model(attrs={})
    create(model.name.underscore, attrs)
  end

  def singular_name
    model.model_name.singular
  end
  
  def plural_name
    model.model_name.plural
  end
    
  def create_webmocks(attributes)
    attributes.each do |attribute, value|
      validators = self.class.model.validators_on(attribute)
        
      if validators.map(&:class).include?(PhoneValidator)
        stub_twilio_lookup(PhoneValidator.normalize(value))
      end
    end
  end
    
  def normalize_attribute(attribute, value)
    if model == Listing && ['size', 'maximum_contiguous_size', 'minimum_divisible_size'].include?(attribute)
      return value.round(-1)
    end
      
    validators = self.class.model.validators_on(attribute)
      
    if validators.map(&:class).include?(PhoneValidator)
      PhoneValidator.normalize(value)
    else
      value
    end
  end
    
  def normalize_to_json(attribute, value)
    value = normalize_attribute(attribute, value)
      
    return nil if value.nil?
      
    if model.column_types[attribute].is_a?(ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Decimal)
      "#{value}.0"
    elsif model.column_types[attribute].is_a?(ActiveRecord::AttributeMethods::TimeZoneConversion::TimeZoneConverter)
      value.to_datetime.utc.iso8601.gsub(/\+00:00$/, 'Z')
    else
      value
    end
  end

  module ClassMethods
    
    def include_filter_tests
      model.instance_variable_get('@filters').each do |filter|
        next if filter[1].is_a?(Proc) # Custom filter
        next if model.reflect_on_association(filter[0]) # TODO: Relation Filter Tests

        define_method("test_model_filter_#{filter[0]}") do
          m = create_model
          value = m.send(filter[0])

          assert_predicate = -> (predicate) {
            get :index, where: predicate, format: 'json'
            assert_equal model.filter(predicate).to_sql, assigns(plural_name).to_sql
          }

          # TODO: Test array
          case model.columns_hash[filter[0].to_s].type
          when :jsonb, :json # JSON
            assert_predicate.call({ filter[0] => value })
          else
            case value
            when Array
              assert_predicate.call({ filter[0] => value }) # Overlaps
              assert_predicate.call({ filter[0] => value[0] }) # Contains
            else
              assert_predicate.call({ filter[0] => value }) # Equality
              assert_predicate.call({ filter[0] => { gt: value } }) # Greater Than
              assert_predicate.call({ filter[0] => { greater_than: value } })
              assert_predicate.call({ filter[0] => { lt: value } }) # Less Than
              assert_predicate.call({ filter[0] => { less_than: value } })
              assert_predicate.call({ filter[0] => { gte: value } }) # Greater Than or Equal To
              assert_predicate.call({ filter[0] => { gteq: value } })
              assert_predicate.call({ filter[0] => { greater_than_or_equal_to: value } })
              assert_predicate.call({ filter[0] => { lte: value } }) # Less Than or Equal To
              assert_predicate.call({ filter[0] => { lteq: value } })
              assert_predicate.call({ filter[0] => { less_than_or_equal_to: value } })
            end
          end
        end
      end
    end

    def model=(val)
      @model = val
    end

    def model
      return @model if defined?(@model) && @model

      klass_name = controller_class.name.gsub(/Controller$/, '').singularize
        
      begin
        @model = klass_name.constantize
      rescue NameError
        raise e unless e.message =~ /uninitialized constant #{klass_name}/
      end

      if @model.nil?
        raise "@model is nil: make sure you set it in your test using `self.model = ModelClass`."
      else
        @model
      end
    end

  end

end
