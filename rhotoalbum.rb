#!/usr/bin/env ruby
# Rhotoalbum -- a Ruby photo album generator.
#
# Copyright (C) 2007-2011  Ondrej Jaura
# Contributor(s): Viktor Zigo
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
#
# Ondrej Jaura <ondrej@valibuk.net>
# Viktor Zigo <viz@alephzarro.com>


# Rhotoalbum -- a Ruby photo album generator.
#
# Ondrej Jaura <ondrej@valibuk.net>
# Viktor Zigo <viz@alephzarro.com>
#
# version: 0.9
#
require 'yaml'
require 'fileutils'
require 'uri'

require 'optional_require'
optional_require 'rubygems' 
EXIF_LIB = optional_require('exifr')
require 'fx.rb'

module RhotoAlbum

    OPTIONS_FILE = 'options.yml'
    CMDS = ['generate', 'text', 'clean', 'cleanindex', 'cleanhighlight', 'rebuild']    
    DEFAULTS =  {
        :title=>'Rhotoalbum',
        :author=>'Ondrej Jaura, Viktor Zigo',
        :author_label => 'Authors',
        :css=>'rhotoalbum.css',
        :explicitIndexHtml => false,
        :styleSwitcher => true,
        :showTitleAlbum => true,
        :showStatsAlbum => true,
        :showTitlePhoto => true,
        :showDescription => true,
        :descriptionAsName => false,
        :showDate => true,
        :useExifDate => true,
        :showExif => true,
        :showExtendedExif => false,
        :thumbnailDim => '256x256',
        :panning => false,
        :fading => false,
        :labelNoPhoto => 'no photos',
        :labelOnePhoto => 'one photo',
        :labelMorePhotos => '# photos',
        :labelOneAlbum => 'one album',
        :labelMoreAlbums => '# albums',
        :generateRss => true, 
        :google_analytics => nil,
        :nonrecursive => false,
        :maxPerPage => -1,
        :debug => false,
        :effect => 'polaroid', # reflection, shadow, polaroid, glow, rotate
        :effectAlbum => 'polaroid_stack', # stack, polaroid_stack
        :effectBackground => '#000000'
    }
#    DEFAULTS[:copyright]=%Q{
#        <a rel="license" href="http://creativecommons.org/licenses/by-nc-nd/3.0/"><img alt="Creative Commons License" style="border-width:0" src="http://i.creativecommons.org/l/by-nc-nd/3.0/80x15.png" /></a> This work is licensed under a <a rel="license" href="http://creativecommons.org/licenses/by-nc-nd/3.0/" title="Creative Commons Attribution-Noncommercial-No Derivative Works 3.0 License">CC NC ND</a>.    
#    }


    HIGHLIGHT = 'highlight.jpg'
	COVER = 'cover.jpg'
    THUMBNAILS_DIR = 'thumbnails'
    VERSION = '0.9'

  # A base class for any page generator.
  #
  class MetaPageGenerator

    # Initialises the page generator.
    #
    def initialize out, path, scriptGenerator, thumbnailGenerator, opts = {}
      @opts = opts
      @out = out
      @path = path
      @scriptGenerator = scriptGenerator
      @thumbnailGenerator = thumbnailGenerator
    end

    def generate subdirs, images, texts, aPage
      generate_header
      @scriptGenerator.generate @out, images, texts, @path
      generate_body subdirs, images, texts, aPage
      generate_footer
    end    
  end


  # generates media RSS 2.0 for the images of an album
  class RssGenerator
    def initialize aThumbnailGenerator, aPath, opts = {}
      @thumbnailGenerator =  aThumbnailGenerator
      @path = aPath
      @opts = opts
    end

    def generate out, images, texts
        out << generate_wrapping do

            # get latest N images
            timedImages = images.map {|img| [ImageInfo.image_time(img), img] }
            timedImages = timedImages.sort.last 1000 #TODO: how many? 

            contents = timedImages.map {|time, img|
                thumbnail = @thumbnailGenerator.thumbnail(img, true) # create/get a thumbnail
                name, description = ImageInfo.nameAndDescription img, texts, @opts
              #if @opts[:showDate]}
              #if @opts[:showTitlePhoto]}
                generate_item img, thumbnail, name, description, time.gmtime
            }
            contents.join
        end
    end
      
    def generate_wrapping &contentBlock
        title = "#{@opts[:title]} :: #{@path[1,1000].join(' :: ')}"
        path = File.join @path[1,1000].map {|p| URI.escape(p)}
        pubTime = File.mtime('photos.rss').gmtime
        %Q{<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<rss version="2.0" xmlns:media="http://search.yahoo.com/mrss" 
    xmlns:atom="http://www.w3.org/2005/Atom">
    <channel>
        <title>#{Entities.encode(title)}</title>
        <link>#{Entities.encode(path)}/photos.rss</link>
        <pubDate>#{pubTime}</pubDate>
        <copyright>#{Entities.encode(@opts[:copyright])}</copyright>
        <generator>Rhotoalbum #{RhotoAlbum::VERSION}</generator>
#{yield}
    </channel>
</rss>}
    end

    def generate_item anImage, aThumbnail, aName, aDescription, aTimestamp
        name = Entities.encode aName
        description = Entities.encode aDescription
        %Q{        <item>
            <title>#{name}</title>
            <media:description>#{description}</media:description>
            <link>#{URI.escape(anImage)}</link>
            <pubDate>#{aTimestamp}</pubDate>
            <author>#{Entities.encode(@opts[:author])}</author>
            <media:thumbnail url="#{URI.escape(aThumbnail)}"/>
            <media:content url="#{URI.escape(anImage)}"/>
        </item>
}
        #TODO: exif
    end
  end

  # A JavaScript part of the page generator.
  #
  class ScriptGenerator
    def initialize opts = {}
      @opts = opts
    end

    def generate_beginning out, path
      relative = Helper.relativise path.size - 1
      #optional Style Switcher
      out << %Q{ 
        <script type="text/javascript" src="#{relative}switcher.js"></script>
      } if @opts[:styleSwitcher]
      
      # image viewer - Slider
      out << %Q{
        <script type="text/javascript" src="#{relative}slide.js"></script>
        <script type=\"text/javascript\">
        <!--
            var viewer = new PhotoViewer();\n
        }
        out << "      viewer.disablePanning();\n" if not @opts[:panning]
        out << "      viewer.enableAutoPlay();\n" if false
        out << "      viewer.disableFading();\n" if not @opts[:fading]
    end

    def generate_end out
      out <<
