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

require File.expand_path(File.join(File.dirname(__FILE__), "..", "..", "..", "spec_helper"))

describe Chef::Provider::Package::Source do
  before :each do
    Chef::Config[:file_cache_path] = '/tmp/foo'
    Chef::Config[:solo] = true
    Chef::Config[:cookbook_path] = [File.expand_path(File.join(File.dirname(__FILE__), "..", "..", "..", 'data', 'cookbooks'))]
    @node = Chef::Node.new
    @node.name "foobar"
    @node[:platform] = "ubuntu"
    @node[:platform_version] = "9.04"
    @resource = Chef::Resource::SourcePackage.new("emacs", nil, @node)
    @provider = Chef::Provider::Package::Source.new(@node,@resource)
    @resource.cookbook 'emacs'
    @resource.source 'emacs.tar.gz'
    @download_path = @provider.send(:download_path)
    @unpack_path = @provider.send(:unpack_path)
    @metadata_path = Chef::FileCache.create_cache_path(@provider.send(:serialize_path),false)
    @provider.load_current_resource
  end

  after :each do
    # Make sure we don't keep any state in our tests
    FileUtils.rm_rf Chef::FileCache.create_cache_path('source-packages',false)
    FileUtils.rm_rf Chef::FileCache.create_cache_path('build-packages',false)
  end

  describe "load_current_resource" do
    before :each do
      @provider.current_resource = nil
    end

    it "should create a new blank resource if no serialized data was found" do
      FileUtils.rm_rf Chef::FileCache.create_cache_path('source-packages',false)
      @provider.load_current_resource
      @provider.current_resource.name.should == "emacs"
      @provider.current_resource.source.should be_nil
    end

    it "should load serialized data from the cache file" do
      FileUtils.mkdir_p Chef::FileCache.create_cache_path('source-packages',true)
      current_resource = Chef::Resource::SourcePackage.new('emacs')
      current_resource.version '10.0'
      current_resource.unpacked true
      File.open(@metadata_path, 'w'){|f| f.write current_resource.to_json }
      @provider.load_current_resource
      @provider.current_resource.version.should == '10.0'
      @provider.current_resource.name.should == 'emacs'
      @provider.current_resource.unpacked.should be_true
    end
  end

  describe "download action" do
    before :each do
      @resource.cookbook 'emacs'
      @resource.source 'emacs.tar.gz'
    end

    it "should download the file if it doesn't exist" do
      # Let's copy from a local cookbook
      @provider.action_download.should be_true
      File.exist?(@download_path).should be_true
    end

    it "should not download the file if it exists" do
      FileUtils.cp(File.expand_path(File.join(File.dirname(__FILE__), "..", "..", "..", 'data', 'cookbooks', 'emacs','files','default', 'emacs.tar.gz')), @download_path)
      @provider.action_download.should be_true
    end
  end

  describe "should_unpack?" do
    it "should be true when the unpack directory is missing and the current resource is not unpacked" do
      @provider.current_resource.unpacked false
      FileUtils.rm_rf(@unpack_path)
      @provider.should_unpack?.should be_true
    end

    it "should be false when the package is already unpacked" do
      @provider.current_resource.unpacked true
      @provider.should_unpack?.should be_false
    end

    it "should be false when the unpack directory exists" do
      FileUtils.mkdir_p(@unpack_path)
      @provider.should_unpack?.should be_false
    end
  end

  describe "unpack action" do
    before :each do
      FileUtils.cp(File.expand_path(File.join(File.dirname(__FILE__), "..", "..", "..", 'data', 'cookbooks', 'emacs','files','default', 'emacs.tar.gz')), @download_path)
    end

    after :each do
      FileUtils.rm_rf(@provider.send(:unpack_path))
    end

    it "should require the archive to be downloaded" do
      @provider.should_receive(:action_download).and_return(true)
      @provider.action_unpack.should be_true
    end

    it "should unpack the file with the default command" do
      @provider.should_receive(:run_command).with(hash_including(:command => "tar xzf emacs.tar.gz")).and_return(true)
      @provider.action_unpack.should be_true
    end

    it "should unpack the file with the specified command" do
      @provider.should_receive(:run_command).with(hash_including(:command => "tar xzvf emacs.tar.gz")).and_return(true)
      @resource.unpack_command "tar xzvf"
      @provider.action_unpack.should be_true
    end

    it "should cleanup the unpack directory if the command fails" do
      FileUtils.mkdir_p(@provider.send(:unpack_path))
      @provider.should_receive(:should_unpack?).and_return(true)
      @provider.should_receive(:unpack_package).and_return(false)
      @provider.action_unpack.should be_false
      File.directory?(@provider.send(:unpack_path)).should be_false
    end
  end

  describe "should_configure?" do
    before :each do
      @provider.current_resource.configured true
      @provider.current_resource.version '10'
      @provider.current_resource.configure true
      @resource.version '10'
      @resource.configure true
    end

    it "should be true when the current resource is not configured" do
      @provider.current_resource.configured false
      @provider.should_configure?.should be_true
    end

    it "should be true when the new resource has a different version" do
      @resource.version "11"
      @provider.should_configure?.should be_true
    end

    it "should be true when the new resource has a different configuration" do
      @resource.configure :debug => true
      @provider.should_configure?.should be_true
    end

    it "should be false when the new resource doesn't need configuring" do
      @resource.configure false
      @provider.should_configure?.should be_false
    end

    it "should be false when the current and new resource are the same" do
      @provider.should_configure?.should be_false
    end
  end

  describe "configure action" do
    before :each do
      @resource.configure true
      @provider.stub!(:action_unpack).and_return(true)
    end

    it "should configure the package" do
      @provider.should_receive(:run_command).with(hash_including(:command => "./configure")).and_return(true)
      @provider.action_configure
      @resource.configured.should be_true
    end

    it "should not execute anything if the package doesn't need configuring" do
      @provider.should_receive(:should_configure?).and_return(false)
      @provider.should_not_receive(:run_command).with(hash_including(:command => "./configure")).and_return(true)
      @provider.action_configure
      @resource.configured.should be_true
    end

    it "should apply the configure switches to the configure command" do
      @resource.configure :prefix => "/usr/local"
      @provider.should_receive(:run_command).with(hash_including(:command => "./configure --prefix=/usr/local")).and_return(true)
      @provider.action_configure
      @resource.configured.should be_true
    end

    it "should not be configured when the unpack fails" do
      @provider.should_receive(:action_unpack).and_return(false)
      @provider.action_configure.should be_false
      @resource.configured.should be_false
    end

    it "should not be configured when the command fails" do
      @provider.should_receive(:run_command).and_return(false)
      @provider.action_configure.should be_false
      @resource.configured.should be_false
    end
  end

  describe "should_build?" do
    before :each do
      @provider.current_resource.built true
      @provider.current_resource.version '10'
      @provider.current_resource.configure true
      @resource.version '10'
      @resource.configure true
    end

    it "should be true when the current resource is not built" do
      @provider.current_resource.built false
      @provider.should_build?.should be_true
    end

    it "should be true when the version is different" do
      @resource.version '11'
      @provider.should_build?.should be_true
    end

    it "should be true when the configuration is different" do
      @resource.configure :debug => true
      @provider.should_build?.should be_true
    end

    it "should be false when the current resource is built and the resources are the same" do
      @provider.should_build?.should be_false
    end
  end
  
  describe "build action" do
    before :each do
      @provider.stub!(:action_configure).and_return(true)
      @provider.stub!(:should_build?).and_return(true)
    end
    
    it "should configure before building" do
      @provider.should_receive(:action_configure).and_return(true)
      @provider.should_receive(:run_command).and_return(true)
      @provider.action_build
    end
    
    it "should run the build command" do
      @provider.should_receive(:run_command).with(hash_including(:command => "make")).and_return(true)
      @provider.action_build.should be_true
      @resource.built.should be_true
    end
    
    it "should use a command specified by the resource" do
      @provider.should_receive(:run_command).with(hash_including(:command => "rake")).and_return(true)
      @resource.build_command 'rake'
      @provider.action_build.should be_true
      @resource.built.should be_true
    end
    
    it "should not be built when the build command fails" do
      @provider.should_receive(:run_command).and_return(false)
      @provider.action_build.should be_false
      @resource.built.should be_false
    end
    
    it "should not run the build_command when should_build? is false" do
      @provider.should_receive(:should_build?).and_return(false)
      @provider.should_not_receive(:run_command)
      @provider.action_build.should be_true
    end
  end

  describe "should_install?" do
    before :each do
      @provider.current_resource.installed true
      @provider.current_resource.version '10'
      @provider.current_resource.configure true
      @resource.version '10'
      @resource.configure true
    end

    it "should be true when the current resource is not built" do
      @provider.current_resource.installed false
      @provider.should_install?.should be_true
    end

    it "should be true when the version is different" do
      @resource.version '11'
      @provider.should_install?.should be_true
    end

    it "should be true when the configuration is different" do
      @resource.configure :debug => true
      @provider.should_install?.should be_true
    end

    it "should be false when the current resource is built and the resources are the same" do
      @provider.should_install?.should be_false
    end
  end
  
  describe "install action" do
    before :each do
      @provider.stub!(:action_build).and_return(true)
      @provider.stub!(:should_install?).and_return(true)
    end
    
    it "should build before installing" do
      @provider.should_receive(:action_build).and_return(true)
      @provider.should_receive(:run_command).and_return(true)
      @provider.action_install
    end
    
    it "should run the install command" do
      @provider.should_receive(:run_command).with(hash_including(:command => "make install")).and_return(true)
      @provider.action_install.should be_true
      @resource.installed.should be_true
    end
    
    it "should use a command specified by the resource" do
      @provider.should_receive(:run_command).with(hash_including(:command => "rake install")).and_return(true)
      @resource.install_command 'rake install'
      @provider.action_install.should be_true
      @resource.installed.should be_true
    end
    
    it "should not be installed when the install command fails" do
      @provider.should_receive(:run_command).and_return(false)
      @provider.action_install.should be_false
      @resource.installed.should be_false
    end
  end
