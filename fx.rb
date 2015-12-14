# Rhotoalbum -- a Ruby photo album generator.
#
# Copyright (C) 2007-2008  Ondrej Jaura, Viktor Zigo
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

require 'optional_require'
optional_require('rubygems')
RMAGICK_LIB = optional_require('RMagick')

def shadow anImage, opts = {}
    aBackground = opts[:background]
    anImage.background_color = '#000'
    shadow = anImage.shadow 5,5, 5.0, 0.5
    shadow.composite!(anImage, Magick::NorthWestGravity, Magick::OverCompositeOp)

    if aBackground
        blackfill = Magick::GradientFill.new(0, 0, anImage.columns, 0, aBackground, aBackground)
        background = Magick::Image.new shadow.columns, shadow.rows, blackfill
        background.composite!(shadow, Magick::NorthWestGravity, Magick::OverCompositeOp)
    else 
        shadow
    end
end

def glow anImage, opts = {}
    aBackground = opts[:background] || "none"
    cols, rows = anImage.columns, anImage.rows
    blackfill = Magick::GradientFill.new(0, 0, cols, 0, aBackground, aBackground)
    background = Magick::Image.new cols, rows, blackfill

    anImage.resize!( cols*0.89, rows*0.89 )
    shadow = anImage.clone

#    shadow.resize!( cols*0.9, rows*0.9 )
    shadow = background.composite!(shadow, Magick::CenterGravity, Magick::OverCompositeOp)
    shadow = shadow.blur_image(10, 10) 
    shadow.composite!(anImage, Magick::CenterGravity, Magick::OverCompositeOp)
end


def reflection anImage, opts = {}
    aBackground = opts[:background]
    anImage.border!(5, 5, "none")

    reflection = anImage.wet_floor 0.7, 1.0
    #reflection = reflection.distort Magick::PerspectiveDistortion, [0,0,0,0,  20,90,0,90,  90,0,90,0,  90,90,90,90], true
    reflection = reflection.blur_image(0, 3)

    parts = Magick::ImageList.new
    parts << anImage
    parts << reflection
    new = parts.append(true)
    if aBackground
        blackfill = Magick::GradientFill.new(0, 0, anImage.columns, 0, aBackground, aBackground)
        background = Magick::Image.new new.columns, new.rows, blackfill
        new = background.composite!(new, Magick::NorthWestGravity, Magick::OverCompositeOp)
    end
    new
end

def stack anImage, opts = {}
    background = opts[:background]
    images = Magick::ImageList.new
    final = Magick::Image.new( anImage.columns*2, anImage.rows*2) {
            self.background_color = background if background
        }
    5.times {
        images << rotate(anImage.clone, {:rotate_more => true}, true, true)
    }
    
    #flatten
    images.each {|i|
        final.composite!(i, Magick::CenterGravity, Magick::OverCompositeOp)
    }

    final.trim!
end

def polaroid_stack anImage, opts = {}
    background = opts[:background]
    images = Magick::ImageList.new
    final = Magick::Image.new( anImage.columns*2, anImage.rows*2) {
            self.background_color = background if background
        }
    5.times {
        images << polaroid(anImage.clone, {:rotate_more => true}, true, true)
    }
    
    #flatten
    images.each {|i|
        final.composite!(i, Magick::CenterGravity, Magick::OverCompositeOp)
    }

    final.trim!
end

def rotate anImage, opts = {}, randomize = true, shadow = false
    image = anImage

    # Bend the image
    background = opts[:background]
    image.background_color = background || "none"
    ampStrength = randomize ? (0.005*(1+rand(5)))-0.0 : 0.01
    amplitude = image.columns * ampStrength
    wavelength = image.rows  * 2

    image.rotate!(90)
    image = image.wave(amplitude, wavelength)
    image.rotate!(-90)

    tilt = randomize ? ( opts[:rotate_more] ? rand(20)-10 : rand(8)-4 ) : -4
    image.rotate!(tilt)

    if shadow
        image = shadow image,  opts
    end
    #puts "tilt:#{tilt}, yadj:#{yadj}, amp:#{ampStrength}"    
    image.background_color = background || "none"
    image.trim!
end

def polaroid anImage, opts = {}, randomize = true, shadow = true
    image = anImage
    image.border!(14, 14, "#f0f0ff")

    # Bend the image
    background = opts[:background]
    image.background_color = "none"
    ampStrength = randomize ? (0.005*(1+rand(5)))-0.0 : 0.01
    amplitude = image.columns * ampStrength
    wavelength = image.rows  * 2

    image.rotate!(90)
    image = image.wave(amplitude, wavelength)
    image.rotate!(-90)

    tilt = randomize ? ( opts[:rotate_more] ? rand(30)-15 : rand(8)-4 ) : -4
    image.rotate!(tilt)

    if shadow        
        image = shadow image,  opts
    else        
        # Make the shadow
        shadow = image.flop
        shadow = shadow.colorize(1, 1, 1, "gray75")     # shadow color can vary to taste
        shadow.background_color = "white"       # was "none"
        shadow.border!(10, 10, "white")
        shadow = shadow.blur_image(0, 3)        # shadow blurriness can vary according to taste

        # Composite image over shadow. The y-axis adjustment can vary according to taste.
        yadj = randomize ? (-amplitude/2) : (-amplitude/2)
        image = shadow.composite(image, yadj, 5, Magick::OverCompositeOp)
    end
    #puts "tilt:#{tilt}, yadj:#{yadj}, amp:#{ampStrength}"    
    image.background_color = background || "none"
    image.trim!
end

def polaroid2 anImage, opts = {}
    anImage[:caption] = "Hi!"
    anImage = anImage.polaroid { self.gravity = Magick::CenterGravity }
end

def recoverSize! anImage, anOriginalImage
    cols, rows = anOriginalImage.columns, anOriginalImage.rows
    anImage.change_geometry!("#{cols}x#{rows}") do |ncols, nrows, img|
        img.resize!(ncols, nrows)
    end
    anImage
end

def withImage aFname, anOutFname = nil
    image = Magick::Image.read(aFname).first
    new = yield image
    out = anOutFname ? anOutFname : aFname.sub(/\./, "-done.")
    puts "Writing #{out}"
    new.write(out)
end


CMDS=%w{shadow reflection polaroid stack rotate glow polaroid_stack}

def processImage! aFname, aCmd = 'shadow', opts = {}
    raise "No such command '#{aCmd}'"  unless CMDS.include?(aCmd)
    withImage(aFname, aFname ) do |img|
        originalImg = img.clone
        outImg = send aCmd, img, opts
        recoverSize! outImg, originalImg
    end
    aFname
end

if $0==__FILE__
    puts "Missing RMagick library" or exit unless RMAGICK_LIB
    fname = ARGV.shift
    cmd = ARGV.shift || 'shadow'
    color = ARGV.shift
    puts "Applying '#{cmd}'	 on the image '#{fname}'"
    puts "Usage: #{$0} <path-to-image> [#{CMDS.join('|')}] [css-background-color (e.g.\"#000000\" | red)]" or exit unless fname and CMDS.include?(cmd)

    opts = {:background=>color}

    withImage(fname, fname.sub(/\./, "-#{cmd}.") ) do |img|
        originalImg = img.clone
        outImg = send cmd, img, opts
        recoverSize! outImg, originalImg
    end 
end 
