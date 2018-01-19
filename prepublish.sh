#!/bin/bash

# Pimatic-Telegram npm prepublish script

TELEGRAM_DIR=~/pimatic-dev/node_modules/pimatic-telegram
TELEBOT_DIR=$TELEGRAM_DIR/node_modules/telebot
DIST_DIR=$TELEBOT_DIR/dist
PLUGINS_SRC_DIR=$TELEBOT_DIR/plugins.src
PLUGINS_DIR=$TELEBOT_DIR/plugins
GULP=$TELEGRAM_DIR/node_modules/gulp/bin/gulp.js


cd $TELEGRAM_DIR/node_modules
if [ ! -d "gulp" ]; then
  npm install gulp --save-dev
fi
if [ ! -d "gulp-babel" ]; then
  npm install gulp-babel --save-dev
fi
if [ ! -d "babel-core" ]; then
  npm install babel-core --save-dev
fi
if [ ! -d "babel-preset-es2015" ]; then
  npm install babel-preset-es2015 --save-dev
fi

# install telebot and gulp with dependencies

if [ ! -d "telebot" ]; then
  git clone https://github.com/sentzu01/telebot.git
fi

cd $TELEBOT_DIR
git checkout latest

if [ ! -d $DIST_DIR ]; then
  mkdir $DIST_DIR
fi
if [ ! -d $PLUGINS_SRC_DIR ]; then
  if [ -d $PLUGINS_DIR ]; then
    cp -R $PLUGINS_DIR $PLUGINS_SRC_DIR
  else
    mkdir $PLUGINS_SRC_DIR
  fi
fi

# transpile telebot js files
cd $TELEGRAM_DIR
nodejs $GULP # automatically loads gulpfile.babel.js

sudo npm install -g json
cd $TELEBOT_DIR
json -I -f package.json -e 'this.main="dist/telebot.js"'
json -I -f package.json -e 'this.engines.node=">= 4.0.0"'

# check files into git repository
#cd $TELEBOT_DIR
#git add dist/*
#git add plugins/*
#git add plugins.src
#git add package.json
#git commit -m "translated to nodejs 4 compatible Javascript"
#git push