end

describe "Chef::Provider::Package::Source::Autoconf" do
  describe "switches" do
    it "should return an empty string by default" do
      Chef::Provider::Package::Source::Autoconf.switches.should == ""
    end
    it "should process an empty string untouched" do
      Chef::Provider::Package::Source::Autoconf.switches("").should == ""
    end
    it "should process a string without embedded switches as prefixed with --" do
      Chef::Provider::Package::Source::Autoconf.switches("debug").should == "--debug"
    end
    it "should process a string with embedded switches untouched" do
      Chef::Provider::Package::Source::Autoconf.switches("--debug").should == "--debug"
    end
    it "should process a hash as switches joined with =" do
      Chef::Provider::Package::Source::Autoconf.switches(:prefix => "/usr/local").should == "--prefix=/usr/local"
    end
    it "should process a hash with true values as singleton switches" do
      Chef::Provider::Package::Source::Autoconf.switches('with-ssl' => true, 'with-ssl-proxy' => true).should == "--with-ssl --with-ssl-proxy"
    end
    it "should process a hash with nil or false values ignoring those switches" do
      Chef::Provider::Package::Source::Autoconf.switches('debug' => false, 'with-poll' => nil).should == ""
    end
    it "should process an array with nil values ignoring them" do
      Chef::Provider::Package::Source::Autoconf.switches([nil]).should == ""
      Chef::Provider::Package::Source::Autoconf.switches(["debug", nil]).should == "--debug"
    end
  end
end