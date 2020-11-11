module CockatriceFeeder
  require 'httparty'
  require 'awesome_print'
  require 'nokogiri'

  @@app_dir = "/Users/ceedev/Desktop/Personal/cockatrice_feeder/" #Dir.pwd+"/"
  @@output_dir = @@app_dir

  def self.create_subfolders
    folders = %w(edhrecavg mtgdecks tappedout deckstats)

    d = Dir.new(@@output_dir)

    current_items = []
    d.each do |f|
      current_items << f
    end

    folders.each do |folder|
      unless current_items.include?(folder)
        Dir.mkdir(@@output_dir+folder)
      end
    end
  end

  def self.update_commanders
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

    File.open(@@app_dir+"commanders.json", "wb") do |file|
      file.write(commanders.to_json)
    end
  end

  def self.update_banned
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

    File.open(@@app_dir+"banned.json", "wb") do |file|
      file.write(banned_list.to_json)
    end
  end

  def self.update_commander_tiers
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

    File.open(@@app_dir+"tiers.json", "wb") do |file|
      file.write(tiers.to_json)
    end

    tiers
  end

  def self.commanders
    JSON.parse(File.read(@@app_dir+"commanders.json"))
  end

  def self.banned
    JSON.parse(File.read(@@app_dir+"banned.json"))
  end
  # names = banned.map{|c| c["name"]}.uniq.sort

  def self.tiers
    JSON.parse(File.read(@@app_dir+"tiers.json"))
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
    ].compact.reject(&:empty?).uniq.join('_')

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

    File.open(@@output_dir+"#{subfolder}/#{filename}.cod", "wb") do |file|
      file.write(builder.to_xml)
    end
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
      i = 0
      col.css("h3").each do |h|
        if h.content.include?("Commander")
          col.css("ul")[i].css("a.card-hover").each do |a|
            if a.css("img.commander-img").length > 0
              commanders << a.attribute("href").value.split("/").last.gsub("-foil","")
            end
          end
        end
        i += 1
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

  def self.edhrecavg
    commanders.map{|c| c["link"]}.each do |c|
      link = "https://edhrec-json.s3.amazonaws.com/en/decks/#{c}.json"
      deck = {
        cardlist: JSON.parse(HTTParty.get(link).body)["description"].
          split("</a>").last.split("\n").select{|s| s != ""},
        name: c,
        commanders: [c],
        link: link,
        price: nil,
        date: nil
      }

      output_cod(deck,"edhrecavg")
    end
  end

  def self.deckstats_decklist

  end

  def self.deckstats_deck

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
    puts deck[:link]
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
end
