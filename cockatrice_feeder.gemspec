Gem::Specification.new do |s|
  s.name        = 'cockatrice_feeder'
  s.version     = '0.0.0'
  s.date        = '2020-11-10'
  s.summary     = "Scrape and generate decks for cockatrice"
  s.description = "A tool to scrape MTG decks from the internet along with some meta information and create Cockatrice compatible deck files."
  s.authors     = ["Matthew Steinwachs"]
  s.email       = 'matt.steinwachs@gmail.com'
  s.files       = ["lib/cockatrice_feeder.rb"]
  s.homepage    = ''
  s.license     = 'MIT'

  s.add_dependency 'nokogiri'
  s.add_dependency 'httparty'
  s.add_dependency 'awesome_print'

  s.post_install_message = "Scraw!"
end
