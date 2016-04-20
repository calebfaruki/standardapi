require 'test_helper'

class PropertiesControllerTest < ActionController::TestCase
  include StandardAPI::TestCase

  # = Routing Tests
  #
  # These also can't be included in StandardAPI::TestCase because we don't know
  # how the other's routes are setup
  test 'route to #create.json' do
    assert_routing({ method: :post, path: "/#{plural_name}" }, path_with_action('create'))
    assert_recognizes(path_with_action('create'), { method: :post, path: "/#{plural_name}" })
  end

  test 'route to #calculate.json' do
    assert_routing "/#{plural_name}/calculate", path_with_action('calculate')
    assert_recognizes(path_with_action('calculate'), "/#{plural_name}/calculate")
  end

  test 'route to #destroy.json' do
    assert_routing({ method: :delete, path: "/#{plural_name}/1" }, path_with_action('destroy', id: '1'))
    assert_recognizes(path_with_action('destroy', id: '1'), { method: :delete, path: "/#{plural_name}/1" })
  end

  test 'route to #index.json' do
    assert_routing "/#{plural_name}", path_with_action('index')
    assert_recognizes path_with_action('index'), "/#{plural_name}"
  end

  test 'route to #show.json' do
    assert_routing "/#{plural_name}/1", path_with_action('show', id: '1')
    assert_recognizes(path_with_action('show', id: '1'), "/#{plural_name}/1")
  end

  test 'route to #update.json' do
    assert_routing({ method: :put, path: "#{plural_name}/1" }, path_with_action('update', id: '1'))
    assert_recognizes(path_with_action('update', id: '1'), { method: :put, path: "/#{plural_name}/1" })
    assert_routing({ method: :patch, path: "/#{plural_name}/1" }, path_with_action('update', id: '1'))
    assert_recognizes(path_with_action('update', id: '1'), { method: :patch, path: "/#{plural_name}/1" })
  end

  test 'route to #schema.json' do
    assert_routing({ method: :get, path: "/#{plural_name}/schema" }, path_with_action('schema'))
    assert_recognizes(path_with_action('schema'), { method: :get, path: "/#{plural_name}/schema" })
  end

  # = Controller Tests

  test 'Controller#model_orders defaults to []' do
    @controller = ReferencesController.new
    assert_equal @controller.send(:model_orders), []
  end

  test 'Controller#model_includes defaults to []' do
    @controller = ReferencesController.new
    assert_equal @controller.send(:model_includes), []
  end

  test 'Controller#model_params defaults to []' do
    @controller = ReferencesController.new
    assert_equal @controller.send(:model_params), []
  end

  # = View Tests

  test 'rendering null attribute' do
    property = create(:property)
    get :show, params: { id: property.id, include: [:landlord], format: 'json' }
    assert JSON(response.body).has_key?('landlord')
    assert_equal nil, JSON(response.body)['landlord']
  end

  test '#index.json uses overridden partial' do
    create(:property, photos: [build(:photo)])
    get :index, params: { include: [:photos], format: 'json' }

    photo = JSON(response.body)[0]['photos'][0]
    assert photo.has_key?('template')
    assert_equal 'photos/_photo', photo['template']
  end

  test '#show.json uses overridden partial' do
    property = create(:property, photos: [build(:photo)])
    get :show, params: { id: property.id, include: [:photos], format: 'json' }

    photo = JSON(response.body)['photos'][0]
    assert photo.has_key?('template')
    assert_equal 'photos/_photo', photo['template']
  end

  test '#schema.json uses overridden partial' do
    @controller = PhotosController.new
    get :schema, params: { format: :json }

    schema = JSON(response.body)
    assert schema.has_key?('template')
    assert_equal 'photos/schema', schema['template']
  end

  test 'belongs_to polymorphic association' do
    property = create(:photo)
    reference = create(:reference, subject: property)
    @controller = ReferencesController.new
    get :show, params: { id: reference.id, include: :subject, format: :json }
    
    json = JSON(response.body)
    assert_equal 'photos/_photo', json['subject']['template']
  end

  test 'has_many association' do
    p = create(:property, photos: [build(:photo)])
    get :index, params: { include: [:photos], format: 'json' }
    assert_equal p.photos.first.id, JSON(response.body)[0]['photos'][0]['id']
  end

  test 'belongs_to association' do
    account = create(:account)
    photo = create(:photo, account: account)
    @controller = PhotosController.new
    get :show, params: { id: photo.id, include: :account, format: :json }
    assert_equal account.id, JSON(response.body)['account']['id']
  end

  test 'has_one association' do
    account = create(:account)
    property = create(:property, landlord: account)
    get :show, params: { id: property.id, include: :landlord, format: :json }
    assert_equal account.id, JSON(response.body)['landlord']['id']
  end

  test 'include method' do
    property = create(:property)
    get :show, params: { id: property.id, include: :english_name, format: :json }
    assert_equal 'A Name', JSON(response.body)['english_name']
  end

  test 'include with where key' do
    property = create(:property)
    get :show, params: { id: property.id, include: { photos: { where: { id: 1 } } }, format: :json }
    assert JSON(response.body)['photos']
  end
  
  test 'include with order key' do
    property = create(:property)
    get :show, params: { id: property.id, include: { photos: { order: { id: :asc } } }, format: :json }
    assert JSON(response.body)['photos']
  end

  # Includes Test

  test 'Includes::normailze' do
    method = StandardAPI::Includes.method(:normalize)
    assert_equal method.call(:x), { 'x' => {} }
    assert_equal method.call([:x, :y]), { 'x' => {}, 'y' => {} }
    assert_equal method.call([ { x: true }, { y: true } ]), { 'x' => {}, 'y' => {} }
    assert_equal method.call({ x: true, y: true }), { 'x' => {}, 'y' => {} }
    assert_equal method.call({ x: { y: true } }), { 'x' => { 'y' => {} } }
    assert_equal method.call({ x: { y: {} } }), { 'x' => { 'y' => {} } }
    assert_equal method.call({ x: [:y] }), { 'x' => { 'y' => {} } }


    assert_equal method.call({ x: { where: { y: false } } }), { 'x' => { 'where' => { 'y' => false } } }
    assert_equal method.call({ x: { order: { y: :asc } } }), { 'x' => { 'order' => { 'y' => :asc } } }
  end

  # sanitize({:key => {}}, [:key]) # => {:key => {}}
  # sanitize({:key => {}}, {:key => true}) # => {:key => {}}
  # sanitize({:key => {}}, :value => {}}, [:key]) => # Raises ParseError
  # sanitize({:key => {}}, :value => {}}, {:key => true}) => # Raises ParseError
  # sanitize({:key => {:value => {}}}, {:key => [:value]}) # => {:key => {:value => {}}}
  # sanitize({:key => {:value => {}}}, {:key => {:value => true}}) # => {:key => {:value => {}}}
  # sanitize({:key => {:value => {}}}, [:key]) => # Raises ParseError
  test 'Includes::sanitize' do
    method = StandardAPI::Includes.method(:sanitize)
    assert_equal method.call(:x, [:x]), { 'x' => {} }
    assert_equal method.call(:x, {:x => true}), { 'x' => {} }

    assert_raises(ActionController::UnpermittedParameters) do
      method.call([:x, :y], [:x])
    end

    assert_raises(ActionController::UnpermittedParameters) do
      method.call([:x, :y], {:x => true})
    end

    assert_raises(ActionController::UnpermittedParameters) do
      method.call({:x => true, :y => true}, [:x])
    end
    assert_raises(ActionController::UnpermittedParameters) do
      method.call({:x => true, :y => true}, {:x => true})
    end
    assert_raises(ActionController::UnpermittedParameters) do
      method.call({ x: { y: true }}, { x: true })
    end

    assert_equal method.call({ x: { y: true }}, { x: { y: true } }), { 'x' => { 'y' => {} } }
    
    
    

  end

  # Order Test

  test 'Orders::sanitize(:column, [:column])' do
    method = StandardAPI::Orders.method(:sanitize)

    assert_equal :x, method.call(:x, :x)
    assert_equal :x, method.call(:x, [:x])
    assert_equal :x, method.call([:x], [:x])
    assert_raises(ActionController::UnpermittedParameters) do
      method.call(:x, :y)
    end

    assert_equal({ x: :asc }, method.call({ x: :asc }, :x))
    assert_equal({ x: :desc }, method.call({ x: :desc }, :x))
    assert_equal([{ x: :desc}, {y: :desc }], method.call({ x: :desc, y: :desc }, [:x, :y]))
    assert_equal({ x: :asc }, method.call([{ x: :asc }], :x))
    assert_equal({ x: :desc }, method.call([{ x: :desc }], :x))
    assert_equal({ x: { asc: :nulls_last } }, method.call([{ x: { asc: :nulls_last } }], :x))
    assert_equal({ x: { asc: :nulls_first } }, method.call([{ x: { asc: :nulls_first } }], :x))
    assert_equal({ x: { desc: :nulls_last } }, method.call([{ x: { desc: :nulls_last } }], :x))
    assert_equal({ x: { desc: :nulls_first }}, method.call([{ x: { desc: :nulls_first } }], :x))
    assert_equal({ relation: :id }, method.call(['relation.id'], { relation: :id }))
    assert_equal({ relation: :id }, method.call([{ relation: :id }], { relation: :id }))
    assert_equal({ relation: :id }, method.call([{ relation: :id }], [{ relation: :id }]))
    assert_equal({ relation: :id }, method.call([{ relation: [:id] }], { relation: [:id] }))
    assert_equal({ relation: :id }, method.call([{ relation: [:id] }], [{ relation: [:id] }]))
    assert_equal({ relation: { id: :desc } }, method.call([{'relation.id' => :desc}], { relation: :id }))
    assert_equal({ relation: { id: :desc } }, method.call([{ relation: { id: :desc } }], { relation: [:id] }))
    assert_equal({ relation: { id: :desc } }, method.call([{ relation: { id: :desc } }], [{ relation: [:id] }]))
    assert_equal({ relation: { id: :desc } }, method.call([{ relation: [{ id: :desc }] }], [{ relation: [:id] }]))
    assert_equal({ relation: { id: :desc } }, method.call([{ relation: [{ id: :desc }] }], [{ relation: [:id] }]))
    assert_equal({ relation: {:id => {:asc => :nulls_last}} }, method.call([{ relation: {:id => {:asc => :nulls_last}} }], [{ relation: [:id] }]))
    assert_equal({ relation: {:id => {:asc => :nulls_last}} }, method.call([{ relation: {:id => {:asc => :nulls_last}} }], [{ relation: [:id] }]))
    assert_equal({ relation: {:id => [{:asc => :nulls_last}]} }, method.call([{ relation: {:id => [{:asc => :nulls_last}]} }], [{ relation: [:id] }]))
    assert_equal({ relation: {:id => [{:asc => :nulls_last}]} }, method.call([{ relation: {:id => [{:asc => :nulls_last}]} }], [{ relation: [:id] }]))
  end

end
