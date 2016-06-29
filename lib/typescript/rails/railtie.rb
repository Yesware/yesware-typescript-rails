require 'typescript/rails'

class Typescript::Rails::Railtie < ::Rails::Railtie
  config.before_initialize do |app|
    if ::Rails::VERSION::MAJOR >= 4 || app.config.assets.enabled
      require 'typescript/rails/template'
      require 'typescript/rails/tsconfig_template'
      require 'sprockets'
      #Sprockets.register_engine '.ts', Typescript::Rails::Template
      Sprockets.register_engine '.tsconfig', Typescript::Rails::TsconfigTemplate
    end
  end
end
