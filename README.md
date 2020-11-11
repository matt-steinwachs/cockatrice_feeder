# Cockatrice Feeder
A tool to scrape MTG decks from the internet along with some meta information and create Cockatrice compatible deck files.

Scraw!

## Install
`gem install cockatrice_feeder`

## Example Setup
open an irb console anywhere and require the gem

`require 'cockatrice_feeder'`

Cockatrice Feeder needs to know where to put meta information

`CockatriceFeeder.set_meta_dir('/some/path/meta/')`

It also needs to know where to put the the deck files it creates

`CockatriceFeeder.set_deck_dir('/some/path/decks/')`

The following will set both directories within the same parent folder with default names.

`CockatriceFeeder.set_app_dir('/some/path/')`

By default it will use the present working directory and create subfolders there.

Run the following to create any missing folders and download the meta information used to fetch decks.

`CockatriceFeeder.setup`

## Fetching Decks
### Simple
If you just want to get a whole bunch of decks run:

`CockatriceFeeder.gobble`

### Detailed
There are currently 3 supported sources for decks:

#### edhrecavg
For every commander listed on EDHREC CockatriceFeeder will download the deck created from the average of all decks for that commander. Run the following:

`CockatriceFeeder.edhrecavg`

#### mtgdecks
A list of recent competitive EDH decks. CockatriceFeeder will go back through the list for as many pages as you specify and will automatically throw out any decks that contain currently banned cards. Run the following to fetch the first 2 pages of decks:

```
decks = CockatriceFeeder.mtgdecks_decklist(pages = 1..2)

decks.each{|d| CockatriceFeeder.mtgdecks_deck(d)}
```

The first line will fetch the basic information about each deck including its link. The second will fill in the rest of the information for each deck and output a deck file for each in the mtgdecks subfolder.

#### tappedout
Using tappedout's deck search CockatriceFeeder can download up to 10 pages of decks returned by customizable searches.

Supported search params

pages
: 1..10 or any subset of that range (i.e. 2..5)

order_by
: any string in ["-date_updated", "-ranking", "-competitive_score"], default "-date_updated"

price_min
: defaults to "" which means no min, otherwise it supports any integer (i.e. 100)

price_min
: defaults to "" which means no max, otherwise it supports any integer (i.e. 1000)

```
decks = CockatriceFeeder.tappedout_decklist(
  pages = 1..10,
  order_by = "-date_updated",
  price_min = "",
  price_max = ""
)

decks.each{|d| CockatriceFeeder.tappedout_deck(d)}
```

The first line will fetch the basic information about each deck including its link. The second will fill in the rest of the information for each deck and output a deck file for each in the tappedout subfolder.
