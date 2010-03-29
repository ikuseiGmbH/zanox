# require 'rubygems'
# require 'rubygems/gem_runner'
# #Gem.manage_gems
# require 'rake/gempackagetask'
require 'rake'

spec = Gem::Specification.new do |s|
    s.platform  =   Gem::Platform::RUBY
    s.name      =   %q{zanox}
    s.version   =   "0.0.1"
    s.authors   =   ["Krispin Schulz"]
    s.homepage  =   %q{http://www.zanox.com/}
    s.date      =   %q{2010-03-16}
    s.email     =   %q{krispinone@googlemail.com}
    s.summary   =   %q{One gem to rule the zanox web services.}
    s.description =   %q{The easy way to the zanox web services.}
    s.files     =   FileList['Rakefile', 'zanox.gemspec', 'README', 'lib/**/*', 'test/*', 'spec/*'].to_a
    s.require_paths  =   ["lib"]
    s.rubygems_version = %q{1.3.5}
    s.test_files = Dir.glob("{test, spec}/**/*")
    # include README while generating rdoc
    s.rdoc_options = ["--main", "README"]
    s.has_rdoc  =   true
    s.extra_rdoc_files  =   ["README"]
    s.add_dependency("soap4r",">=1.5.8")
end

# Rake::GemPackageTask.new(spec) do |pkg|
#     pkg.need_tar = true
# end
# 
# task :default => "pkg/#{spec.name}-#{spec.version}.gem" do
#     puts "generated latest version"
# end