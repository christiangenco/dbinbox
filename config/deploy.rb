# from http://gembundler.com/deploying.html
# require "bundler/capistrano"

# random RVM bug fixes
set :default_environment, {
  'PATH' => "/usr/local/rvm/gems/ruby-1.9.2-p290/bin:/usr/local/rvm/gems/ruby-1.9.2-p290@global/bin:/usr/local/rvm/rubies/ruby-1.9.2-p290/bin:/usr/local/rvm/bin:$PATH",
  'RUBY_VERSION' => 'ruby-1.9.2-p290',
  'GEM_HOME'     => '/usr/local/rvm/gems/ruby-1.9.2-p290',
  'GEM_PATH'     => '/usr/local/rvm/gems/ruby-1.9.2-p290:/usr/local/rvm/gems/ruby-1.9.2-p290@global',
  'BUNDLE_PATH'  => '/usr/local/rvm/gems/ruby-1.9.2-p290/bin/'  # If you are using bundler.
}
namespace :rvm do
  task :trust_rvmrc do
    run "rvm rvmrc trust #{release_path}"
  end
end
# after "deploy", "rvm:trust_rvmrc"

# fixes "No such file or directory" on public/[images, stylesheets, javascripts]
set :normalize_asset_timestamps, false


set :application, "dbinbox" # Application name.
set :location, "dbinbox.com" # Web server url.
set :user, "cgenco" # Remote user name. Must be able to log in via SSH.
# set :port, 2897 # SSH port. Only required if non default ssh port used.
set :use_sudo, false # Remove or set the true if all commands should be run through sudo.

set :local_user, "cgenco" # Local user name.

set :deploy_to, "/u/apps/#{application}"
set :deploy_via, :copy # Copy the files across as an archive rather than using Subversion on the remote machine.
# set :copy_dir, "/home/#{local_user}/tmp/capistrano" # Directory in which the archive will be created. Defaults to /tmp. Note that I had problems with /tmp because on my machine it's on a different partition to the rest of my filesystem and hence a hard link could not be created across devices.
# set :copy_remote_dir, "/home/#{user}/tmp/capistrano" # Directory on the remote machine where the archive will be copied. Defaults to /tmp.

# Use without Subversion on local machine.
# set :repository,  "public"
set :repository,  "."
set :scm, :none

# Use with Subversion on local machine.
# set :repository,  "file:///home/#{local_user}/repositories/#{application}/public"
# set :copy_cache, "#{copy_dir}/#{application}" # Directory in which the local copy will reside. Defaults to /tmp/#{application}. Note that copy_dir must not be the same as (nor inside) copy_cache and copy_cache must not exist before deploy:cold.
# set :copy_exclude, [".svn", "**/.svn"] # Prevent Subversion directories being copied across.


role :app, location
role :web, location
role :db,  location, :primary => true

# Override default tasks which are not relevant to a non-rails app.
namespace :deploy do
  desc "Make symlink for users database" 
  task :symlink_database do
    run "ln -nfs #{shared_path}/users.db #{release_path}/users.db" 
  end

  task :start, :roles => [:web, :app] do
    run "cd #{deploy_to}/current && bundle exec thin -C thin/production_config.yml -R config.ru start"
  end
 
  task :stop, :roles => [:web, :app] do
    run "cd #{deploy_to}/current && bundle exec thin -C thin/production_config.yml -R config.ru stop"
  end
 
  task :restart, :roles => [:web, :app] do
    deploy.stop
    deploy.start
  end
 
  # This will make sure that Capistrano doesn't try to run rake:migrate (this is not a Rails project!)
  task :cold do
    deploy.update
    deploy.start
  end
end
after 'deploy:update_code', 'deploy:symlink_database'