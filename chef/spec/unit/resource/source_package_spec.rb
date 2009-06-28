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

require File.expand_path(File.join(File.dirname(__FILE__), "..", "..", "spec_helper"))

describe Chef::Resource::SourcePackage do
  before :each do
    @resource = Chef::Resource::SourcePackage.new("emacs")
  end

  it "should inherit from the Package resource" do
    @resource.should be_kind_of(Chef::Resource::Package)
  end

  it "should use the Chef::Provider::Package::Source provider" do
    @resource.provider.should == Chef::Provider::Package::Source
  end

  it "should set the resource name to :source_package" do
    @resource.resource_name.should == :source_package
  end

  describe "defaults" do
    it "source should be nil" do
      @resource.source.should be_nil
    end

    it "cookbook should be nil" do
      @resource.cookbook.should be_nil
    end

    it "configure should be true" do
      @resource.configure.should == true
    end

    it "configure_command should be './configure'" do
      @resource.configure_command.should == "./configure"
    end

    it "build_command should be 'make'" do
      @resource.build_command.should ==  'make'
    end

    it "install_command should be 'make install'" do
      @resource.install_command.should == "make install"
    end

    it "remove_command should be nil" do
      @resource.remove_command.should be_nil
    end

    it "purge_command should be nil" do
      @resource.purge_command.should be_nil
    end

    it "action should be :install" do
      @resource.action.should == :install
    end
  end

  describe "actions" do
    %w{install upgrade remove purge download unpack configure build force_install}.each do |a|
      it "should allow :#{a}" do
        @resource.allowed_actions.should include(a.to_sym)
      end
    end
  end

  describe "configure" do
    it "should allow true/false" do
      lambda { @resource.configure true }.should_not raise_error
      @resource.configure.should be_true
      lambda { @resource.configure false }.should_not raise_error
      @resource.configure.should be_false
    end

    it "should allow strings" do
      lambda { @resource.configure "--prefix=/usr/local" }.should_not raise_error
      @resource.configure.should == "--prefix=/usr/local"
    end

    it "should allow arrays" do
      lambda { @resource.configure ["--prefix=/usr/local", "--with-debug"] }.should_not raise_error
      @resource.configure.should == ["--prefix=/usr/local", "--with-debug"]
    end

    it "should allow hashes" do
      lambda { @resource.configure :prefix => "/usr/local" }.should_not raise_error
      @resource.configure.should == {:prefix => "/usr/local"}
    end
  end

  describe "environment" do
    it "should allow hashes" do
      lambda { @resource.environment 'HOME' => '/root' }.should_not raise_error
      @resource.environment.should == {'HOME' => '/root'}
    end
  end

  %w{source cookbook unpack_command configure_command build_command install_command remove_command purge_command}.each do |prop|
    describe prop do
      it "should allow strings" do
        lambda { @resource.send(prop, "opscode is totally metal") }.should_not raise_error
        @resource.send(prop).should == "opscode is totally metal"
      end

      it "should not allow hashes" do
        lambda { @resource.send(prop, :opscode => "totally metal") }.should raise_error
      end
    end
  end

  %w{unpacked configured built installed}.each do |prop|
    describe prop do
      it "should be false by default" do
        @resource.send(prop).should be_false
      end
      
      it "should allow true/false" do
        lambda { @resource.send(prop, true) }.should_not raise_error
        @resource.send(prop).should be_true
        lambda { @resource.send(prop, false) }.should_not raise_error
        @resource.send(prop).should be_false
      end

      describe "when resetting" do
        it "should be set to false" do
          @resource.send(prop, true)
          @resource.reset!
          @resource.send(prop).should be_false
        end
      end
    end
  end
  
  describe "filename" do
    it "should equal the basename of the source URL" do
      @resource.source "http://foobar.com/package.tgz"
      @resource.filename.should == "package.tgz"
    end
  end
  
  describe "archive_type" do
    it "should be :gzip for .tar.gz and .tgz" do
      @resource.source "http://foobar.com/package.tgz"
      @resource.archive_type.should == :gzip
      @resource.source "http://foobar.com/package.tar.gz"
      @resource.archive_type.should == :gzip
    end
    
    it "should be :bzip2 for .tar.bz2 and .tar.bzip2" do
      @resource.source "http://foobar.com/package.tar.bz2"
      @resource.archive_type.should == :bzip2
      @resource.source "http://foobar.com/package.tar.bzip2"
      @resource.archive_type.should == :bzip2
    end
    
    it "should be :tar for .tar" do
      @resource.source "http://foobar.com/package.tar"
      @resource.archive_type.should == :tar
    end
    
    it "should be :zip for .zip" do
      @resource.source "http://foobar.com/package.zip"
      @resource.archive_type.should == :zip
    end
  end
  
  describe "unpacks_to" do
    it "should default to the stem of the filename" do
      @resource.source "http://foobar.com/package.tgz"
      @resource.unpacks_to.should == "package"
    end
    
    it "should accept a string" do
      lambda { @resource.unpacks_to "foobar" }.should_not raise_error
      @resource.unpacks_to.should == "foobar"
    end
  end
end