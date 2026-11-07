# Every help guide, in the help centre's order, as one Markdown document with a contents list. Links between
# guides become links within the document. Only the HTML the guides use is converted: headings, paragraphs,
# lists (not nested), bold, code, links and walkthroughs (an image and its numbered steps).
class HelpGuideExport
  def to_markdown
    [ header, contents, *HelpArticle::SECTIONS.flat_map { section(_1) } ].join("\n\n").gsub(/\n{3,}/, "\n\n").strip + "\n"
  end

  private
    def header
      <<~MD.strip
        # HardPoint user guide

        Every guide from HardPoint's help centre in one document. In the app, open **Help** from the menu under your name.
        This file is generated from `app/views/help/articles` by `bin/rails help:export`; edit the guides there, not here.
      MD
    end

    def contents
      lines = [ "## Contents" ]
      HelpArticle::SECTIONS.each do |name|
        lines << "\n**#{name}**\n"
        HelpArticle.in_section(name).each { lines << "- [#{_1.title}](##{_1.slug}): #{_1.summary}" }
      end
      lines.join("\n")
    end

    def section(name)
      [ "## #{name}" ] + HelpArticle.in_section(name).map { article(_1) }
    end

    def article(article)
      %(<a id="#{article.slug}"></a>\n\n### #{article.title}\n\n_#{article.summary}_\n\n#{markdown(render(article))})
    end

    def render(article)
      ApplicationController.renderer.new(http_host: "hardpoint.app", https: true).render(partial: article.partial)
    end

    def markdown(html)
      Nokogiri::HTML::DocumentFragment.parse(html).children.map { block(_1) }.reject(&:blank?).join("\n\n")
    end

    def block(node)
      case node.name
      when "h2" then [ (%(<a id="#{node["id"]}"></a>\n) if node["id"]), "#### #{inline(node)}" ].join
      when "ul" then node.css("> li").map { "- #{inline(_1)}" }.join("\n")
      when "ol" then node.css("> li").each_with_index.map { |item, index| "#{index + 1}. #{inline(item)}" }.join("\n")
      when "figure" then walkthrough(node)
      when "text" then node.text.strip
      else inline(node)
      end
    end

    # A walkthrough (help/_walkthrough) becomes its screenshot and its steps, numbered as on the screen.
    def walkthrough(node)
      tour = HelpTour.find(node["data-walkthrough"])
      [ "**Walkthrough: #{tour.title}**",
        "![Screenshot: #{tour.title}](../app/assets/images/#{tour.image})",
        block(node.at_css("ol.walkthrough-steps")) ].join("\n\n")
    end

    def inline(node)
      node.children.map do |child|
        case child.name
        when "text" then child.text
        when "strong", "b" then "**#{inline(child).strip}**"
        when "em", "i" then "_#{inline(child).strip}_"
        when "code" then "`#{child.text}`"
        when "a" then "[#{inline(child).strip}](#{href(child["href"])})"
        else inline(child)
        end
      end.join.gsub(/\s+/, " ").strip
    end

    def href(href)
      if (match = href.to_s.match(%r{\A(?:https?://[^/]+)?/help/([\w-]+)(?:#([\w-]+))?\z}))
        "##{match[2] || match[1]}"
      elsif href.to_s.start_with?("#")
        href
      else
        href.to_s.start_with?("/") ? "https://hardpoint.app#{href}" : href
      end
    end
end