"   //--></script>\n"
    end

    def generate_file_entry out, image, aTexts
      name, description = ImageInfo.nameAndDescription image, aTexts, @opts  
      out << "      viewer.add('#{image}', '#{name}', '#{ImageInfo.image_timestamp image, @opts[:useExifDate]}');\n"
    end

    def generate out, images, aTexts, path
      generate_beginning out, path
      images.each do |i|
        next if i == HIGHLIGHT or i == COVER
        generate_file_entry out, i, aTexts
      end
      generate_end out
    end
  end

  # A page generator.
  #
  class PageGenerator < MetaPageGenerator

    # Returns a navigational URL. Currently, only 'home', 'up' and 'down' are supported.
    def navigate relation, args = {}
      url = case relation
              when 'home' then Helper.relativise @path.size - 1;
              when 'up'   then Helper.relativise args[:level]
              when 'down' then args[:subdir] + '/';
            end
      url += 'index.html' if @opts[:explicitIndexHtml]
      return url
    end

    def generate_menu images, subdirs, aPage
      relative = Helper.relativise @path.size - 1  
      @out << '<div class="menu"><div class="navigation">'
      i = @path.size - 1
      @path.each do |p|
        if p == @path.last
          @out << '<span class="actual-item">'
        else
          @out << '<a class="normal-item"'
          @out << " href=\"#{navigate 'up', :level => i}\">"
        end

        @out << Entities.encode("#{p == @path.first ? @opts[:title] : p}")
        @out << (p == @path.last ? '</span>' : '</a> :: ')

        i -= 1
      end

      # statistics
      if @opts[:showStatsAlbum]
        stats = []

        stats_images = number_of_images(images, false)	
        stats.push stats_images unless stats_images.empty?

        stats_subalbums = number_of_subalbums(subdirs)
        stats.push stats_subalbums unless stats_subalbums.empty?

        @out << "<span class=\"menu-details\">#{stats.join(' &nbsp; / &nbsp; ')}</span>"
      end

      @out << '</div>'

      #RSS
      @out <<  %Q{
        <div class="rss">
            <a href="photos.rss"><img src="#{relative}/.rss-icon.png" title="RSS photo media feed" alt="RSS photo media feed"/></a>
        </div>
      } if @opts[:generateRss]

      #Theme switching 
      @out <<  %Q{
        <div class="skin">
            Skin:
            <a href="#" onclick="setActiveStyleSheet('black'); return false;">Black</a>,
            <a href="#" onclick="setActiveStyleSheet('white'); return false;">White</a>
        </div>
      } if @opts[:styleSwitcher]
      
      @out << '&nbsp;</div>'
      generate_paginator images, subdirs, aPage
    end

    def generate_paginator images, subdirs, aCurrentPage
      def clickMacro aPage, aText, aTitle, anId = nil
        @out << "<a #{"id=\"#{anId}\"" if anId} href=\"#{Helper.indexName aPage}\" title=\"#{aTitle}\">#{aText}</a>"
      end

      # paginator
      if doPagination? subdirs, images
          allItems = subdirs + images
          maxPerPage = @opts[:maxPerPage]
          pages = (allItems.length.to_f/maxPerPage).ceil
          @out << '<span class="paginator">'
          clickMacro aCurrentPage-1, '&laquo;', 'Previous Page' if aCurrentPage>0
          
          pageSequence = [(1..pages)]
          if pages>10
            if aCurrentPage<4
              pageSequence = [(1..5), (pages-1..pages)]
            elsif aCurrentPage>pages-3
              pageSequence = [(1..2), (pages-3..pages)]
            else
              pageSequence = [(1..2), (aCurrentPage-1..aCurrentPage+3), (pages-1..pages)]
            end
          end
          pageSequence.each_with_index {|seq, i|
              @out << '<span class="elipsis">&hellip;</span>' unless i==0
              seq.each { |i|
                  clickMacro i-1, i, " Page #{i}", (i==aCurrentPage+1 ? 'current' : nil)
              }
          }          
          clickMacro aCurrentPage+1, '&raquo;', 'Next Page' if aCurrentPage<pages-1
          @out << '</span>'
      end
    end

    def generate_subdirs subdirs, texts,  firstIdx, count
      subdirs[firstIdx,count].each do |s|
        #name, description = ImageInfo.nameAndDescription s, texts, @opts
        name, description = Entities.encode(s), Entities.encode(texts[s])
        numOfImages = number_of_images(Dir[s + '/**/' + Generator::IMAGE_MASK].uniq.reject{ |f| 
            f.include? THUMBNAILS_DIR or f.include? HIGHLIGHT or f.include? COVER 
        }) if @opts[:showStatsAlbum]

        @out << %Q{
            <div class="index-item album">
            <a href="#{navigate 'down', :subdir => s}">
                <img class="image" src="#{s}/#{HIGHLIGHT}" alt="Album: #{name}"/>
                #{"<span class=\"title\">#{name}</span>" if @opts[:showTitleAlbum]}
            </a>
            #{ "<span class=\"description\">#{description}</span>" if description and @opts[:showDescription]}
            #{ "<span class=\"statistics\">#{numOfImages}</span>" if @opts[:showStatsAlbum]}
            </div>
        }		
      end
    end

    def generate_images images, texts, firstIdx, count
      k =  firstIdx # index      
      images[firstIdx,count].each do |i|                
        #if k % 2 == 0 # Uncomment this line if you have a double-thumbnail problem. (Fix by Michael Adams)

          showExif = false # show exif?
          j = nil # image exif data
          exifBasicText = '' # exif basic info in a textual form

          if @opts[:showExif] && EXIF_LIB # if enabled and the exif library is loaded
            j = EXIFR::JPEG.new(i)
            showExif = j.exif? # show exif only if the image contains exif info
            if showExif
              exifBasic = []
              exifBasic.push "#{j.exif[:exposure_time].to_s} sec" if j.exif[:exposure_time]
              exifBasic.push "#{j.exif[:focal_length]} mm" if j.exif[:focal_length]
              exifBasic.push "F#{j.exif[:f_number].to_f}" if j.exif[:f_number]
              exifBasicText = exifBasic.join ', '
            end
          end

          name, description = ImageInfo.nameAndDescription i, texts, @opts
          Entities.encode!(name)
          Entities.encode!(description)
          thumbnail = @thumbnailGenerator.thumbnail(i) # create a thumbnail
          #nacitaj exif data do pola a join ak showExif

          @out << %Q{
              <div class="image-item photo #{'first-image-item' if k == 0}">
              <a href="#{URI.escape(i)}" onclick="return viewer.show(#{k})"><img class="image" src="#{URI.escape(thumbnail)}" alt="#{i}" title="#{i}"/></a>
              #{"<span class=\"datum\">#{ImageInfo.image_timestamp i, @opts[:useExifDate]}</span>" if @opts[:showDate]}
              #{"<span class=\"title\">#{name}</span>" if @opts[:showTitlePhoto]}
              #{"<span class=\"description\">#{description}</span>" if description and @opts[:showDescription]}
              #{"<span class=\"exifBasic\">#{exifBasicText}</span>" if showExif}
              #{"<span class=\"exifExtended\">#{j.exif[:model]}</span>" if showExif && @opts[:showExtendedExif]}
              </div>
          }
        #end # Uncomment this line if you have a double-thumbnail problem.  (Fix by Michael Adams)
        k += 1
      end
    end

    def generate_header
      if @path.size > 1
	    navigation = %Q{
            <link rel="home" title="Home" href="#{navigate 'home'}" />
            <link rel="up" title="Up" href="#{navigate 'up', :level => 1}" />
        }
      end
      relative = Helper.relativise @path.size - 1
      @out << %Q{<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
        <html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
        <head>            
            <meta http-equiv="Content-Type" content="text/html;charset=utf-8" />
            <meta name="author" content="#{@opts[:author]}" />
            <meta name="generator" content="Rhotoalbum #{VERSION}" />
            <title>#{@opts[:title]} :: #{@path.last}</title>
            #{navigation}
            <link href="#{relative}#{@opts[:css]}" media="all" rel="stylesheet" type="text/css" />
            <link href="#{relative}rhotoalbum.css#" media="all" rel="alternate stylesheet" type="text/css" title="black"/>
            <link href="#{relative}rhotoalbum_w.css#" media="all" rel="alternate stylesheet" type="text/css" title="white"/>
            <link href="photos.rss" rel="alternate"  type="application/rss+xml" title="photo media feed" id="gallery" />
        </head>
        <body>
        }
    end

    def generate_footer
      @out << Helper.copyright(@opts)
      @out << Helper.analytics(@opts)
      @out <<%Q{
        </body>
        </html>
    }
    end

    def generate_body subdirs, images, texts, aPage        
        images-=[HIGHLIGHT]  # exclude highlight
		images-=[COVER] # exclude cover
        generate_menu images, subdirs, aPage

        if doPagination?(subdirs, images)
            #pagination needed
            allItems = subdirs + images
            maxPerPage = @opts[:maxPerPage]
            todo = maxPerPage
            done = 0
            globalIdx = aPage*maxPerPage
            firstItem = allItems[globalIdx+done]
            localIdx = subdirs.index firstItem
            unless (localIdx.nil?)
                count = [subdirs.length-localIdx, todo].min
                puts "for page #{aPage}: position #{globalIdx}/#{allItems.length} taking [#{localIdx},#{count}] from #{subdirs.length} subdirs"
                generate_subdirs subdirs, texts, localIdx, count
                done += count
                todo -= count
            end
            return if todo<=0
            firstItem = allItems[globalIdx+done]
            localIdx = images.index firstItem
            unless (localIdx.nil?)
                count = [images.length-localIdx, todo].min
                puts "for page #{aPage}: position #{globalIdx}/#{allItems.length} taking [#{localIdx},#{count}] from #{images.length} images "
                generate_images images, texts, localIdx, count 
                done += count
                todo -= count
            end
        else
            #no pagination needed
            generate_subdirs subdirs, texts, 0, 10000
            generate_images images, texts, 0, 10000
        end
    end

    def doPagination? subdirs, images
        maxPerPage = @opts[:maxPerPage]
        items = subdirs.length + images.length
        maxPerPage.to_i>0 and items>maxPerPage
    end

    def number_of_images images, talkative=true
      n = images.include?(HIGHLIGHT) ? images.size - 1 : images.size
      n = images.include?(COVER) ? n - 1 : n
      if n == 0
        talkative ? @opts[:labelNoPhoto] : ''
      elsif n == 1
        @opts[:labelOnePhoto]
      else
        @opts[:labelMorePhotos].gsub('#',n.to_s)
      end
    end

    def number_of_subalbums subalbums
      s = subalbums.size
      if s == 0
        ''
      elsif s == 1
        @opts[:labelOneAlbum]
      else
        @opts[:labelMoreAlbums].gsub('#',s.to_s)
      end
    end
  end

  # A thumbnails generator. It calls an external application to generate a thumbnail. Currently it is the <code>convert</code> application from the ImageMagick library. If RMagick is installed it can be used for adding effects.
  #
  class ThumbnailGenerator
    def initialize opts = {}
      @opts = opts
    end

    def thumbnail image, noeffect = false
      Dir.mkdir THUMBNAILS_DIR unless File.exists? THUMBNAILS_DIR
      th = "#{THUMBNAILS_DIR}/#{thumbnail_name image, noeffect}"
      generate th, image, noeffect unless (File.exists? th) || (image == HIGHLIGHT)  || (image == COVER)
      th
    end

    def thumbnail_name image, noeffect = false
        name = "th_#{image}"
		#uncomment for different thumbnail file names for different effects
        #name = name.split('.').insert(-2,@opts[:effect]).join('.') unless noeffect or @opts[:effect].to_s.empty?
        name
    end

    def generate thumbnail, image, noeffect = false
      puts "Generating #{thumbnail} from #{image}"
      `convert "#{image}" -thumbnail #{@opts[:thumbnailDim]} -blur 0x0.25 "#{thumbnail}"` unless (File.exists? thumbnail)

      fx thumbnail, @opts[:effect], @opts[:effectBackground] unless noeffect
    end
    
    def generate_album thumbnail, image, noeffect = false
      puts "Generating album thumbnail #{thumbnail} from #{image}"
      `convert "#{image}" -thumbnail #{@opts[:thumbnailDim]} -blur 0x0.25 "#{thumbnail}"` unless (File.exists? thumbnail)
      fx thumbnail, @opts[:effectAlbum], @opts[:effectBackground] unless noeffect
    end    

    def fx aThumbnail, aCmd, aBackground
        opts = {:background => aBackground}
        processImage! aThumbnail, aCmd, opts if aCmd and RMAGICK_LIB
    end
  end


  class ImageInfo
    # 'fero.jpg' => 'fero',  'fero' => 'fero"
    def self.image_name image
      re = /.((jpg)|(jpeg)|(png)|(gif)|(tiff))$/i
      re.match image
      $` || image
    end

    def self.image_timestamp image, useExifDate
      ts = nil
      if useExifDate && EXIF_LIB
		exif = EXIFR::JPEG.new(image)
        ts = exif.date_time_original
		ts = exif.date_time if ts == nil
      end
      ts = File.mtime(image) if ts == nil
      ts.strftime '%A %d %B %Y %H:%M'
    end

    def self.image_time image
      File.mtime(image)
    end

    # usage: name, description = nameAndDescription img, texts, opts
    def self.nameAndDescription anImage, aTexts, opts = {}
        name = image_name anImage
        desc = aTexts[anImage] 
        opts[:descriptionAsName] ? [desc, nil] : [name, desc]
    end
  end

    class Generator
        IMAGE_MASK = '*.{jpg,JPG,jpeg,JPEG,png,PNG,gif,GIF}'
        DESCRIPTION_FILE = 'description.txt'
        def initialize opts = {}
            @opts = opts            
        end
    
        def execute cmd, path
            subdirs = Dir['*'].find_all do |d|
                File.directory?(d) and d != THUMBNAILS_DIR
            end
            subdirs.sort!
            
            # handle all albums recursivelly
            unless @opts[:nonrecursive]
                subdirs.each do |subdir|
                    Dir.chdir subdir
                    albumOpts = Helper::loadOpts
                    puts "options.yml found for the album '#{subdir}'" if albumOpts
                    albumGen = Generator.new( @opts.merge( albumOpts || {} ) )
                    albumGen.execute cmd, path + [subdir]
                    Dir.chdir '..' 
                end
            end

			# and handle the root album

            puts "Executing '#{cmd}' upon the directory: #{path.join '/'}"
            images = Dir[IMAGE_MASK].uniq.sort
            # the images array contains also the HIGHLIGHT image, that is handled as needed later

            case cmd 
                when 'generate' then generateAlbum path, subdirs, images
                when 'text' then generateText path, subdirs, images
                when 'cleanindex' then return cleanindex(path)
                when 'cleanhighlight' then return cleanhighlight(path)
                when 'clean' then return clean(path)
                when 'rebuild' then 
                    cleanindex(path)
                    generateText( path, subdirs, images )
                    generateAlbum( path, subdirs, images)
            end 
        end
        
        def cleanindex aPath
            FileUtils.rm Dir['**/index*.html'], :verbose=>true
        end
        def cleanhighlight aPath
            FileUtils.rm Dir['**/highlight.jpg'], :verbose=>true
        end
        def clean aPath
            FileUtils.rm_rf Dir['**/thumbnails'], :verbose=>true
			cleanhighlight aPath
            cleanindex aPath
        end
        
        def generateAlbum path, subdirs, images
            texts = loadTexts path, images, subdirs
            puts "Image descriptions: #{texts.inspect}." if @opts[:debug]
            
            maxPerPage = @opts[:maxPerPage]
            items = subdirs.length + images.length
            pages = maxPerPage.to_i<=0 ? 1 : (items.to_f/maxPerPage).ceil
            pages.times {|page|
                fname = Helper.indexName page
                puts "Generating #{File.join(path)}/#{fname}, using #{texts.size} text descriptions."
                File.open(fname, "w") do |out|
                    pg = PageGenerator.new out, path, ScriptGenerator.new(@opts), ThumbnailGenerator.new(@opts), @opts
                    pg.generate subdirs, images, texts, page
                end
            }
            # if there is no highlight image, set it to the first image
            unless images.include?(HIGHLIGHT)
			  unless images.empty? # if there are any images create the highlight from them
				hasCover = images.include? COVER
				if ! @opts[:effectAlbum] 
					albumThumbnail = ThumbnailGenerator.new(@opts).thumbnail(hasCover ? COVER : images.first, true)
					puts "Setting the album image to the #{hasCover ? 'cover' : 'first'} image thumbnail #{albumThumbnail}."
					FileUtils.copy_file albumThumbnail, HIGHLIGHT
				else
					ThumbnailGenerator.new(@opts).generate_album(HIGHLIGHT, hasCover ? COVER : images.first, false)
					puts "Setting the album image to the #{hasCover ? 'cover' : 'first'} image thumbnail with an effect."
				end
			  else # if there are no images, try to find already generated highlight in subdirectories
				highlights = Dir["./**/#{HIGHLIGHT}"]
				unless highlights.empty?
				  puts "Setting a highlight from another album #{highlights[0]}."
				  FileUtils.copy_file highlights[0], HIGHLIGHT
				else
				  puts "Could not find any highlight for this album."
				end
			  end
            end

            generateRss path, subdirs, images, texts if @opts[:generateRss]
        end
        
        def generateRss path, subdirs, images, texts
            puts "Generating #{File.join(path)}/photos.rss, using #{texts.size} text descriptions."
            File.open('photos.rss', "w") do |out|
                rssg = RssGenerator.new ThumbnailGenerator.new(@opts), path, @opts
                rssg.generate out, images, texts
            end        
        end
        
        # Generates empty boilerplate central description file for images and albums (does not overwrite existing files)
        def generateText path, subdirs, images
            textables = subdirs + images - ['highlight.jpg']
            if File.exist? DESCRIPTION_FILE
                texts = loadTexts path, images, subdirs, true
                newItems = textables - texts.keys
                if newItems.size>0 then
                    puts "Merging #{newItems.size} new empty text descriptions to #{DESCRIPTION_FILE}."
                    #return
                    File.open(DESCRIPTION_FILE, "a") do |out|
                        out.puts
                        newItems.each do |img|
                            out<<"#{img}\t\n"
                        end
                    end
                else
                    puts('The existing text description file is up to date.')
                end                
            else
                File.open(DESCRIPTION_FILE, "w") do |out|
                    out.puts '# Write descriptions for images and albums. Format: one definition per line, filename and text separated by colon, semicolon, comma or tab.'
                    textables.each do |img|
                        out<<"#{img}\t\n"
                    end
                end 
            end       
        end
        
        # Loads texts/descriptons for images and albums
        # Returns hash filename=>text
        def loadTexts path, images, subdirs, includeEmpty = false
            texts = loadCentralTexts path, includeEmpty
            texts.merge loadPerFileTexts(path, images, subdirs)
        end

        # Loads texts/descriptons for images and albums from central file 'description.,txt'
        # Format: one definition per line, filename and text separated by colon, semicolon, comma, or tab., Hash comments allowed
        # Returns hash: filename=>text
        def loadCentralTexts path, includeEmpty = false
            #textFiles = Dir['*.{txt,TXT}']
            texts = {}
            if File.exist? DESCRIPTION_FILE
                File.open(DESCRIPTION_FILE) { |f| 
                    f.each {|l|
                        l.gsub!( /#.*$/,'' )  #remove comments
                        name,text=l.scan(/(.+?)\s*[;,:\t](.*)/).first
                        texts[name.to_s.strip]=text.to_s.strip if name.to_s.strip.size>0 and (includeEmpty or text.to_s.strip.size>0)
                    }
                }
            end
            texts
        end
        
        # Loads texts/descriptons for image/album separate file
        # The filename that contain the text has format: #{image_or_album_fname}.txt
        # Returns hash: filename=>text
        def loadPerFileTexts path, images, subdirs
            texts = {}
            images.each do |fname|
                textfname="#{fname}.txt"
                if File.exist? textfname
                    text=File.open(textfname) {|f| f.read}
                    texts[fname]=text
                end
            end
            texts
        end


    end

  class Helper
    def self.relativise level
      relative = './'
      level.times do
        relative += '../'
      end

      relative
    end
    
    def self.indexName aPage = 0
        aPage == 0 ? "index.html" : "index_#{aPage.to_s.rjust(4).tr(' ','0')}.html"        
    end

    def self.analytics opts
        ac = opts[:google_analytics]
        return if not ac or ac.length==0
        %Q{<script type="text/javascript">
var gaJsHost = (("https:" == document.location.protocol) ? "https://ssl." : "http://www.");
document.write(unescape("%3Cscript src='" + gaJsHost + "google-analytics.com/ga.js' type='text/javascript'%3E%3C/script%3E"));
</script>
<script type="text/javascript">
var pageTracker = _gat._getTracker("#{ac}");
pageTracker._trackPageview();
</script>
}
    end

    def self.copyright opts
        cp = opts[:copyright]
        cp = "All rights reserved."  unless cp
        cp = "#{opts[:author_label]} #{opts[:author]}<br />#{cp}"
        %Q{
    <div class="copyright">
    <p class="license">
        #{cp}
      </p>
      <p class="software">Generated by <a href="http://rhotoalbum.rubyforge.org/" title="Photo album generator"><em>Rhotoalbum</em>  - a photo album generator.</a></p>
      </div>
    }
    end

    def self.symbolize aHash
        return unless aHash
        ih={}
        aHash.each {|n,v| ih[n.to_sym]=v}
        ih
    end

    # try to load opts in the current directory
    def self.loadOpts        
        symbolize(YAML.load_file( RhotoAlbum::OPTIONS_FILE) ) if File.exist? RhotoAlbum::OPTIONS_FILE
    end

  end

  class Entities
    @map = {
        '<' => 'lt', 
        '>' => 'gt',
        '&' => 'amp',
        "'" => 'apos',
        '"' => 'quot'
    }

    def self.encode! aString
        return aString unless aString and aString.length>0
        return aString.gsub!(/[<>'"&]/) { |char|
            "&#{@map[char]};"
        }
    end

    def self.encode aString
        return aString unless aString and aString.length>0 
        return aString.gsub(/[<>'"&]/) { |char|
            "&#{@map[char]};"
        }
    end

  end

  class Runtime 
    def go cmd = nil
      globalOpts = Helper::loadOpts
      puts "Global options.yml #{globalOpts ? 'found' : 'not found, using defaults'}."
      generator = Generator.new RhotoAlbum::DEFAULTS.merge( globalOpts || {})    
      generator.execute( cmd, ['.'] )
    end
  end
end

#If executed from command line
if __FILE__ == $0
    
    cmd = (ARGV.shift or 'generate')
    #check cmd line
    puts('Usage: rhotoalbum.rb [ text | generate | clean | cleanindex | cleanhighlight | rebuild | help]') or exit if cmd=~/help|-h/i or not RhotoAlbum::CMDS.include?(cmd) 
    puts "Rhotoalbum #{RhotoAlbum::VERSION}"
    puts "exifr library: #{EXIF_LIB ? '' : 'not '}found."
    puts "RMagick library: #{RMAGICK_LIB ? 'found' : 'not found (cannot use effects)'}."

    #go for it
    RhotoAlbum::Runtime.new.go cmd
end

