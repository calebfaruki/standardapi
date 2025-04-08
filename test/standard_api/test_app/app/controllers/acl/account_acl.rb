module AccountACL

  def attributes
    [ "property_id", "name" ]
  end

  def sorts
    [ "id" ]
  end

  def includes
    {
      photos: true,
      subject: [ 'landlord' ],
      property: true
    }
  end

end
