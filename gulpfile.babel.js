const gulp = require('gulp');
const babel = require('gulp-babel');
 
gulp.task('telebot', () => {
    return gulp.src('./node_modules/telebot/lib/*.js')
        .pipe(babel({
            presets: ['es2015']
        }))
        .pipe(gulp.dest('./node_modules/telebot/dist'));
});