#!/bin/bash

# Pimatic-Telegram npm prepublish script

TELEGRAM_DIR=~/pi/pimatic-dev/node_modules/pimatic-telegram
TELEBOT_DIST_DIR=$TELEGRAM_DIR/node_modules/telebot/dist
GULP=$TELEGRAM_DIR/node_modules/gulp/bin/gulp.js

# transpile telebot js files
cd $TELEGRAM_DIR
nodejs $GULP # automatically loads gulpfile.babel.js

# check files into git repository
cd $TELEBOT_DIST_DIR
git add *.js
git commit -a -m "transpiled for latest changes"
git push
