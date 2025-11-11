#!/bin/bash

install_ruby(){
    apt -y install ruby3.2

    ruby -v

cat > ruby_test.rb <<'EOF' 
    msg = Class.send(:new, String);
    mymsg = msg.send(:new, "Hello Ruby World !\n");
    STDOUT.send(:write, mymsg)
EOF

    ruby ruby_test.rb

}

install_packages() {

    apt -y install ruby-dev libmysqlclient-dev gcc make yarnpkg libxml2 libxml2-dev libxslt-dev libyaml-dev nodejs git
}

install_rails() {

    gem install bundler
    gem install nokogiri -- --use-system-libraries
    gem install rails -N --version='~> 7.0, < 8.0'
    rails -v
}


install_ruby
install_packages
install_rails




