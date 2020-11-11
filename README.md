#Cockatrice Feeder
A tool to scrape MTG decks from the internet along with some meta information and create Cockatrice compatible deck files.

Scraw!

##Install
`gem install cockatrice_feeder`

##Example Usage
open an irb console anywhere

`require 'cockatrice_feeder'`

Cockatrice Feeder needs to know where to put meta information

`CockatriceFeeder.set_meta_dir('/some/path/meta/')`

It also needs to know where to put the the deck files it creates

`CockatriceFeeder.set_meta_dir('/some/path/decks/')`

The following will set both directories within the same parent folder with default names and it will create the folders if they don't exist

`CockatriceFeeder.set_app_dir('/some/path/')`
