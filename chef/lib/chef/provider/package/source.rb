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

require 'chef/provider/package'
require 'chef/mixin/command'
require 'chef/resource/source_package'
require 'chef/file_cache'

class Chef::Provider::Package::Source < Chef::Provider::Package
  include Chef::Mixin::Command

  UnpackCommands = {
    :tar => "tar xf",
    :gzip => "tar xzf",
    :bzip2 => "tar xjf",
    :zip => "unzip"
  } unless defined?(UnpackCommands)

  def load_current_resource
    @current_resource = if Chef::FileCache.has_key?(serialize_path)
      Chef::Log.debug("Loading stored source package state from #{serialize_path}")
      JSON.parse(Chef::FileCache.load(serialize_path))
    else
      Chef::Resource::SourcePackage.new(@new_resource.name)
    end
  end

  def action_download
    file = Chef::Resource::RemoteFile.new(download_path, @new_resource.collection, @new_resource.node)
    file.source(@new_resource.source)
    file.cookbook(@new_resource.cookbook)
    file.backup(false)
    result = file.run_action(:create_if_missing)
    if result
      @current_resource.reset!
      serialize_resource
      @new_resource.updated = true
    elsif result.nil?
      true
    end
  end

  def action_unpack
    if action_download
      if should_unpack?
        if unpack_package(download_path, @new_resource.archive_type)
          @new_resource.unpacked true
          serialize_resource
          @new_resource.updated = true
        else
          FileUtils.rm_rf(unpack_path) # Cleanup any stray files for next run
          @new_resource.unpacked false
        end
      else
        @new_resource.unpacked true
        serialize_resource
        true
      end
    else
      false
    end
  end

  def action_configure
    if action_unpack
      if should_configure?
        if configure_package(unpack_path, @new_resource.configure_command, @new_resource.configure)
          @new_resource.configured true
          serialize_resource
          @new_resource.updated = true
        else
          @new_resource.configured false
          serialize_resource
          false
        end
      else
        @new_resource.configured true
        serialize_resource
        true
      end
    else
      false
    end
  end

  def action_build
    if action_configure
      if should_build?
        if build_package(unpack_path, @new_resource.build_command)
          @new_resource.built true
          serialize_resource
          @new_resource.updated = true
        else
          @new_resource.built false
          serialize_resource
          false
        end
      else
        @new_resource.built true
        serialize_resource
        true
      end
    else
      false
    end
  end

  def action_install
    if action_build
      if should_install?
        if install_package(unpack_path, @new_resource.install_command)
          @new_resource.installed true
          serialize_resource
          @new_resource.updated = true
        else
          @new_resource.installed false
          serialize_resource
          false
        end
      else
        @new_resource.installed true
        serialize_resource
        true
      end
    else
      false
    end
  end

  def action_upgrade
    action_install
  end

  def action_force_install
    @current_resource.reset!
    action_install
  end
  
  def unpack_package(file, type)
    command = @new_resource.unpack_command || UnpackCommands[@new_resource.archive_type]
    raise ArgumentError, "don't know how to unpack #{file} of type #{type}" unless command
    run_command(:command => "#{command} #{::File.basename(file)}", :cwd => ::File.dirname(file), :environment => @new_resource.environment)
  end

  def configure_package(dir, command, config)
    command = "#{command} #{Autoconf.switches(config)}".strip
    run_command(:command => command, :cwd => dir, :environment => @new_resource.environment)
  end

  def build_package(dir, command)
    run_command(:command => command, :cwd => dir, :environment => @new_resource.environment)
  end

  def install_package(dir, command)
    run_command(:command => command, :cwd => dir, :environment => @new_resource.environment)
  end

  def should_unpack?
    !@current_resource.unpacked && !::File.directory?(unpack_path)
  end

  def should_configure?
    @new_resource.configure && (
      !@current_resource.configured ||
      @new_resource.version != @current_resource.version ||
      @new_resource.configure != @current_resource.configure
    )
  end

  def should_build?
    !@current_resource.built || 
    @new_resource.version != @current_resource.version ||
    @new_resource.configure != @current_resource.configure
  end

  def should_install?
    !@current_resource.installed ||
    @new_resource.version != @current_resource.version ||
    @new_resource.configure != @current_resource.configure
  end

  def unpack_path
    ::File.join(Chef::FileCache.create_cache_path("build-packages"), @new_resource.unpacks_to)
  end

  def download_path
    ::File.join(Chef::FileCache.create_cache_path('build-packages'), @new_resource.filename)
  end

  def serialize_path
    "source-packages/#{@new_resource.name}"
  end

  def serialize_resource
    Chef::Log.debug("Serializing source package '#{@new_resource.to_s}' state to #{serialize_path}")
    Chef::FileCache.store(serialize_path, @new_resource.to_json)
  end

  module Autoconf
    extend self

    def switches(config=nil)
      case config
      when String
        switch(config)
      when Enumerable
        config.map {|item| switch(item) }.join(" ").strip
      else
        ""
      end
    end

    private
    def switch(*items)
      items = items.flatten
      case items.size
      when 1
        plain_switch(items.first)
      when 2
        value_switch(items.first, items.last)
      else
        ""
      end
    end

    def plain_switch(sw)
      if sw.respond_to?(:to_s)
        if sw.to_s =~ /^\s*(-|$)/
          sw
        else
          "--#{sw}"
        end
      else
        ""
      end
    end

    def value_switch(key, value)
      if value && key.respond_to?(:to_s) && value.respond_to?(:to_s)
        value == true ? plain_switch(key) : "--#{key}=#{value}"
      else
        ""
      end
    end
  end
end