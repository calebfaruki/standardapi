FactoryGirl.define do

  factory :account do
    name            { Faker::Name.name }
  end
  
  factory :photo do
    format          { ['jpg', 'png', 'tiff'].sample }
  end
  
  factory :property do
    name            { Faker::Lorem.words(Kernel.rand(1..4)).join(' ') }
    description     { Faker::Lorem.paragraphs.join("\n\n") }
    constructed     { Kernel.rand(1800..(Time.now.year - 2)) }
    size            { Kernel.rand(1000..10000000).to_f / 100 }
    active          { [true, false].sample }

    trait(:nested)  do
      photos_attributes { [attributes_for(:photo)] }
    end

    trait(:invalid) { name nil }
  end

end