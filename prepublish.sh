#!/bin/bash

# Pimatic-Telegram npm prepublish script

TELEGRAM_DIR=~/pimatic-dev/node_modules/pimatic-telegram
TELEBOT_DIST_DIR=$TELEGRAM_DIR/node_modules/telebot/dist
GULP=$TELEGRAM_DIR/node_modules/gulp/bin/gulp.js

# install telebot and gulp with dependencies
cd $TELEGRAM_DIR/node_modules
if [ ! -d "telebot" ]; then
  npm install git+https://github.com/sentzu01/telebot.git
fi
if [ ! -d "gulp" ]; then
  npm install gulp --save-dev
fi
if [ ! -d "gulp-babel" ]; then
  npm install gulp-babel --save-dev
fi
if [ ! -d "babel-core" ]; then
  npm install babel-core --save-dev
fi
if [ ! -d "babel-register" ]; then
  npm install babel-register --save-dev
fi

# transpile telebot js files
cd $TELEGRAM_DIR
nodejs $GULP # automatically loads gulpfile.babel.js

# check files into git repository
cd $TELEBOT_DIST_DIR
git add *.js
git commit -a -m "transpiled for latest changes"
git push
