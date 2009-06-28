#
# Author:: Sean Cribbs (<seancribbs@gmail.com>)
# Copyright:: Copyright (c) 2009 Opscode, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'chef/resource/package'
require 'chef/provider/package/source'

class Chef::Resource::SourcePackage < Chef::Resource::Package
  ArchiveTypes = {
      :tar => /\.tar$/i,
      :gzip => /\.(tgz|tar\.gz)$/i,
      :bzip2 => /\.tar\.bz(ip)?2$/i,
      :zip => /\.zip/i
  } unless defined?(ArchiveTypes)

  def initialize(name, collection=nil, node=nil)
    super
    reset!
    @resource_name = :source_package
    @provider = Chef::Provider::Package::Source
    @action = :install
    @configure = true
    @configure_command = "./configure"
    @build_command = "make"
    @install_command = "make install"
    @allowed_actions.push(:download, :unpack, :configure, :build, :force_install)
  end

  def configure(value=nil)
    set_or_return(:configure, value, :kind_of => [TrueClass, FalseClass, String, Array, Hash])
  end

  def environment(value=nil)
    set_or_return(:environment, value, :kind_of => [Hash])
  end
  
  # String attributes
  %w{source cookbook checksum unpack_command configure_command build_command install_command remove_command purge_command}.each do |prop|
    class_eval %Q{
      def #{prop}(value=nil)
        set_or_return(:#{prop}, value, :kind_of => [String])
      end
    }
  end

  # Boolean attributes
  %w{unpacked configured built installed}.each do |prop|
    class_eval %Q{
      def #{prop}(value=nil)
        set_or_return(:#{prop}, value, :kind_of => [TrueClass, FalseClass])
      end
    }
  end

  def unpacks_to(value=nil)
    unless value.nil?
      validate({:unpacks_to => value}, {:unpacks_to => {:kind_of => [String]}})
      @unpacks_to = value 
    end
    @unpacks_to || filename.sub(ArchiveTypes[archive_type], '')
  end

  # Calculated attributes
  def filename
    @source && ::File.basename(@source)
  end

  def archive_type
    if pair = ArchiveTypes.find {|k,v| filename =~ v }
      pair.first
    else
      :unknown
    end
  end

  # Reset the state of the package so it can go from nothing again.
  def reset!
    @unpacked = @configured = @built = @installed = false
  end

end