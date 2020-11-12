module CockatriceFeeder
  require 'httparty'
  require 'nokogiri'
  require 'fileutils'
  require 'descriptive_statistics'

  @@app_dir = Dir.pwd+"/"
  @@deck_dir = @@app_dir+"decks/"
  @@meta_dir = @@app_dir+"meta/"

  def self.set_app_dir(dir)
    @@app_dir = (dir + (dir[-1] != "/" ? "/" : ""))
    @@deck_dir = @@app_dir+"decks/"
    @@meta_dir = @@app_dir+"meta/"

    puts "decks will go here: #{@@deck_dir}"
    puts "meta data will go here: #{@@meta_dir}"
  end

  def self.app_dir
    @@app_dir
  end

  def self.set_deck_dir(dir)
    @@deck_dir = (dir + (dir[-1] != "/" ? "/" : ""))
    puts "decks will go here: #{@@deck_dir}"
  end

  def self.deck_dir
    @@deck_dir
  end

  def self.set_meta_dir(dir)
    @@meta_dir = (dir + (dir[-1] != "/" ? "/" : ""))
    puts "meta data will go here: #{@@meta_dir}"
  end

  def self.meta_dir
    @@meta_dir
  end

  def self.setup(skip_meta = false)
    unless File.directory?(@@meta_dir)
      Dir.mkdir(@@meta_dir)
      puts "Creating a folder at '#{@@meta_dir}' for storing meta data."
      unless skip_meta
        puts "Fetching meta data."
        update_commanders()
        update_banned()
        update_commander_tiers()
      end
    end

    unless File.directory?(@@deck_dir)
      Dir.mkdir(@@deck_dir)
      puts "Creating a folder at '#{@@deck_dir}' for generated decks."

      folders = %w(edhrecavg mtgdecks tappedout deckstats)

      folders.each do |folder|
        unless File.directory?(@@deck_dir+folder)
          Dir.mkdir(@@deck_dir+folder)
          puts "Creating a deck subfolder at '#{@@deck_dir+folder}'."
        end
      end
    end

    puts "Ready to scraw!"
  end

  def self.update_commanders
    puts "Downloading a list of all commanders from EDHREC."
    commander_cids = %w(
      w g r u b
      wu ub br rg gw wb ur bg rw gu
      wub ubr brg rgw gwu wbg urw bgu rwb gur
      wubr ubrg brgw rgwu gwub
      wubrg
    )

    commanders = []

    commander_cids.each do |cid|
      url = "https://edhrec-json.s3.amazonaws.com/en/commanders/#{cid}.json"
      commanders.concat(
        JSON.parse(
          HTTParty.get(url).body
        )["container"]["json_dict"]["cardlists"].first["cardviews"].map{|c|
          {
            link: c["sanitized"],
            name: c["names"].first,
            color_identity: cid,
            deckstats_uri: c["deckstats_uri"]
          }
        }
      )
    end

    File.open(@@meta_dir+"commanders.json", "wb") do |file|
      file.write(commanders.to_json)
    end
  end

  def self.update_banned
    puts "Downloading the current EDH banned card list."
    banned_list = []

    more_pages = true
    page = 1
    while(more_pages)
      url = "https://api.magicthegathering.io/v1/cards?gameFormat=Commander&legality=Banned&page=#{page}"
      cards = JSON.parse(HTTParty.get(url).body)["cards"]
      banned_list.concat(cards)
      page += 1
      if cards.length == 0
        more_pages = false
      end
    end

    File.open(@@meta_dir+"banned.json", "wb") do |file|
      file.write(banned_list.to_json)
    end
  end

  def self.update_commander_tiers
    puts "Downloading a tappedout deck that ranks EDG commanders into tiers."
    doc = Nokogiri::HTML(HTTParty.get("https://tappedout.net/mtg-decks/list-multiplayer-edh-generals-by-tier/").body)

    tiers = {}
    doc.css(".board-container .board-col").each do |col|
      col.css("h3").each_with_index do |h,i|
        tier = h.content.split(")").first.gsub("(","")

        tiers[tier] = []
        col.css("ul")[i].css("a.card-hover").each do |a|
          tiers[tier] << a.attribute("href").value.split("/").last.gsub("-foil","").downcase
        end

      end
    end

    File.open(@@meta_dir+"tiers.json", "wb") do |file|
      file.write(tiers.to_json)
    end

    tiers
  end

  def self.commanders
    unless File.exist?(@@meta_dir+"commanders.json")
      update_commanders()
    end
    JSON.parse(File.read(@@meta_dir+"commanders.json"))
  end

  def self.banned
    unless File.exist?(@@meta_dir+"banned.json")
      update_banned()
    end
    JSON.parse(File.read(@@meta_dir+"banned.json"))
  end
  # names = banned.map{|c| c["name"]}.uniq.sort

  def self.commander_tiers
    unless File.exist?(@@meta_dir+"tiers.json")
      update_commander_tiers()
    end
    JSON.parse(File.read(@@meta_dir+"tiers.json"))
  end

  def self.output_cod(deck, subfolder)
    comments = [
      deck[:name],
      deck[:link],
      deck[:commanders].join("\n"),
      deck[:price]
    ].join("\n")


    filename = [
      deck[:commanders].join("-and-"),
      deck[:name],
      deck[:price],
      subfolder
    ].compact.reject(&:empty?).uniq.join('_').gsub("/","")

    builder = Nokogiri::XML::Builder.new do |xml|
      xml.cockatrice_deck(:version => "1"){
        xml.deckname {
          xml.text(deck[:name])
        }
        xml.comments {
          xml.text(comments)
        }
        xml.zone(:name => "main") {
          deck[:cardlist].each do |crd|
            xml.card(
              :number => crd.split(" ").first,
              :name => crd.split(" ")[1..-1].join(" ")
            )
          end
        }
      }
    end

    File.open(@@deck_dir+"#{subfolder}/#{filename}.cod", "wb") do |file|
      file.write(builder.to_xml)
    end

    puts "created deck at #{@@deck_dir+"#{subfolder}/#{filename}.cod"}"
  end


  # ordering
  # -rating
  # -date_updated
  # -competitive_score
  def self.tappedout_decklist(pages = (1..10), order_by = "-date_updated", price_min = "", price_max = "")
    decks = []
    pages.each do |page|
      doc = Nokogiri::HTML(
        HTTParty.get(
          "https://tappedout.net/mtg-decks/search/?q=&format=edh&is_top=on&price_min=#{price_min}&price_max=#{price_max}&o=#{order_by}&submit=Filter+results&p=#{page}&page=#{page}"
        ).body
      )

      doc.css(".deck-wide-header a").each do |a|
        link = a.attribute("href").value
        if link.include?("/mtg-decks/")
          decks << {
            name: link.split("/").last,
            commanders: [],
            link: "https://tappedout.net"+link,
            date: nil,
            price: nil,
            cardlist: []
          }
        end
      end
    end

    decks
  end

  def self.tappedout_deck(deck)
    doc2 = Nokogiri::HTML(HTTParty.get(deck[:link]).body)

    deck[:cardlist] = doc2.css("#mtga-textarea").first.content.
      split("\n").select{|c| c != ""}.
      map{|c| c.split("(").first.strip}

    commanders = []
    doc2.css(".board-container .board-col").each do |col|
      col.css("h3").each_with_index do |h,i|
        if h.content.include?("Commander")
          col.css("ul")[i].css("a.card-hover").each do |a|
            if a.css("img.commander-img").length > 0
              commanders << a.attribute("href").value.split("/").last.gsub("-foil","")
            end
          end
        end
      end
    end
    deck[:commanders] = commanders

    price = nil
    doc2.css("form").each do |f|
      fname = f.attribute("name")
      if !fname.nil? && fname.value == "ck_checkout"
        price = f.css("span.pull-right").first.content.split(" - ").first.
          strip.gsub("$","").split(".").first
      end
    end
    deck[:price] = price

    subfolder = "tappedout"
    output_cod(deck, subfolder)
  end

  def self.edhrecavg_decklist
    commanders.map{|c| c["link"]}.map do |c|
      {
        name: c,
        commanders: [c],
        link: "https://edhrec-json.s3.amazonaws.com/en/decks/#{c}.json",
        price: nil,
        date: nil,
        cardlist: []
      }
    end
  end

  def self.edhrecavg_deck(deck)
    deck[:cardlist] = JSON.parse(HTTParty.get(deck[:link]).body)["description"].
      split("</a>").last.split("\n").select{|s| s != ""}

    output_cod(deck,"edhrecavg")
  end


  #order ["views,desc", "price,desc", "likes,desc", "updated,desc"]
  #commander should be a name attribute from the commanders array of objects
  def self.deckstats_decklist(commander = "nil", pages = (1..1), order = "likes,desc", price_min = "", price_max = "")
    decklist = []
    pages.each do |page|
      url = [
        "https://deckstats.net/decks/search/?lng=en",
        "&search_title=",
        "&search_format=10",
        "&search_season=0",
        "&search_cards_commander%5B%5D=#{URI.encode_www_form_component(commander)}",
        "&search_cards_commander%5B%5D=",
        "&search_price_min=#{price_min}",
        "&search_price_max=#{price_max}",
        "&search_colors%5B%5D=",
        "&search_number_cards_main=100",
        "&search_number_cards_sideboard=",
        "&search_cards%5B%5D=",
        "&search_tags=",
        "&search_order=#{URI.encode_www_form_component(order)}",
        "&utf8=%E2%9C%94",
        "&page=#{page}"
      ].join("")

      doc = Nokogiri::HTML(HTTParty.get(url).body)

      doc.css(".deck_row").each do |dr|
        link = dr.css("td")[1].css("a").first.attribute("href").value
        decklist << {
          link: link,
          name: link.split("/")[-2],
          commanders: [commander].reject(&:empty?),
          price: nil,
          date: nil,
          cardlist: []
        }
      end
    end

    decklist
  end

  def self.deckstats_deck(deck)
    docstring = HTTParty.get(deck[:link]).body

    doc = Nokogiri::HTML(docstring)

    legal = (doc.css(".fa-exclamation-triangle").count == 0)

    if legal
      deck_data = JSON.parse(docstring.split("init_deck_data(").last.split(");deck_display();").first)
      deck[:date] = DateTime.strptime(deck_data["updated"].to_s,'%s')
      unless deck_data["highlight_cards"].nil?
        deck[:commanders] = deck_data["highlight_cards"]
      end
      deck[:cardlist] = deck_data["sections"].map do |sec|
        sec["cards"].map{|c| "#{c["amount"]} #{c["name"]}"}
      end.flatten

      deck[:price] = doc.css(".deck_overview_price").first.content.gsub("$","").strip.split(".").first

      output_cod(deck,'deckstats')
    end
  end

  def self.mtgdecks_decklist(pages = (1..1))
    decks = []
    pages.each do |page|
      puts "https://mtgdecks.net/Commander/decklists/page:#{page}"
      doc = Nokogiri::HTML(HTTParty.get("https://mtgdecks.net/Commander/decklists/page:#{page}").body)
      doc.css(".decks tr.previewable").each do |r|
        if r.css("td")[0].css(".label-danger").length == 0
          decks << {
            name: "", # r.css("td")[1].css("a")[0].content,
            link: "https://mtgdecks.net"+r.css("td")[1].css("a")[0].attribute("href").value,
            date: r.css("td")[6].css("strong")[0].content.
              gsub("<span class=\"hidden-xs\">","").
              gsub("</span>","").gsub(/\s+/, ""),
            price: r.css("td")[7].css("span.paper")[0].content.gsub("$","").gsub(/\s+/, ""),
            commanders: [],
            cardlist: []
          }
        end
      end
    end

    decks
  end

  def self.mtgdecks_deck(deck)
    doc = Nokogiri::HTML(HTTParty.get(deck[:link]).body)

    cardlist = []
    doc.css(".cardItem").each do |card|
      cardlist << "#{card.attribute("data-required").value} #{card.attribute("data-card-id").value}"
    end
    deck[:cardlist] = cardlist

    commanders = []
    doc.css(".breadcrumbs a").each do |a|
      href = a.attribute("href").value
      if href.include?("/Commander/")
        commanders << href.split("/").last
      end
    end
    deck[:commanders] = commanders

    output_cod(deck,"mtgdecks")
  end

  def self.gobble
    setup(skip_meta = true)
    update_commanders()

    total_decks = 0

    puts "Fetching the average deck for every commander on EDHREC"
    decks = CockatriceFeeder.edhrecavg_decklist
    puts "#{decks.length} decks found."
    decks.each {|d|
      CockatriceFeeder.edhrecavg_deck(d)
      total_decks += 1
    }

    puts "Fetching the most recently updated ranked decks from tappedout"
    decks = CockatriceFeeder.tappedout_decklist(1..10)
    puts "#{decks.length} decks found."
    decks.each {|d|
      CockatriceFeeder.tappedout_deck(d)
      total_decks += 1
    }

    puts "Fetching the first 10 pages of decks at https://mtgdecks.net/Commander/decklists/"
    decks = CockatriceFeeder.mtgdecks_decklist(1..10)
    puts "#{decks.length} decks found."
    decks.each {|d|
      CockatriceFeeder.mtgdecks_deck(d)
      if d[:cardlist].length < 0
        total_decks += 1
      end
    }

    puts "Fetching the first 5 pages of edh decks from deckstats ordered by likes"
    decks = CockatriceFeeder.deckstats_decklist("", (1..5))
    puts "#{decks.length} decks found."
    decks.each {|d|
      CockatriceFeeder.deckstats_deck(d)
      if d[:cardlist].length < 0
        total_decks += 1
      end
    }

    puts "#{total_decks} decks created at #{@@deck_dir}."

    puts "cleaning up"
    FileUtils.remove_dir(@@meta_dir)
    puts "Scraw!"
  end
end
